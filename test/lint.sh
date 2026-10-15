#!/bin/bash
# Lints every shell script with ShellCheck. Reports SKIP if it isn't installed.
#
#   test/lint.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v shellcheck >/dev/null || { echo "SKIP  shellcheck isn't installed (brew install shellcheck)"; exit 2; }
cd "$REPO" || exit 1
shellcheck -S warning install.sh bin/*.sh test/*.sh && echo "all checks passed"
