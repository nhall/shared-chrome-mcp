# Shared defaults and checks, sourced by the wrapper, ensure-chrome.sh,
# install.sh and the tests. The one place the defaults live.
#
# Overrides: CHROME_MCP_PORT, CHROME_MCP_PROFILE, CHROME_MCP_CHROME (Chrome
# binary). install.sh saves them in CONFIG, so every MCP client that runs the
# wrapper finds the same Chrome. One set in the environment wins over the file.
#
# The variables below are read by the scripts that source this file.
# shellcheck shell=bash disable=SC2034

SERVER_NAME="chrome-devtools"
INSTALL_DIR="$HOME/.local/share/shared-chrome-mcp"
CONFIG="$INSTALL_DIR/config.env"
OVERRIDE_VARS=(CHROME_MCP_PORT CHROME_MCP_PROFILE CHROME_MCP_CHROME)

# CONFIG holds KEY=value lines, read as data (never sourced), so a value can
# hold spaces without quoting.
load_config() {
  local key value
  [ -f "$CONFIG" ] || return 0
  while IFS='=' read -r key value; do
    case " ${OVERRIDE_VARS[*]} " in
      *" $key "*) [ -n "${!key:-}" ] || export "$key=$value" ;;
    esac
  done < "$CONFIG"
  return 0
}
load_config
PORT="${CHROME_MCP_PORT:-9333}"
PROFILE="${CHROME_MCP_PROFILE:-$HOME/.cache/chrome-mcp-shared/profile}"
CHROME="${CHROME_MCP_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

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
