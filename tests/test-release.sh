#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/version.sh
source "$REPOSITORY_ROOT/lib/version.sh"
# shellcheck source=lib/common.sh
source "$REPOSITORY_ROOT/lib/common.sh"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

assert_file_contains() {
    grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_eq "$(release_bump_version 1.2.3 major)" "2.0.0"
assert_eq "$(release_bump_version 1.2.3 minor)" "1.3.0"
assert_eq "$(release_bump_version 1.2.3 patch)" "1.2.4"
assert_eq "$(release_normalize_version 1.3.0rc2)" "1.3.0-rc.2"
assert_eq "$(release_pep440_version 1.3.0-rc.2)" "1.3.0rc2"
assert_eq "$(release_version_from_tag 2.3.4 '')" "2.3.4"
if release_version_from_tag v2.3.4 '' >/dev/null; then
    fail "empty tag prefix accepted a v-prefixed tag"
fi
assert_eq "$(release_moving_tags 2.3.4 v 'major minor')" $'v2\nv2.3'
assert_eq "$(release_moving_tags 2.3.4 '' 'major minor')" $'2\n2.3'
if release_moving_tags 2.3.4 v invalid >/dev/null; then
    fail "invalid moving tag level was accepted"
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/release-tests.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
PROJECT="$TMP_ROOT/project"
REMOTE="$TMP_ROOT/remote.git"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git checkout -q -b main
git config user.name "Release Tests"
git config user.email "release-tests@example.invalid"
printf '1.2.3\n' > VERSION
printf 'dist/\n' > .gitignore
git add VERSION .gitignore
git commit -q -m "Initial project"

export RELEASE_GET_VERSION='cat VERSION'
# Expanded by the configured hook's Bash process.
# shellcheck disable=SC2016
export RELEASE_SET_VERSION='printf "%s\n" "$RELEASE_VERSION" > VERSION'
export RELEASE_CHECK_COMMAND='test -s VERSION'
export RELEASE_BUILD_COMMAND='mkdir -p dist && printf artifact > dist/app.tgz'
export RELEASE_ARTIFACTS='dist/*.tgz'
export RELEASE_TAG_PREFIX='v'
export RELEASE_MOVING_TAGS='major minor'
export RELEASE_BRANCH_PATTERN='main'

"$REPOSITORY_ROOT/lib/release.sh" --no-publish patch >/dev/null
assert_eq "$(cat VERSION)" "1.2.4"
git rev-parse -q --verify refs/tags/v1.2.4 >/dev/null || fail "stable tag was not created"
assert_eq "$(git rev-parse 'v1^{}')" "$(git rev-parse 'v1.2.4^{}')"
assert_eq "$(git rev-parse 'v1.2^{}')" "$(git rev-parse 'v1.2.4^{}')"
assert_file_contains CHANGELOG.md "## 1.2.4 -"
assert_eq "$(git log -1 --pretty=%s)" "chore(release): v1.2.4"

BEFORE=$(git rev-parse HEAD)
PLAN=$("$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run minor)
assert_file_contains <(printf '%s\n' "$PLAN") "Target:  1.3.0"
assert_eq "$(git rev-parse HEAD)" "$BEFORE"

"$REPOSITORY_ROOT/lib/release.sh" --no-publish --pre minor >/dev/null
assert_eq "$(cat VERSION)" "1.3.0-rc.1"
git rev-parse -q --verify refs/tags/v1.3.0-rc.1 >/dev/null || fail "prerelease tag was not created"
assert_eq "$(git rev-parse 'v1^{}')" "$(git rev-parse 'v1.2.4^{}')"

"$REPOSITORY_ROOT/lib/release.sh" --no-publish --promote >/dev/null
assert_eq "$(cat VERSION)" "1.3.0"
git rev-parse -q --verify refs/tags/v1.3.0 >/dev/null || fail "promoted tag was not created"
assert_eq "$(git rev-parse 'v1^{}')" "$(git rev-parse 'v1.3.0^{}')"
assert_eq "$(git rev-parse 'v1.3^{}')" "$(git rev-parse 'v1.3.0^{}')"

git init -q --bare "$REMOTE"
git remote add origin "$REMOTE"

MOCK_BIN="$TMP_ROOT/bin"
GH_LOG="$TMP_ROOT/gh.log"
mkdir -p "$MOCK_BIN"
export GH_LOG
apply_mock="$MOCK_BIN/gh"
# These variables are expanded when the generated mock runs.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'if [[ "$1 $2" == "auth status" ]]; then exit 0; fi' \
    'if [[ "$1 $2" == "api repos/{owner}/{repo}" ]]; then' \
    '  [[ "${GH_REPO_INACCESSIBLE:-}" == true ]] && exit 1' \
    '  printf "%s\n" "${GH_REPO_CAN_PUSH:-true}"' \
    '  exit 0' \
    'fi' \
    'if [[ "$1 $2" == "release view" ]]; then [[ "${GH_RELEASE_EXISTS:-}" == true ]] && exit 0 || exit 1; fi' \
    'printf "%s\n" "$*" >> "$GH_LOG"' > "$apply_mock"
chmod +x "$apply_mock"
PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/github.sh" v1.3.0 >/dev/null
assert_eq "$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')" "origin/main"
assert_eq "$(git --git-dir="$REMOTE" rev-parse 'v1^{}')" "$(git rev-parse 'v1.3.0^{}')"
assert_eq "$(git --git-dir="$REMOTE" rev-parse 'v1.3^{}')" "$(git rev-parse 'v1.3.0^{}')"
assert_file_contains "$GH_LOG" "release create v1.3.0"
assert_file_contains "$GH_LOG" "--verify-tag"

GH_RELEASE_EXISTS=true PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/github.sh" v1.3.0 >/dev/null
assert_file_contains "$GH_LOG" "release edit v1.3.0"
assert_file_contains "$GH_LOG" "release upload v1.3.0"
assert_file_contains "$GH_LOG" "--clobber"

# Retrying an older release must never move aliases backward.
unset RELEASE_MOVING_TAGS
PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/github.sh" v1.2.4 --moving-tags major,minor >/dev/null
assert_eq "$(git --git-dir="$REMOTE" rev-parse 'v1^{}')" "$(git rev-parse 'v1.3.0^{}')"

# Doctor reports configuration mismatches before a release mutates anything.
git tag -a 9.9.9 -m 9.9.9
export RELEASE_MOVING_TAGS='major minor'
DOCTOR_OUTPUT=$(PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" 2>&1)
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "does not match RELEASE_TAG_PREFIX"
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "GitHub repository permission: WRITE"
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "cfg RELEASE_CHECK_COMMAND: test -s VERSION"
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "moving tags: major minor (current aliases: v1 v1.3)"

if GH_REPO_CAN_PUSH=false PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1; then
    fail "doctor accepted read-only GitHub repository access"
fi
DOCTOR_OUTPUT=$(GITHUB_ACTIONS=true GH_REPO_CAN_PUSH=false PATH="$MOCK_BIN:$PATH" \
    "$REPOSITORY_ROOT/lib/doctor.sh" 2>&1)
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "WRITE (Actions Git dry-run)"
if GH_REPO_INACCESSIBLE=true PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1; then
    fail "doctor accepted GitHub authentication without repository access"
fi
DOCTOR_OUTPUT=$(GH_REPO_INACCESSIBLE=true PATH="$MOCK_BIN:$PATH" \
    "$REPOSITORY_ROOT/lib/doctor.sh" 2>&1 || true)
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") \
    "Release readiness checks failed; resolve the ERR lines above."

export RELEASE_MOVING_TAGS=invalid
if PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1; then
    fail "doctor accepted invalid moving tags"
fi
export RELEASE_MOVING_TAGS='major minor'

export RELEASE_ARTIFACTS='missing/*.zip'
DOCTOR_OUTPUT=$(PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" 2>&1)
assert_file_contains <(printf '%s\n' "$DOCTOR_OUTPUT") "build must create them"

export RELEASE_BUILD_COMMAND='missing-release-builder --output dist'
if PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1; then
    fail "doctor accepted a missing build executable"
fi
export RELEASE_BUILD_COMMAND='mkdir -p dist && printf artifact > dist/app.tgz'
export RELEASE_ARTIFACTS='dist/*.tgz'
printf 'configured\n' > .dropboxuploader
unset RELEASE_DROPBOX_PATH
if PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1; then
    fail "doctor accepted Dropbox configuration without an explicit path"
fi
export RELEASE_DROPBOX_PATH='example/releases'
PATH="$MOCK_BIN:$PATH" "$REPOSITORY_ROOT/lib/doctor.sh" >/dev/null 2>&1 || \
    fail "doctor rejected valid Dropbox configuration"
rm -f .dropboxuploader
unset RELEASE_DROPBOX_PATH

# Tag-only projects need no package-manager configuration.
TAG_PROJECT="$TMP_ROOT/tag-only"
mkdir -p "$TAG_PROJECT"
cd "$TAG_PROJECT"
git init -q
git checkout -q -b main
git config user.name "Release Tests"
git config user.email "release-tests@example.invalid"
printf 'example\n' > README.md
git add README.md
git commit -q -m "Initial project"
unset RELEASE_GET_VERSION RELEASE_SET_VERSION RELEASE_CHECK_COMMAND RELEASE_BUILD_COMMAND RELEASE_MOVING_TAGS
export RELEASE_BRANCH_PATTERN='main'
export RELEASE_CHANGELOG=false
export RELEASE_ARTIFACTS='missing/*.zip'
if "$REPOSITORY_ROOT/lib/release.sh" --no-publish patch >/dev/null 2>&1; then
    fail "missing artifacts should stop a release"
fi
git rev-parse -q --verify refs/tags/v0.0.1 >/dev/null 2>&1 && fail "failed release created a tag"

unset RELEASE_ARTIFACTS
export RELEASE_CHECK_COMMAND=false
if "$REPOSITORY_ROOT/lib/release.sh" --no-publish patch >/dev/null 2>&1; then
    fail "failed checks should stop a release"
fi
git rev-parse -q --verify refs/tags/v0.0.1 >/dev/null 2>&1 && fail "failed checks created a tag"

unset RELEASE_CHECK_COMMAND
"$REPOSITORY_ROOT/lib/release.sh" --no-publish patch >/dev/null
git rev-parse -q --verify refs/tags/v0.0.1 >/dev/null || fail "tag-only release was not created"

# Publishing preflight is part of a mutating release command.
if PATH="/usr/bin:/bin" "$REPOSITORY_ROOT/lib/release.sh" patch >/dev/null 2>&1; then
    fail "publishing without gh should fail preflight"
fi

printf 'dirty\n' >> README.md
DIRTY_STATUS=$(git status --porcelain)
PLAN=$("$REPOSITORY_ROOT/lib/release.sh" --dry-run patch)
assert_file_contains <(printf '%s\n' "$PLAN") "Target:  0.0.2"
assert_eq "$(git status --porcelain)" "$DIRTY_STATUS"

# Default-branch enforcement and explicit release-branch patterns.
BRANCH_PROJECT="$TMP_ROOT/branches"
BRANCH_REMOTE="$TMP_ROOT/branches.git"
git init -q --bare "$BRANCH_REMOTE"
git --git-dir="$BRANCH_REMOTE" symbolic-ref HEAD refs/heads/main
mkdir -p "$BRANCH_PROJECT"
cd "$BRANCH_PROJECT"
git init -q
git checkout -q -b main
git config user.name "Release Tests"
git config user.email "release-tests@example.invalid"
printf 'example\n' > README.md
git add README.md
git commit -q -m "Initial project"
git remote add origin "$BRANCH_REMOTE"
git push -q -u origin main
git remote set-head origin -a >/dev/null
unset RELEASE_BRANCH_PATTERN
"$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run patch >/dev/null

git checkout -q -b feature/test
if "$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run patch >/dev/null 2>&1; then
    fail "non-default branch should stop a release"
fi
export RELEASE_BRANCH_PATTERN='main|feature/.+'
"$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run patch >/dev/null
export RELEASE_BRANCH_PATTERN='('
if "$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run patch >/dev/null 2>&1; then
    fail "invalid release branch regex was accepted"
fi

# Conventional Commits deterministically select the highest required bump.
CONVENTIONAL_PROJECT="$TMP_ROOT/conventional"
mkdir -p "$CONVENTIONAL_PROJECT"
cd "$CONVENTIONAL_PROJECT"
git init -q
git checkout -q -b main
git config user.name "Release Tests"
git config user.email "release-tests@example.invalid"
printf 'initial\n' > changes.txt
git add changes.txt
git commit -q -m "chore: initial project"
git tag -a v1.2.3 -m v1.2.3
export RELEASE_BRANCH_PATTERN=main
unset RELEASE_MOVING_TAGS RELEASE_ARTIFACTS RELEASE_CHECK_COMMAND RELEASE_BUILD_COMMAND
export RELEASE_CHANGELOG=false

printf 'chore\n' >> changes.txt
git commit -q -am "chore: update tooling"
if "$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run auto >/dev/null 2>&1; then
    fail "non-release Conventional Commits should not select a bump"
fi

printf 'fix\n' >> changes.txt
git commit -q -am "fix(parser): handle empty input"
PLAN=$("$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run auto)
assert_file_contains <(printf '%s\n' "$PLAN") "Target:  1.2.4"

printf 'feature\n' >> changes.txt
git commit -q -am "FeAt(api): add batch endpoint"
PLAN=$("$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run auto)
assert_file_contains <(printf '%s\n' "$PLAN") "Target:  1.3.0"

printf 'breaking\n' >> changes.txt
git add changes.txt
git commit -q -m "refactor: replace configuration model" -m "BREAKING CHANGE: configuration keys were renamed"
PLAN=$("$REPOSITORY_ROOT/lib/release.sh" --no-publish --dry-run auto)
assert_file_contains <(printf '%s\n' "$PLAN") "Target:  2.0.0"

# Expanded by the configured hook's Bash process.
# shellcheck disable=SC2016
export RELEASE_CHANGELOG_COMMAND='printf "Release %s\n" "$RELEASE_VERSION" > "$RELEASE_NOTES_FILE"; printf "Version %s\n" "$RELEASE_VERSION" > CUSTOM_CHANGELOG.txt; git add CUSTOM_CHANGELOG.txt'
"$REPOSITORY_ROOT/lib/release.sh" --no-publish auto >/dev/null
git rev-parse -q --verify refs/tags/v2.0.0 >/dev/null || fail "custom-changelog release tag was not created"
assert_file_contains CUSTOM_CHANGELOG.txt "Version 2.0.0"
assert_eq "$(git show HEAD:CUSTOM_CHANGELOG.txt)" "Version 2.0.0"

# Hook setup creates a default once and never rewrites project-owned config.
HOOK_PROJECT="$TMP_ROOT/hooks"
HOOK_BIN="$TMP_ROOT/hook-bin"
HOOK_LOG="$TMP_ROOT/pre-commit.log"
mkdir -p "$HOOK_PROJECT" "$HOOK_BIN"
cd "$HOOK_PROJECT"
git init -q
git checkout -q -b main
export HOOK_LOG
# Expanded by the generated mock when it runs.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$HOOK_LOG"' > "$HOOK_BIN/pre-commit"
chmod +x "$HOOK_BIN/pre-commit"
PATH="$HOOK_BIN:$PATH" "$REPOSITORY_ROOT/mise-tasks/release/setup-hooks" >/dev/null
assert_file_contains .pre-commit-config.yaml "commitizen-tools/commitizen"
assert_file_contains .pre-commit-config.yaml "rev: v4.10.0"
assert_file_contains "$HOOK_LOG" "validate-config"
assert_file_contains "$HOOK_LOG" "install --hook-type pre-commit --hook-type commit-msg"

printf 'repos: []\n' > .pre-commit-config.yaml
PATH="$HOOK_BIN:$PATH" "$REPOSITORY_ROOT/mise-tasks/release/setup-hooks" >/dev/null
assert_eq "$(cat .pre-commit-config.yaml)" "repos: []"

FALLBACK_PROJECT="$TMP_ROOT/hooks-fallback"
FALLBACK_BIN="$TMP_ROOT/fallback-bin"
MISE_LOG="$TMP_ROOT/mise.log"
mkdir -p "$FALLBACK_PROJECT" "$FALLBACK_BIN"
cd "$FALLBACK_PROJECT"
git init -q
git checkout -q -b main
export MISE_LOG
# Expanded by the generated mock when it runs.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$MISE_LOG"' > "$FALLBACK_BIN/mise"
chmod +x "$FALLBACK_BIN/mise"
PATH="$FALLBACK_BIN:/usr/bin:/bin" \
    "$REPOSITORY_ROOT/mise-tasks/release/setup-hooks" >/dev/null
assert_file_contains "$MISE_LOG" "exec pre-commit@4 -- pre-commit validate-config"
assert_file_contains "$MISE_LOG" \
    "exec pre-commit@4 -- pre-commit install --hook-type pre-commit --hook-type commit-msg"

# Guided setup infers safe defaults, previews without writes, and delegates
# configuration changes to mise instead of rewriting TOML itself.
SETUP_PROJECT="$TMP_ROOT/setup"
SETUP_BIN="$TMP_ROOT/setup-bin"
SETUP_MISE_LOG="$TMP_ROOT/setup-mise.log"
mkdir -p "$SETUP_PROJECT" "$SETUP_BIN"
cd "$SETUP_PROJECT"
git init -q
git checkout -q -b main
printf '{"name":"setup-test","version":"1.0.0"}\n' > package.json
printf '{}\n' > package-lock.json
printf 'name: setup-test\n' > action.yml
git add package.json package-lock.json action.yml
git -c user.name='Release Tests' -c user.email='release-tests@example.invalid' \
    commit -q -m 'chore: initial project'
export SETUP_MISE_LOG
# Expanded by the generated mock when it runs.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "$SETUP_MISE_LOG"' > "$SETUP_BIN/mise"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$SETUP_BIN/pre-commit"
chmod +x "$SETUP_BIN/mise" "$SETUP_BIN/pre-commit"

SETUP_ENV=(
    env
    -u RELEASE_TAG_PREFIX
    -u RELEASE_MOVING_TAGS
    -u RELEASE_GET_VERSION
    -u RELEASE_SET_VERSION
    -u RELEASE_CHECK_COMMAND
    -u RELEASE_BUILD_COMMAND
    -u RELEASE_ARTIFACTS
    -u RELEASE_BRANCH_PATTERN
    -u RELEASE_CHANGELOG
    -u RELEASE_CHANGELOG_COMMAND
)
SETUP_PLAN=$(PATH="$SETUP_BIN:/usr/bin:/bin" "${SETUP_ENV[@]}" \
    "$REPOSITORY_ROOT/mise-tasks/release/setup" --dry-run --yes)
assert_file_contains <(printf '%s\n' "$SETUP_PLAN") "RELEASE_TAG_PREFIX=v"
assert_file_contains <(printf '%s\n' "$SETUP_PLAN") "RELEASE_MOVING_TAGS=major"
assert_file_contains <(printf '%s\n' "$SETUP_PLAN") "RELEASE_GET_VERSION=npm pkg get version"
[[ ! -e mise.toml ]] || fail "setup dry run created mise.toml"

PATH="$SETUP_BIN:/usr/bin:/bin" "${SETUP_ENV[@]}" \
    "$REPOSITORY_ROOT/mise-tasks/release/setup" --yes >/dev/null 2>&1
assert_file_contains "$SETUP_MISE_LOG" "set --file"
assert_file_contains "$SETUP_MISE_LOG" "/setup/mise.toml"
assert_file_contains "$SETUP_MISE_LOG" "RELEASE_MOVING_TAGS=major"
assert_file_contains .pre-commit-config.yaml "commitizen-tools/commitizen"

# GitHub commands prefer an existing gh and otherwise use mise's pinned fallback.
: > "$SETUP_MISE_LOG"
PATH="$SETUP_BIN:/usr/bin:/bin" release_gh auth status
assert_file_contains "$SETUP_MISE_LOG" "exec gh@2 -- gh auth status"

printf 'All release tests passed.\n'
