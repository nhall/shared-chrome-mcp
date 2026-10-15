# shared-chrome-mcp

A small wrapper that makes the
[Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp)
work the way you'd expect it to out of the box: every agent session on a Mac
(Claude Code, Codex, Gemini CLI, Cursor, or any MCP client) uses it at the same
time, in one shared Chrome, with logins that persist.
Chrome opens only when a session actually uses it, and stays in the background.

It doesn't fork or replace the Chrome DevTools MCP. The real
`chrome-devtools-mcp`, maintained by the Chrome DevTools team, runs underneath
unchanged, at a pinned version you can upgrade. The wrapper only decides when
Chrome starts and keeps it out of your way.

## The problem

Out of the box, each agent session (each Claude Code, Codex or Gemini CLI
terminal, each Cursor window) starts its own copy of the chrome-devtools MCP
server, and each copy launches Chrome with the same fixed
profile (`~/.cache/chrome-devtools-mcp/chrome-profile`) over a private
`--remote-debugging-pipe`. Chrome allows one instance per profile, so the first
session wins and every other session fails with:

> The browser is already running for …/chrome-profile. Use --isolated to run
> multiple browser instances.

## How this fixes it

The MCP server is pointed at a small wrapper (`bin/chrome-mcp-shared.sh`)
instead of `chrome-devtools-mcp` directly. The wrapper starts a stdio relay
(`bin/lazy-launch.cjs`) in front of `chrome-devtools-mcp --browserUrl
http://127.0.0.1:9333`, which connects to a running browser instead of
launching its own.

- **Session start:** the relay passes everything straight through. The
  session gets its tools immediately and **no Chrome opens**. A session that
  never touches the browser never launches one.
- **Each browser tool call:** before forwarding it, the relay runs
  `bin/ensure-chrome.sh`. If the shared Chrome isn't answering on
  `127.0.0.1:9333`, that script launches one: a dedicated profile, with the
  debugging port bound to localhost, started through macOS (`open -g`) so it
  outlives the session. A lock stops two sessions calling at once from both
  launching it, and it refuses to connect if something other than the shared
  Chrome is listening on the port.

So the first browser action from any session opens Chrome, and every other
session joins the same browser in its own tabs. Quit Chrome like any app, and
the next browser action relaunches it, even in the middle of a session.

- **Tool calls never bring Chrome forward.** It launches in the background with no window
  of its own. The relay opens every `new_page` in the background (even if the
  agent asks for the foreground) and drops `bringToFront` from `select_page`;
  snapshots, screenshots and input all work on background pages. If Chrome has
  no pages (fresh launch, or you closed all its windows), a blank one is opened
  in the background first, so tools like `navigate_page` work.
- **`chrome-devtools-mcp` stays in charge of the tools.** The relay knows only
  `new_page` and `select_page` by name (the `TOOLS` table in
  `bin/lazy-launch.cjs`). Every other tool, including any a new release adds, is
  passed through unchanged.

## Install

Requirements: macOS, Google Chrome, Node 22+ and npm, `jq`, `curl`, `lsof`.

```bash
git clone https://github.com/nhall/shared-chrome-mcp.git ~/repos/shared-chrome-mcp
cd ~/repos/shared-chrome-mcp
./install.sh
./test/all.sh
```

If the `claude` CLI is installed, `install.sh` registers the wrapper with Claude
Code. For any other client, register it yourself (below). Then restart open
sessions, and log into the sites you test (WP admin etc.) once in the shared
Chrome (click its Dock icon to bring it forward).

Prefer to have an agent do it? Open your agent in this folder and say
"install this" — see [AGENTS.md](AGENTS.md).

### Other MCP clients

Register a user-level stdio server named `chrome-devtools` whose command is
`~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh` (no arguments; spell out
your home folder where a client doesn't expand `~`). Remove any other
`chrome-devtools` server first, such as one following the upstream
instructions (`npx chrome-devtools-mcp@latest`) or the Gemini CLI extension, or
that client keeps launching its own Chrome.

| Client | Register | Check |
|---|---|---|
| Codex | `codex mcp add chrome-devtools -- ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh` (writes `~/.codex/config.toml`) | `codex mcp list` |
| Gemini CLI | `gemini mcp add -s user chrome-devtools ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh` (writes `~/.gemini/settings.json`; without `-s user` it's per project) | `gemini mcp list` |
| Cursor (editor and `agent` CLI) | Add it under `mcpServers` in `~/.cursor/mcp.json`: `"chrome-devtools": {"type": "stdio", "command": "/Users/you/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh", "args": []}` | `agent mcp list` (older installs: `cursor-agent`) |

Every client shares the same Chrome, port and profile, read from
`~/.local/share/shared-chrome-mcp/config.env`.

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

The deny rule hides the **chrome-devtools plugin's** own MCP tools, so sessions
see only one set of Chrome tools. The plugin stays enabled, so its skills
(a11y-debugging, troubleshooting, …) still work. If the plugin isn't installed,
the rule is harmless.

The rule only hides the plugin server's tools: its process still starts in each
session and sits idle, but it can never launch Chrome. There's no global way to
stop it starting. `disabledMcpServers` (what `/mcp` → Disable writes) works only
per project in `~/.claude.json`, and a top-level entry is ignored (tested on
2.1.285). The idle process is accepted as the cost.

Each config file is backed up (`*.bak-shared-chrome-<timestamp>`) before it is
changed, by install and by uninstall; a re-run that changes nothing makes no
backups. The first install records what was there before in
`~/.local/share/shared-chrome-mcp/install-state.json`, so uninstall can restore it.
`install.sh` is safe to re-run; it's also how you update. An install from
before 1.0.0 (in `~/.claude/chrome-mcp/`) is moved to the new folder, with its
record and overrides, and the Claude Code server repointed. Sessions started
before that keep running the old copy, so the old folder stays until they've
ended; restart them and re-run `install.sh` to remove it.

### Manual install (no script)

```bash
mkdir -p ~/.local/share/shared-chrome-mcp
install -m 0755 bin/chrome-mcp-shared.sh bin/ensure-chrome.sh ~/.local/share/shared-chrome-mcp/
install -m 0644 bin/lazy-launch.cjs bin/common.sh ~/.local/share/shared-chrome-mcp/
npm install --prefix ~/.local/share/shared-chrome-mcp chrome-devtools-mcp@1.9.0
claude mcp add --scope user chrome-devtools -- ~/.local/share/shared-chrome-mcp/chrome-mcp-shared.sh
```

Then add `"mcp__plugin_chrome-devtools-mcp_chrome-devtools"` to the
`permissions.deny` array in `~/.claude/settings.json`.

## Uninstall

```bash
./install.sh --uninstall
```

Restores the config as it was before the first install: removes the MCP server
(putting back an equivalent of any `chrome-devtools` server it replaced; key
order in `~/.claude.json` may differ), removes the deny rule
(unless it was there before), and removes a `permissions` block or
`settings.json` that install created. It then quits the shared Chrome and
deletes `~/.local/share/shared-chrome-mcp/`. Remove the server from any other
client you added it to yourself. If any step fails, it stops before deleting
the install folder and its record of what install changed, so you can fix the problem and re-run it. The Chrome profile is kept
so logins survive a reinstall; delete `~/.cache/chrome-mcp-shared/` to remove it
too.

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

## Things to know

- **Sessions share tabs.** Each session sees every tab in the browser. Page
  numbers in `list_pages` are per session, so they don't collide, but a session
  should only act on tabs it opened (`new_page`) and close them when done.
- **Tabs aren't closed automatically** when a session ends.
- **Finding the shared Chrome.** It's a separate instance from your everyday
  Chrome, so it has its own Dock icon while it runs. Click that icon to bring it
  forward (to log in, or to watch an agent work).
- **Links can open in it.** Both instances are "Google Chrome" to macOS. If
  your everyday Chrome isn't running but the shared one is, a link you click in
  another app (Slack, Mail) can open in the shared Chrome and bring it forward.
  Start your everyday Chrome first to avoid this, or point `CHROME_MCP_CHROME`
  at a different browser build (e.g. Chrome for Testing), which macOS treats as
  a separate app.
- **No telemetry.** `chrome-devtools-mcp` runs with `--no-usage-statistics`,
  which also saves an extra watchdog process per session.
- **Security.** Any local process can drive the shared Chrome through the
  debugging port. That's why it uses its own profile (never your everyday one)
  and binds to `127.0.0.1` only. Don't log it into anything you wouldn't hand to
  an agent.
- **Tool calls error out instead of hanging.** If Chrome can't start (wrong
  path, port taken), the tool call returns an error with the reason, and the
  reason is also written to `wrapper.log`.
- **macOS only.** The launcher uses the macOS Chrome path and `/usr/bin/lockf`
  for its launch lock (a kernel lock, so a crashed launch can't leave it stuck).
- **Version pin.** `chrome-devtools-mcp` is pinned to match the plugin. To
  try a newer [release](https://github.com/ChromeDevTools/chrome-devtools-mcp/releases):
  `MCP_VERSION=x.y.z ./install.sh`, then `./test/all.sh`. The version each
  release of this wrapper was tested with is in [CHANGELOG.md](CHANGELOG.md).

## Troubleshooting

Every launch and every refused tool call is logged in
`~/.local/share/shared-chrome-mcp/wrapper.log`; start there.

| Symptom | Check / fix |
|---|---|
| A test reports the wrapper exited, or Chrome did not start | Read `wrapper.log`. Confirm the Chrome path, or set `CHROME_MCP_CHROME`. |
| "port 9333 is in use by another program" | Something else owns the port. Find it with `lsof -nP -iTCP:9333 -sTCP:LISTEN`, then re-run with `CHROME_MCP_PORT=<free port> ./install.sh` (it writes the port into the MCP server's `env`). |
| A session still shows "browser is already running for …/chrome-devtools-mcp/chrome-profile" | That session started before the install — restart it. Confirm the deny rule is in `~/.claude/settings.json` and `claude mcp get chrome-devtools` shows the wrapper. In another client, check its server list (Other MCP clients) for a second Chrome DevTools server still running `chrome-devtools-mcp` directly. |
| A tool call returns "Shared Chrome is unavailable: …" | The reason follows the colon; it's also in `wrapper.log`. Usually the Chrome path or the port. |
| "timed out waiting for another session to launch Chrome" | Another session's launch held the lock for 30s. Check `wrapper.log` for why that launch is slow. The lock is a kernel lock, released when its holder exits, so it can't go stale. |
| Chrome opens as soon as a session starts | An old wrapper is installed. Re-run `./install.sh` and restart the session. |
| `claude mcp get chrome-devtools` not found | Re-run `./install.sh`. |

## Tests

Run these after every change (re-install first, so the installed copy is the
code you're testing), with the shared Chrome closed:

```bash
./install.sh && ./test/all.sh          # tiers 1 + 2, about 30s
./install.sh && ./test/all.sh --e2e    # plus tier 3, before committing
```

| Tier | What it checks | Touches |
|---|---|---|
| `test/verify.sh` | Through raw MCP sessions: session start doesn't open Chrome; concurrent first calls launch it once; tabs are shared; it survives a session's process group being killed; a call right after quitting relaunches it; navigate-first sessions on a page-less Chrome work with no blank tabs left; Chrome never comes to the front | The shared Chrome (quits it only if it launched it and no other session has tabs) |
| `test/install.sh` | Install and uninstall in throwaway home folders: overrides saved in config.env (kept on a re-run, an environment value wins), symlinked settings and mode kept, earlier server restored, re-run is a no-op, a failed uninstall can be re-run, a deny rule that was already there is kept, someone else's server is left alone, a pre-1.0.0 install is moved, and install works without Claude Code (its Claude cases SKIP when `claude` is missing) | Nothing real (its own profiles and ports) |
| `test/e2e.sh` | Real `claude -p` sessions with your config: the relay loads, a session without browser use doesn't open Chrome, two sessions at once open their tabs in one Chrome launched once, nothing is refused, Chrome never comes to the front, the plugin's own Chrome never starts | The shared Chrome, and a few model calls (`E2E_MODEL`, default haiku) |

`all.sh` refuses to run if the installed files differ from the repo. `e2e.sh`
reports SKIP if the shared Chrome is already running or `claude` is missing. The focus checks need
your terminal to be allowed to control System Events (Privacy & Security >
Automation); without it they fail rather than pass silently.

## Files

```
bin/chrome-mcp-shared.sh   the MCP server command; starts the relay
bin/lazy-launch.cjs        stdio relay: launches Chrome on the first tool call, not at session start
bin/ensure-chrome.sh       launches the shared Chrome in the background if it isn't running (lock, port safety check, blank page)
bin/common.sh              defaults, the saved overrides (config.env) and the "is this the shared Chrome?" checks, shared by the scripts and tests
install.sh                 install / update / --uninstall
test/all.sh                runs the suite (add --e2e for the real-session tier)
test/verify.sh             tier 1: multi-session check against the installed wrapper
test/verify.cjs            the check itself (minimal MCP stdio client)
test/install.sh            tier 2: install / uninstall in throwaway home folders
test/e2e.sh                tier 3: real `claude -p` sessions with your config
AGENTS.md                  instructions for an agent doing the install
CHANGELOG.md               release notes, with the chrome-devtools-mcp version each release was tested with
LICENSE                    MIT
```

## License

MIT
