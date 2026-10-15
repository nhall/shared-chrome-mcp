# Development

Changing this repo? Read [AGENTS.md](../AGENTS.md) too: it lists the
invariants the tests guard and the steps for each change and release.

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
reports SKIP if the shared Chrome is already running or `claude` is missing.
The focus checks need your terminal to be allowed to control System Events
(Privacy & Security > Automation); without it they fail rather than pass
silently.

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
docs/                      details linked from the README
AGENTS.md                  instructions for an agent installing or changing this repo
CHANGELOG.md               release notes, with the chrome-devtools-mcp version each release was tested with
```
