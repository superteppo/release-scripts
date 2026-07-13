#!/usr/bin/env bash

release_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

release_die() {
    release_error "$*"
    exit 1
}

release_info() {
    printf '%s\n' "$*"
}

release_project_root() {
    git rev-parse --show-toplevel 2>/dev/null || release_die "not inside a Git repository"
}

release_require_command() {
    command -v "$1" >/dev/null 2>&1 || release_die "required command not found: $1"
}

release_run_hook() {
    local label=$1
    local command=$2
    [[ -n "$command" ]] || return 0
    release_info "==> ${label}"
    bash -o pipefail -c "$command"
}

release_trim() {
    local value=$1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

release_expand_artifacts() {
    local patterns=${RELEASE_ARTIFACTS:-}
    local pattern file found=false
    RELEASE_ASSET_FILES=()

    [[ -n "$patterns" ]] || return 0
    for pattern in $patterns; do
        found=false
        while IFS= read -r file; do
            [[ -f "$file" ]] || continue
            RELEASE_ASSET_FILES+=("$file")
            found=true
        done < <(compgen -G "$pattern" || true)
        $found || release_die "artifact pattern matched no files: $pattern"
    done
}
