#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/release-standalone-tests.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

PROJECT="$TEST_ROOT/project"
mkdir -p "$PROJECT"
cd "$PROJECT"
git init -q
git checkout -q -b main
git config user.name 'Release Tests'
git config user.email release-tests@example.invalid
touch tracked
git add tracked
git commit -qm initial

RELEASE_SCRIPTS_SOURCE="$REPOSITORY_ROOT" "$REPOSITORY_ROOT/install.sh" 1.5
[[ -x .release-scripts/release ]] || fail 'standalone CLI was not installed'
[[ -x .release-scripts/install.sh ]] || fail 'updater was not installed'
[[ $(<.release-scripts/.channel) == 1.5 ]] || fail 'release channel was not recorded'
[[ $(<.release-scripts/.revision) == local ]] || fail 'revision was not recorded'

HELP=$(./.release-scripts/release --help)
grep -Fq 'Usage: release <command>' <<< "$HELP" || fail 'standalone help is unavailable'

cat > .release.env <<'EOF'
RELEASE_MOVING_TAGS='major'
RELEASE_BRANCH_PATTERN='main'
EOF
DOCTOR=$(./.release-scripts/release doctor 2>&1 || true)
grep -Fq 'moving tags: major' <<< "$DOCTOR" || fail '.release.env was not loaded'

PATH=/usr/bin:/bin ./.release-scripts/release setup --yes >/dev/null 2>&1
grep -Fq "RELEASE_TAG_PREFIX='v'" .release.env || fail 'standalone setup did not update .release.env'
grep -Fq "RELEASE_MOVING_TAGS='major'" .release.env || fail 'standalone setup replaced existing configuration'

RELEASE_SCRIPTS_SOURCE="$REPOSITORY_ROOT" ./.release-scripts/release update
[[ $(<.release-scripts/.channel) == 1.5 ]] || fail 'update did not preserve the channel'

printf 'Standalone installation tests passed.\n'
