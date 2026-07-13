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

printf '%s\n' '==> Release integration tests'
tests/test-release.sh

printf '%s\n' '==> Whitespace'
git diff --check
git diff --cached --check

printf '%s\n' 'Repository checks passed.'
