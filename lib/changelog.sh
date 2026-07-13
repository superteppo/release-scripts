#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: changelog.sh [--version VERSION] [--from TAG] [--output FILE] [--notes FILE]

Generate a Markdown changelog entry from Git commits. VERSION defaults to
Unreleased and FILE defaults to CHANGELOG.md.
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

if [[ -z "$FROM_TAG" ]]; then
    FROM_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
fi

RANGE=HEAD
[[ -z "$FROM_TAG" ]] || RANGE="${FROM_TAG}..HEAD"
ENTRY=$(mktemp "${TMPDIR:-/tmp}/release-changelog.XXXXXX")
UPDATED=$(mktemp "${TMPDIR:-/tmp}/release-changelog-updated.XXXXXX")
trap 'rm -f "$ENTRY" "$UPDATED"' EXIT

{
    printf '## %s - %s\n\n' "$VERSION" "$(date +%Y-%m-%d)"
    # Git expands %s and %h; the shell must not.
    # shellcheck disable=SC2016
    if ! git log "$RANGE" --pretty=format:'- %s (`%h`)' | sed '/^[[:space:]]*$/d'; then
        release_die "could not read Git history"
    fi
    if [[ -z "$(git log "$RANGE" --pretty=format:%s)" ]]; then
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
        awk -v entry="$ENTRY" '
            NR == 1 && $0 ~ /^# / {
                print
                print ""
                while ((getline line < entry) > 0) print line
                close(entry)
                next
            }
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
