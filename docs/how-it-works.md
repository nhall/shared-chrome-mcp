# How it works

Each client's MCP server entry points at a small wrapper
(`bin/chrome-mcp-shared.sh`) instead of `chrome-devtools-mcp` directly. The
wrapper starts a stdio relay (`bin/lazy-launch.cjs`) in front of
`chrome-devtools-mcp --browserUrl http://127.0.0.1:9333`, which connects to a
running browser instead of launching its own.

- **Session start:** the relay passes everything straight through. The session
  gets its tools immediately and **no Chrome opens**. A session that never
  touches the browser never launches one.
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

## Chrome stays in the background

It launches with no window of its own. The relay opens every `new_page` in the
background (even if the agent asks for the foreground) and drops `bringToFront`
from `select_page`; snapshots, screenshots and input all work on background
pages. If Chrome has no pages (fresh launch, or you closed all its windows), a
blank one is opened in the background first, so tools like `navigate_page` work.

## chrome-devtools-mcp stays in charge of the tools

The relay knows only `new_page` and `select_page` by name (the `TOOLS` table in
`bin/lazy-launch.cjs`). Every other tool, including any a new release adds, is
passed through unchanged.

## Details

- **Tool calls error out instead of hanging.** If Chrome can't start (wrong
  path, port taken), the tool call returns an error with the reason, and the
  reason is also written to `wrapper.log`.
- **Security.** Any local process can drive the shared Chrome through the
  debugging port. That's why it uses its own profile (never your everyday one)
  and binds to `127.0.0.1` only.
- **No telemetry.** `chrome-devtools-mcp` runs with `--no-usage-statistics`,
  which also saves an extra watchdog process per session.
- **macOS only.** The launcher uses the macOS Chrome path and `/usr/bin/lockf`
  for its launch lock (a kernel lock, so a crashed launch can't leave it stuck).
