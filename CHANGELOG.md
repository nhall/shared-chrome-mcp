# Changelog

Notable changes to shared-chrome-mcp. Versions follow
[Semantic Versioning](https://semver.org/): the interface is `install.sh`, its
`CHROME_MCP_*` and `MCP_VERSION` variables, and the behavior the README and
`docs/` describe.
Each release lists the `chrome-devtools-mcp` version it was tested with.

## [Unreleased]

## [1.0.0]

Tested with `chrome-devtools-mcp` 1.9.0.

First release.

- Every agent session on a Mac shares one Chrome through the Chrome DevTools
  MCP, with a dedicated profile so logins persist. Works with any MCP client:
  `install.sh` registers it with Claude Code, and docs/clients.md gives the
  registration for Codex, Gemini CLI and Cursor.
- Installs to `~/.local/share/shared-chrome-mcp/` (moved from
  `~/.claude/chrome-mcp/`, which `install.sh` migrates). `CHROME_MCP_*`
  overrides are saved in `config.env` there, so every client finds the same
  Chrome.
- Chrome opens only on a session's first browser tool call, and stays in the
  background: launching it and tool calls never bring it to the front.
- Concurrent sessions launch Chrome once, and it outlives the session that
  launched it.
- With Claude Code, `install.sh` also hides the chrome-devtools plugin's own
  MCP server; `install.sh --uninstall` restores the config as it was.
- Test suite: raw MCP sessions, sandboxed install/uninstall, and real
  `claude -p` sessions.

[Unreleased]: https://github.com/nhall/shared-chrome-mcp/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/nhall/shared-chrome-mcp/releases/tag/v1.0.0
