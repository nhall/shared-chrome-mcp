#!/bin/bash
# Make sure the shared, debuggable Chrome is running; launch it if not.
# Exits 0 once Chrome answers on the port, 1 (with a reason on stderr) if not.
#
#   ensure-chrome.sh [--need-page]
#
# Called by lazy-launch.cjs right before a browser tool call, so Chrome only
# opens when a session actually uses it. --need-page: the tool acts on an
# existing page, so make sure there is one. Chrome is detached, so it outlives the session that launched it — quit it
# like any app and the next tool call relaunches it.
#
# Env overrides: CHROME_MCP_PORT, CHROME_MCP_PROFILE, CHROME_MCP_CHROME (Chrome binary).

set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
LOCK="$DIR/.launch.lockf"
LOG="$DIR/wrapper.log"

log() { echo "$(date '+%F %T') [$$] $*" >> "$LOG"; }
fail() { log "$1"; echo "$1 (see $LOG)" >&2; exit 1; }

# Chrome can be running with no page (launched without a window, or the user
# closed them all).
NEED_PAGE=false; [ "${1:-}" = "--need-page" ] && NEED_PAGE=true
needs_page() { [ "$NEED_PAGE" = true ]; }
has_page() { curl -s -m 1 "http://127.0.0.1:$PORT/json/list" | jq -e 'any(.[]; .type == "page")' >/dev/null; }
ready() { chrome_answers && port_is_ours && { ! needs_page || has_page; }; }

# Opens a blank page in the background, so it doesn't pull Chrome to the front.
open_blank_page() {
  node -e '
    const port = process.argv[1];
    setTimeout(() => process.exit(1), 5000);
    fetch(`http://127.0.0.1:${port}/json/version`).then(r => r.json()).then(v => {
      const ws = new WebSocket(v.webSocketDebuggerUrl);
      ws.onopen = () => ws.send(JSON.stringify({ id: 1, method: "Target.createTarget", params: { url: "about:blank", background: true } }));
      ws.onmessage = e => process.exit(JSON.parse(e.data).error ? 1 : 0);
      ws.onerror = () => process.exit(1);
    }, () => process.exit(1));
  ' "$PORT" || log "could not open a blank page"
}

ready && exit 0

# Serialize launches (and blank-page creation) so two sessions calling at once
# can't both do it. lockf holds a kernel lock that is released when its holder
# exits, so a crashed launcher can't leave a stale lock behind, and the
# processes it starts don't inherit it. -s: our own message explains a timeout.
if [ -z "${CHROME_MCP_LOCKED:-}" ]; then
  CHROME_MCP_LOCKED=1 /usr/bin/lockf -s -k -t 30 "$LOCK" "$0" "$@"
  rc=$?
  [ "$rc" -eq 75 ] && fail "timed out waiting for another session to launch Chrome"
  exit "$rc"
fi

# Holding the lock. Another session may have done the work while we waited.
ready && exit 0

if chrome_answers && ! port_is_ours; then
  fail "port $PORT is in use by another program; set CHROME_MCP_PORT"
fi

if ! chrome_answers; then
  # A shared Chrome that was just quit can take a few seconds to exit, and a
  # new launch meanwhile would hand off to it and vanish. Wait it out.
  for _ in $(seq 1 40); do
    if [ -n "$(shared_chrome_pids)" ] && ! chrome_answers; then sleep 0.25; else break; fi
  done
  if ! chrome_answers && [ -n "$(shared_chrome_pids)" ]; then
    fail "the shared Chrome is running but not answering on port $PORT; quit it and try again"
  fi
fi

if ! chrome_answers; then
  mkdir -p "$PROFILE"
  log "$LAUNCH_MARK on $PORT"
  ARGS=(--remote-debugging-port="$PORT" --remote-debugging-address=127.0.0.1
    --user-data-dir="$PROFILE" --no-first-run --no-default-browser-check)
  # The innermost .app bundle the binary is in, used only if the binary is
  # that bundle's main executable.
  APP="${CHROME%.app/Contents/MacOS/*}.app"
  EXE="$(defaults read "$APP/Contents/Info" CFBundleExecutable 2>/dev/null)"
  if [ -n "$EXE" ] && [ "$APP/Contents/MacOS/$EXE" = "$CHROME" ]; then
    # Launch through LaunchServices without activating it (-g) and with no
    # window of its own, so starting Chrome doesn't pull it in front of whatever
    # the user is doing. -n starts a separate instance from their everyday
    # Chrome. Chrome is then launchd's child, not part of this session at all.
    open -g -n -a "$APP" --args "${ARGS[@]}" --no-startup-window
  else
    # A bare binary: run it in its own process group (set -m), so a signal sent
    # to the session's group when it exits doesn't reach Chrome; nohup covers SIGHUP.
    set -m
    nohup "$CHROME" "${ARGS[@]}" >/dev/null 2>&1 &
    disown
    set +m
  fi
  for _ in $(seq 1 60); do chrome_answers && break; sleep 0.25; done
  chrome_answers || fail "Chrome did not start on port $PORT"
fi

if needs_page && ! has_page; then open_blank_page; fi
exit 0
