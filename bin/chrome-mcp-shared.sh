#!/bin/bash
# Shared Chrome for the Chrome DevTools MCP — the MCP server command.
#
# Registered as a user-scope MCP server, so every Claude Code session runs this
# instead of chrome-devtools-mcp directly. It starts lazy-launch.cjs, a stdio
# relay: the session gets its tools immediately, and the shared Chrome is only
# launched (by ensure-chrome.sh) on the first browser tool call. Every session
# connects to that same browser and works in its own tabs.
#
# Env overrides: CHROME_MCP_PORT, CHROME_MCP_PROFILE, CHROME_MCP_CHROME (Chrome binary).

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
# Hand the resolved port to the relay, so the default lives only in common.sh.
CHROME_MCP_PORT="$PORT" exec node "$DIR/lazy-launch.cjs"
