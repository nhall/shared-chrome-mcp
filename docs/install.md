# Install details

## What `install.sh` changes

| Change | Location |
|---|---|
| Wrapper, relay and launcher (`chrome-mcp-shared.sh`, `lazy-launch.cjs`, `ensure-chrome.sh`, `common.sh`) | `~/.local/share/shared-chrome-mcp/` |
| Overrides you set (`CHROME_MCP_*`), for every client | `~/.local/share/shared-chrome-mcp/config.env` |
| What the first install found in Claude Code's config, for uninstall | `~/.local/share/shared-chrome-mcp/install-state.json` |
| `chrome-devtools-mcp` (pinned, local install — no `npx` fetch per session) | `~/.local/share/shared-chrome-mcp/node_modules/` |
| Claude Code only: user-scope MCP server `chrome-devtools` → the wrapper | `~/.claude.json` (via `claude mcp add-json --scope user`) |
| Claude Code only: deny rule `mcp__plugin_chrome-devtools-mcp_chrome-devtools` | `~/.claude/settings.json` → `permissions.deny` |
| Shared Chrome profile (created on first launch) | `~/.cache/chrome-mcp-shared/profile` |
| Launch log | `~/.local/share/shared-chrome-mcp/wrapper.log` |

`install.sh` is safe to re-run; it's also how you update. Each config file is
backed up (`*.bak-shared-chrome-<timestamp>`) before it is changed, by install
and by uninstall; a re-run that changes nothing makes no backups.

### The deny rule (Claude Code)

The deny rule hides the **chrome-devtools plugin's** own MCP tools, so sessions
see only one set of Chrome tools. The plugin stays enabled, so its skills
(a11y-debugging, troubleshooting, …) still work. If the plugin isn't installed,
the rule is harmless.

The rule only hides the plugin server's tools: its process still starts in each
session and sits idle, but it can never launch Chrome. There's no global way to
stop it starting. `disabledMcpServers` (what `/mcp` → Disable writes) works only
per project in `~/.claude.json`, and a top-level entry is ignored (tested on
2.1.285). The idle process is accepted as the cost.

### Upgrading from before 1.0.0

Installs before 1.0.0 lived in `~/.claude/chrome-mcp/`. `install.sh` moves one
to the new folder, with its record and overrides, and repoints the Claude Code
server. Sessions started before that keep running the old copy, so the old
folder stays until they've ended; restart them and re-run `install.sh` to
remove it.

## Configuration

These variables override the defaults. Export them before running `install.sh`:
it uses them for its checks and saves them in
`~/.local/share/shared-chrome-mcp/config.env`, which the wrapper reads for every
client, so they all share one Chrome. A re-run without them keeps the saved
ones. A variable set in the environment wins over the file; to drop a saved
override, delete its line.

| Variable | Default |
|---|---|
| `CHROME_MCP_PORT` | `9333` |
| `CHROME_MCP_PROFILE` | `~/.cache/chrome-mcp-shared/profile` |
| `CHROME_MCP_CHROME` | `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` |
| `MCP_VERSION` (install only) | `1.9.0` |

## Upgrading chrome-devtools-mcp

`chrome-devtools-mcp` is pinned to match the Claude Code plugin. To try a newer
[release](https://github.com/ChromeDevTools/chrome-devtools-mcp/releases):
`MCP_VERSION=x.y.z ./install.sh`, then `./test/all.sh`. The version each
release of this wrapper was tested with is in [CHANGELOG.md](../CHANGELOG.md).

## Manual install (no script)

```bash
mkdir -p ~/.local/share/shared-chrome-mcp
install -m 0755 bin/chrome-mcp-shared.sh bin/ensure-chrome.sh ~/.local/share/shared-chrome-mcp/
install -m 0644 bin/lazy-launch.cjs bin/common.sh ~/.local/share/shared-chrome-mcp/
npm install --prefix ~/.local/share/shared-chrome-mcp chrome-devtools-mcp@1.9.0
claude mcp add --scope user chrome-devtools -- ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh
```

Then add `"mcp__plugin_chrome-devtools-mcp_chrome-devtools"` to the
`permissions.deny` array in `~/.claude/settings.json`. For other clients, see
[clients.md](clients.md).

## Uninstall

```bash
./install.sh --uninstall
```

Restores the config as it was before the first install: removes the MCP server
(putting back an equivalent of any `chrome-devtools` server it replaced; key
order in `~/.claude.json` may differ), removes the deny rule (unless it was
there before), and removes a `permissions` block or `settings.json` that install
created. It then quits the shared Chrome and deletes
`~/.local/share/shared-chrome-mcp/`. Remove the server from any other client you
added it to yourself.

If any step fails, it stops before deleting the install folder and its record
of what install changed, so you can fix the problem and re-run it. The Chrome
profile is kept so logins survive a reinstall; delete `~/.cache/chrome-mcp-shared/`
to remove it too.
