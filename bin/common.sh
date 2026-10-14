# Shared defaults and checks, sourced by the wrapper, ensure-chrome.sh,
# install.sh and the tests. The one place the defaults live.
#
# Env overrides: CHROME_MCP_PORT, CHROME_MCP_PROFILE, CHROME_MCP_CHROME (Chrome binary).

SERVER_NAME="chrome-devtools"
INSTALL_DIR="$HOME/.claude/chrome-mcp"
OVERRIDE_VARS=(CHROME_MCP_PORT CHROME_MCP_PROFILE CHROME_MCP_CHROME)

resolve_config() {
  PORT="${CHROME_MCP_PORT:-9333}"
  PROFILE="${CHROME_MCP_PROFILE:-$HOME/.cache/chrome-mcp-shared/profile}"
  CHROME="${CHROME_MCP_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
}
resolve_config

# The user-scope server registered under SERVER_NAME, as JSON (null if none).
registered_server() { jq -c --arg n "$SERVER_NAME" '.mcpServers[$n] // null' "$HOME/.claude.json" 2>/dev/null || echo null; }
is_our_server() { [ "$(jq -r '.command // ""' <<<"$1")" = "$INSTALL_DIR/chrome-mcp-shared.sh" ]; }

# Use the overrides Claude Code runs the wrapper with: the registered server's
# env (or, once uninstall has removed the server, the copy install saved).
# Registered values win; ones it doesn't set keep the shell's.
use_registered_overrides() {
  local server env
  server="$(registered_server)"
  if is_our_server "$server"; then
    env="$(jq -c '.env // {}' <<<"$server")"
  else
    env="$(jq -c '.registered_env // {}' "$INSTALL_DIR/install-state.json" 2>/dev/null || echo '{}')"
  fi
  eval "$(jq -r 'to_entries[] | select(.key as $k | $ARGS.positional | index($k))
    | "export \(.key)=\(.value | @sh)"' --args "${OVERRIDE_VARS[@]}" <<<"$env")"
  resolve_config
}

# ensure-chrome.sh logs this for every launch; the tests count it.
LAUNCH_MARK="launching shared Chrome"
launch_count() { local n; n="$(grep -c "$LAUNCH_MARK" "$INSTALL_DIR/wrapper.log" 2>/dev/null)"; echo "${n:-0}"; }

# Something answers DevTools requests on the port.
chrome_answers() { curl -s -m 1 "http://127.0.0.1:$PORT/json/version" >/dev/null; }

# True if PID is the shared Chrome's main process: exactly our profile (not a
# path that merely starts with it), and not one of Chrome's helper processes.
is_shared_chrome() {
  local cmd
  cmd="$(ps -o command= -p "$1" 2>/dev/null)" || return 1
  [[ " $cmd " == *" --user-data-dir=$PROFILE "* && " $cmd " != *" --type="* ]]
}

# PIDs of the shared Chrome's main process (normally zero or one).
shared_chrome_pids() {
  local pid
  for pid in $(pgrep -f -- "--user-data-dir=$PROFILE"); do
    is_shared_chrome "$pid" && echo "$pid"
  done
  return 0
}

# True if the process listening on the port is the shared Chrome — not just
# that the shared Chrome is running somewhere.
port_is_ours() {
  local pid
  for pid in $(lsof -nP -iTCP:"$PORT" -sTCP:LISTEN -t 2>/dev/null); do
    is_shared_chrome "$pid" && return 0
  done
  return 1
}
