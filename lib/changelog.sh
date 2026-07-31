#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/version.sh
source "$SCRIPT_DIR/version.sh"

usage() {
    cat <<'EOF'
Usage: changelog.sh [--version VERSION] [--from TAG] [--output FILE] [--notes FILE]

Generate a Markdown changelog entry from Git commits. VERSION defaults to
Unreleased and FILE defaults to CHANGELOG.md. A stable X.Y.Z version replaces
the release-candidate entries it supersedes, so it defaults to covering commits
from the latest stable tag.
EOF
}

VERSION="Unreleased"
FROM_TAG=""
OUTPUT=${RELEASE_CHANGELOG:-CHANGELOG.md}
NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || release_die "--version requires a value"; VERSION=$2; shift 2 ;;
        --from) [[ $# -ge 2 ]] || release_die "--from requires a value"; FROM_TAG=$2; shift 2 ;;
        --output) [[ $# -ge 2 ]] || release_die "--output requires a value"; OUTPUT=$2; shift 2 ;;
        --notes) [[ $# -ge 2 ]] || release_die "--notes requires a value"; NOTES=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) release_die "unknown argument: $1" ;;
    esac
done

ROOT=$(release_project_root)
cd "$ROOT"

# A stable release documents the whole candidate line it concludes, so the
# superseded rc entries can be dropped without losing their commits.
DROP_PRERELEASES=false
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && DROP_PRERELEASES=true

if [[ -z "$FROM_TAG" ]]; then
    if $DROP_PRERELEASES; then
        FROM_TAG=$(release_latest_stable_tag "${RELEASE_TAG_PREFIX-v}" || true)
    fi
    [[ -n "$FROM_TAG" ]] || FROM_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
fi

RANGE=HEAD
[[ -z "$FROM_TAG" ]] || RANGE="${FROM_TAG}..HEAD"
# Release commits are made by this tool and document nothing on their own.
LOG_ARGS=("$RANGE" --extended-regexp --invert-grep --grep='^chore\(release\): ')
ENTRY=$(mktemp "${TMPDIR:-/tmp}/release-changelog.XXXXXX")
UPDATED=$(mktemp "${TMPDIR:-/tmp}/release-changelog-updated.XXXXXX")
trap 'rm -f "$ENTRY" "$UPDATED"' EXIT

{
    printf '## %s - %s\n\n' "$VERSION" "$(date +%Y-%m-%d)"
    # Git expands %s and %h; the shell must not.
    # shellcheck disable=SC2016
    if ! git log "${LOG_ARGS[@]}" --pretty=format:'- %s (`%h`)' | sed '/^[[:space:]]*$/d'; then
        release_die "could not read Git history"
    fi
    if [[ -z "$(git log "${LOG_ARGS[@]}" --pretty=format:%s)" ]]; then
        printf '%s' '- No user-visible changes.'
    fi
    printf '\n'
} > "$ENTRY"

if [[ -n "$NOTES" ]]; then
    cp "$ENTRY" "$NOTES"
fi

if [[ "$OUTPUT" != "false" ]]; then
    if [[ -f "$OUTPUT" ]] && grep -Fq "## ${VERSION} -" "$OUTPUT"; then
        release_die "${OUTPUT} already contains version ${VERSION}"
    fi
    if [[ -f "$OUTPUT" ]]; then
        awk -v entry="$ENTRY" -v drop_prereleases="$DROP_PRERELEASES" '
            function insert(   line) {
                while ((getline line < entry) > 0) print line
                close(entry)
            }
            NR == 1 && $0 ~ /^# / { print; print ""; insert(); next }
            NR == 1 { insert(); print "" }
            /^## / {
                skip = drop_prereleases == "true" &&
                    $0 ~ /^## [0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+ /
            }
            skip { next }
            { print }
        ' "$OUTPUT" > "$UPDATED"
    else
        {
            printf '# Changelog\n\n'
            cat "$ENTRY"
        } > "$UPDATED"
    fi
    mv "$UPDATED" "$OUTPUT"
    release_info "Updated ${OUTPUT}"
fi

[[ -n "$NOTES" ]] || cat "$ENTRY"
