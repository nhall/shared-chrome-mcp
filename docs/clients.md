# Other MCP clients

`install.sh` registers the wrapper with Claude Code when the `claude` CLI is
installed. For any other client, register it yourself: a user-level stdio
server named `chrome-devtools` whose command is
`~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh`, with no arguments.
Spell out your home folder where a client doesn't expand `~`.

Remove any other `chrome-devtools` server first, such as one following the
upstream instructions (`npx chrome-devtools-mcp@latest`) or the Gemini CLI
extension, or that client keeps launching its own Chrome.

| Client | Register | Check |
|---|---|---|
| Codex | `codex mcp add chrome-devtools -- ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh` (writes `~/.codex/config.toml`) | `codex mcp list` |
| Gemini CLI | `gemini mcp add -s user chrome-devtools ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh` (writes `~/.gemini/settings.json`; without `-s user` it's per project) | `gemini mcp list` |
| Cursor (editor and `agent` CLI) | Add it under `mcpServers` in `~/.cursor/mcp.json`: `"chrome-devtools": {"type": "stdio", "command": "/Users/you/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh", "args": []}` | `agent mcp list` (older installs: `cursor-agent`) |

Every client shares the same Chrome, port and profile, read from
`~/.local/share/shared-chrome-mcp/config.env` (see
[Configuration](install.md#configuration)).

When you uninstall, remove the server from each client you added it to.
