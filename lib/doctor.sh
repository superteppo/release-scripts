#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/common.sh"

ROOT=$(release_project_root)
cd "$ROOT"

failed=false
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

$failed && exit 1
printf 'Ready to release.\n'
