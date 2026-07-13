#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=lib/version.sh
source "$REPOSITORY_ROOT/lib/version.sh"

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
assert_eq "$(release_moving_tags 2.3.4 v 'major minor')" $'v2\nv2.3'
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

# Publishing preflight is part of the normal release command.
if PATH="/usr/bin:/bin" "$REPOSITORY_ROOT/lib/release.sh" --dry-run patch >/dev/null 2>&1; then
    fail "publishing without gh should fail preflight"
fi

printf 'dirty\n' >> README.md
if "$REPOSITORY_ROOT/lib/release.sh" --dry-run patch >/dev/null 2>&1; then
    fail "dirty working tree should stop a release"
fi

printf 'All release tests passed.\n'
