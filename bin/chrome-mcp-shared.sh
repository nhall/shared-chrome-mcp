#!/bin/bash
# Shared Chrome for the Chrome DevTools MCP — the MCP server command.
#
# Registered as a user-level MCP server, so every client session runs this
# instead of chrome-devtools-mcp directly. It starts lazy-launch.cjs, a stdio
# relay: the session gets its tools immediately, and the shared Chrome is only
# launched (by ensure-chrome.sh) on the first browser tool call. Every session
# connects to that same browser and works in its own tabs.
#
# Overrides: CHROME_MCP_PORT, CHROME_MCP_PROFILE, CHROME_MCP_CHROME (see common.sh).

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
# Hand the resolved port to the relay, so the default lives only in common.sh.
CHROME_MCP_PORT="$PORT" exec node "$DIR/lazy-launch.cjs"
