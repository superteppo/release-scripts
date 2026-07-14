#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"
# shellcheck source=lib/version.sh
source "$SCRIPT_DIR/version.sh"

ROOT=$(release_project_root)
cd "$ROOT"

failed=false
warnings=false

doctor_warn() {
    printf 'WARN %s\n' "$*" >&2
    warnings=true
}

doctor_check_hook() {
    local name=$1
    local value=$2
    local first
    [[ -n "$value" ]] || return 0
    if ! bash -n -c "$value" >/dev/null 2>&1; then
        printf 'ERR %s has invalid Bash syntax\n' "$name" >&2
        failed=true
        return
    fi
    first=${value%%[[:space:]]*}
    first=${first#\"}; first=${first%\"}
    first=${first#\'}; first=${first%\'}
    if [[ "$first" == *=* ]]; then
        doctor_warn "$name starts with an environment assignment; executable resolution skipped"
    elif command -v "$first" >/dev/null 2>&1 || [[ -x "$first" ]]; then
        printf 'ok  %s executable: %s\n' "$name" "$first"
    else
        printf 'ERR %s executable not found: %s\n' "$name" "$first" >&2
        failed=true
    fi
}

for command in bash git gh; do
    if command -v "$command" >/dev/null 2>&1; then
        printf 'ok  %s\n' "$command"
    else
        printf 'ERR %s is not installed\n' "$command" >&2
        failed=true
    fi
done

if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        printf 'ok  GitHub authentication\n'
    else
        printf 'ERR GitHub CLI is not authenticated\n' >&2
        failed=true
    fi
fi

if git remote get-url origin >/dev/null 2>&1; then
    printf 'ok  origin: %s\n' "$(git remote get-url origin)"
else
    printf 'ERR origin remote is not configured\n' >&2
    failed=true
fi

if branch=$(release_assert_branch 2>/dev/null); then
    printf 'ok  release branch: %s\n' "$branch"
else
    printf 'ERR current branch is not eligible for releases\n' >&2
    failed=true
fi

TAG_PREFIX=${RELEASE_TAG_PREFIX-v}
LATEST_TAG=$(release_latest_stable_tag "$TAG_PREFIX" || true)
INCOMPATIBLE_TAG=""
while IFS= read -r tag; do
    candidate=${tag#v}
    version=$(release_normalize_version "$candidate" 2>/dev/null || true)
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if ! release_version_from_tag "$tag" "$TAG_PREFIX" >/dev/null 2>&1; then
        INCOMPATIBLE_TAG=$tag
        break
    fi
done < <(git tag --list --sort=-version:refname)
if [[ -n "$LATEST_TAG" ]]; then
    printf 'ok  latest release tag: %s\n' "$LATEST_TAG"
else
    printf 'ok  no previous release tags matching configured prefix\n'
fi
if [[ -n "$INCOMPATIBLE_TAG" ]]; then
    doctor_warn "existing tag '$INCOMPATIBLE_TAG' does not match RELEASE_TAG_PREFIX='${TAG_PREFIX}'"
fi

if [[ -n "${RELEASE_GET_VERSION:-}" ]]; then
    if version=$(bash -o pipefail -c "$RELEASE_GET_VERSION" 2>/dev/null); then
        printf 'ok  package version: %s\n' "$(release_trim "$version")"
    else
        printf 'ERR RELEASE_GET_VERSION failed\n' >&2
        failed=true
    fi
else
    printf 'ok  tag-based versioning\n'
fi

doctor_check_hook RELEASE_CHECK_COMMAND "${RELEASE_CHECK_COMMAND:-}"
doctor_check_hook RELEASE_BUILD_COMMAND "${RELEASE_BUILD_COMMAND:-}"
doctor_check_hook RELEASE_CHANGELOG_COMMAND "${RELEASE_CHANGELOG_COMMAND:-}"

if [[ -n "${RELEASE_ARTIFACTS:-}" ]]; then
    MISSING_ARTIFACTS=()
    for pattern in $RELEASE_ARTIFACTS; do
        MATCHED=false
        while IFS= read -r file; do
            [[ -f "$file" ]] && MATCHED=true
        done < <(compgen -G "$pattern" || true)
        $MATCHED || MISSING_ARTIFACTS+=("$pattern")
    done
    if [[ ${#MISSING_ARTIFACTS[@]} -gt 0 ]]; then
        if [[ -n "${RELEASE_BUILD_COMMAND:-}" ]]; then
            doctor_warn "artifacts currently missing (build must create them): ${MISSING_ARTIFACTS[*]}"
        else
            printf 'ERR artifact patterns match no files: %s\n' "${MISSING_ARTIFACTS[*]}" >&2
            failed=true
        fi
    else
        printf 'ok  release artifacts exist\n'
    fi
fi

DROPBOX_CONFIG=${RELEASE_DROPBOX_CONFIG:-$ROOT/.dropboxuploader}
if [[ -n "${RELEASE_DROPBOX_PATH:-}" || -n "${RELEASE_DROPBOX_CONFIG:-}" || -e "$DROPBOX_CONFIG" ]]; then
    if [[ -s "$DROPBOX_CONFIG" ]]; then
        printf 'ok  Dropbox credentials: %s\n' "$DROPBOX_CONFIG"
    else
        printf 'ERR Dropbox credentials not found: %s\n' "$DROPBOX_CONFIG" >&2
        failed=true
    fi
    if [[ -n "${RELEASE_DROPBOX_PATH:-}" ]]; then
        printf 'ok  Dropbox path: %s\n' "$RELEASE_DROPBOX_PATH"
    else
        printf 'ERR RELEASE_DROPBOX_PATH must be set when Dropbox is configured\n' >&2
        failed=true
    fi
fi

$failed && exit 1
if $warnings; then
    printf 'Ready to release with warnings.\n'
else
    printf 'Ready to release.\n'
fi
