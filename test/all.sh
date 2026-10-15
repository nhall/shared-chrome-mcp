#!/bin/bash
# Runs the test suite. Run it after every change, and before committing.
#
#   test/all.sh          lint.sh (ShellCheck) + verify.sh (shared Chrome, via raw MCP) + install.sh (sandboxed)
#   test/all.sh --e2e    ...plus e2e.sh (real Claude Code sessions; slower, uses the model)
#
# Re-install first (./install.sh) so verify.sh and e2e.sh test the current code.
# For the full run, quit the shared Chrome first: some checks only run, or only
# run safely, when the test is the one that launches it.

DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/.." && pwd)"
. "$REPO/bin/common.sh"
results=()
status=0

# The installed copy must match the repo, or verify/e2e test stale code.
stale=""
for f in "$REPO"/bin/*; do
  cmp -s "$f" "$INSTALL_DIR/$(basename "$f")" || stale+=" $(basename "$f")"
done
if [ -n "$stale" ]; then
  echo "installed files differ from the repo:$stale — run ./install.sh first"
  exit 1
fi

run() {
  echo "=== $1"
  "$DIR/$1"
  local rc=$?
  case $rc in
    0) results+=("PASS  $1") ;;
    2) results+=("SKIP  $1") ;;
    *) results+=("FAIL  $1"); status=1 ;;
  esac
  echo
}

run lint.sh
run verify.sh
run install.sh
[ "${1:-}" = "--e2e" ] && run e2e.sh

echo "=== summary"
printf '%s\n' "${results[@]}"
exit $status
