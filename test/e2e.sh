#!/bin/bash
# End-to-end smoke test with real Claude Code sessions (`claude -p`), using the
# user's own config and the installed wrapper. Slower than verify.sh and costs
# a few model calls, so it's opt-in (test/all.sh --e2e).
#
# Every check reads the system, not what the model replies: the relay process
# under each session, launches in wrapper.log, the tabs in Chrome, and which app
# is in front. A session whose model fumbles its tools gets one retry.
#
#   test/e2e.sh          (E2E_MODEL picks the model; default haiku)
#
# Needs the shared Chrome closed, since it checks that sessions launch it.

set -u
MODEL="${E2E_MODEL:-haiku}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shared-chrome-e2e.XXXXXX")"
TAG="e2e-$$"

. "$(cd "$(dirname "$0")/.." && pwd)/bin/common.sh"
[ -d "$INSTALL_DIR" ] || { echo "FAIL  not installed: run ./install.sh"; exit 1; }
use_registered_overrides
LOG="$INSTALL_DIR/wrapper.log"
BASE="http://127.0.0.1:$PORT"

failures=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; failures=$((failures + 1)); fi; }
plugin_chrome() { pgrep -f -- "--user-data-dir=$HOME/.cache/chrome-devtools-mcp/chrome-profile" >/dev/null; }
# Tabs are found by URL: a plain-text data URL survives a model's escaping.
tab_url() { echo "data:text/plain,$TAG-$1"; }
tab_ids() { curl -s "$BASE/json/list" | jq -r --arg t "$TAG" '.[] | select(.type == "page" and (.url | contains($t))) | .id'; }

if chrome_answers || [ -n "$(shared_chrome_pids)" ]; then
  echo "SKIP  the shared Chrome is running; quit it and re-run (this test checks that sessions launch it)"
  exit 2
fi
plugin_was_running=false; plugin_chrome && plugin_was_running=true

# Which app is in front, every 150ms, for the whole run.
FRONT="$WORK/front.txt"; CHROMES="$WORK/chromes.txt"; : > "$FRONT"; : > "$CHROMES"
( while :; do
    osascript -e 'tell application "System Events" to unix id of first process whose frontmost is true' >> "$FRONT" 2>/dev/null
    shared_chrome_pids >> "$CHROMES"
    sleep 0.15
  done ) &
SAMPLER=$!
disown "$SAMPLER"  # no "Terminated" notice when it is stopped
cleanup() {
  kill "$SAMPLER" 2>/dev/null
  for id in $(tab_ids); do curl -s "$BASE/json/close/$id" >/dev/null; done
  # Quit the Chrome this test launched, unless another session has tabs in it.
  if [ "$(curl -s "$BASE/json/list" | jq '[.[] | select(.type == "page" and .url != "about:blank")] | length' 2>/dev/null)" = 0 ]; then
    for pid in $(shared_chrome_pids); do kill "$pid"; done
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Runs one `claude -p` session in its own folder; records whether the relay
# started under it. $1 name, $2 prompt, $3 allowed tools.
session() {
  local dir="$WORK/$1"; mkdir -p "$dir"
  ( cd "$dir" && exec claude -p "$2" --model "$MODEL" ${3:+--allowedTools "$3"} < /dev/null > out.txt 2>&1 ) &
  local pid=$! relay=no
  while kill -0 "$pid" 2>/dev/null; do
    for c in $(pgrep -P "$pid"; for p in $(pgrep -P "$pid"); do pgrep -P "$p"; done); do
      ps -o command= -p "$c" 2>/dev/null | grep -q lazy-launch.cjs && relay=yes
    done
    sleep 0.3
  done
  echo "$relay" > "$dir/relay"
}
open_tab() {
  session "$1" "Use the chrome-devtools new_page tool to open the URL $(tab_url "$1") exactly as written, then reply done. Do not close the page." \
    "mcp__chrome-devtools__new_page,mcp__chrome-devtools__list_pages"
}
has_tab() { curl -s "$BASE/json/list" | jq -e --arg t "$TAG-$1" 'any(.[]; .url | endswith($t))' >/dev/null 2>&1; }

echo "model: $MODEL   port: $PORT"
echo
LOG_START=$(( $(wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))
new_log() { tail -n "+$LOG_START" "$LOG" 2>/dev/null; }
L0=$(launch_count)
session plain "Reply with the single word ready. Do not use any tools."
check "a session that doesn't use the browser loads the relay" '[ "$(cat "$WORK/plain/relay")" = yes ]'
check "...and doesn't open Chrome" '[ "$(launch_count)" = "$L0" ] && [ -z "$(shared_chrome_pids)" ]'

L1=$(launch_count)
# Wait for just these two: the focus sampler is a background job too.
open_tab one & p1=$!; open_tab two & p2=$!; wait "$p1" "$p2"
for s in one two; do has_tab "$s" || { echo "      retrying session $s: $(head -c 120 "$WORK/$s/out.txt" | tr '\n' ' ')"; open_tab "$s"; }; done
check "two sessions using the browser at once each opened their tab" 'has_tab one && has_tab two'
check "...in one Chrome, launched once" '[ "$(( $(launch_count) - L1 ))" = 1 ] && [ "$(shared_chrome_pids | wc -l | tr -d " ")" = 1 ]'
check "no tool call was refused" '! new_log | grep -q "tool call refused"'

kill "$SAMPLER" 2>/dev/null
if [ ! -s "$FRONT" ]; then
  check "could read the frontmost app (allow your terminal to control System Events in Privacy & Security > Automation)" false
else
  check "the shared Chrome never came to the front ($(wc -l < "$FRONT" | tr -d ' ') samples)" \
    '! grep -qxF -f <(sort -u "$CHROMES" | grep .) "$FRONT"'
fi
if [ "$plugin_was_running" = false ]; then
  check "the plugin's own Chrome never started" '! plugin_chrome'
fi

echo
[ "$failures" -eq 0 ] && echo "all checks passed" || echo "$failures check(s) failed"
exit $(( failures > 0 ))
