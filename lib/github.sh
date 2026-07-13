#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
    cat <<'EOF'
Usage: github.sh TAG [NOTES_FILE] [--prerelease]

Push TAG and create or update its GitHub Release with RELEASE_ARTIFACTS.
EOF
}

[[ $# -ge 1 ]] || { usage >&2; exit 1; }
TAG=$1
shift
SAFE_TAG=${TAG//\//-}
NOTES=""
if [[ $# -gt 0 && "$1" != --* ]]; then
    NOTES=$1
    shift
fi
PRERELEASE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prerelease) PRERELEASE=true ;;
        -h|--help) usage; exit 0 ;;
        *) release_die "unknown argument: $1" ;;
    esac
    shift
done

release_require_command gh
ROOT=$(release_project_root)
cd "$ROOT"
NOTES=${NOTES:-$ROOT/.git/release-notes-${SAFE_TAG}.md}
[[ -f "$NOTES" ]] || release_die "release notes not found: $NOTES"
git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || release_die "tag not found: $TAG"

release_expand_artifacts
BRANCH=$(git symbolic-ref --quiet --short HEAD) || release_die "releases must be published from a branch"
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git push
else
    git push --set-upstream origin "$BRANCH"
fi
git push origin "$TAG"

if gh release view "$TAG" >/dev/null 2>&1; then
    release_info "Updating GitHub Release ${TAG}"
    if $PRERELEASE; then
        gh release edit "$TAG" --notes-file "$NOTES" --prerelease
    else
        gh release edit "$TAG" --notes-file "$NOTES" --latest
    fi
    if [[ ${#RELEASE_ASSET_FILES[@]} -gt 0 ]]; then
        gh release upload "$TAG" "${RELEASE_ASSET_FILES[@]}" --clobber
    fi
else
    args=(release create "$TAG" --title "$TAG" --notes-file "$NOTES" --verify-tag)
    if $PRERELEASE; then
        args+=(--prerelease)
    else
        args+=(--latest)
    fi
    if [[ ${#RELEASE_ASSET_FILES[@]} -gt 0 ]]; then
        args+=("${RELEASE_ASSET_FILES[@]}")
    fi
    gh "${args[@]}"
fi
