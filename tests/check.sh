#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPOSITORY_ROOT"

SHELL_FILES=(
    lib/*.sh
    ./*.sh
    mise-tasks/release/*
    tests/*.sh
)

printf '%s\n' '==> Bash syntax'
bash -n "${SHELL_FILES[@]}"

printf '%s\n' '==> ShellCheck'
if ! command -v shellcheck >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: shellcheck is required' >&2
    exit 1
fi
shellcheck "${SHELL_FILES[@]}"

printf '%s\n' '==> Mise task usage'
if ! command -v mise >/dev/null 2>&1; then
    printf '%s\n' 'ERROR: mise is required' >&2
    exit 1
fi
MISE_CONFIG="$REPOSITORY_ROOT/mise.toml"
for task in \
    release \
    release:changelog \
    release:doctor \
    release:dropbox \
    release:github \
    release:setup \
    release:setup-hooks; do
    HELP=$(MISE_OVERRIDE_CONFIG_FILENAMES="$MISE_CONFIG" mise run "$task" -h)
    grep -Fq "Usage: $task" <<< "$HELP" || {
        printf 'ERROR: missing mise usage for %s\n' "$task" >&2
        exit 1
    }
done

printf '%s\n' '==> Release integration tests'
tests/test-release.sh

printf '%s\n' '==> Whitespace'
git diff --check
git diff --cached --check

printf '%s\n' 'Repository checks passed.'
