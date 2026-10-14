# Agent guide: shared-chrome-mcp

This repo makes every agent session on a Mac (Claude Code, Codex, Gemini CLI,
Cursor, any MCP client) share one Chrome through the Chrome DevTools MCP. `README.md` explains the design, lists what `install.sh`
changes, and describes the tests.

## Rules

- **Touch only the shared Chrome**: the process `shared_chrome_pids` in
  `bin/common.sh` finds. Any other Chrome (the user's own, or one an old plugin
  server launched) belongs to someone else, so report it and ask before acting
  on it.
- **Change config through `install.sh`**, which backs up and merges
  `~/.claude.json` and `~/.claude/settings.json`. If a change truly needs a hand
  edit, read the file first and merge into it, keeping everything else as it was.
  Register other clients as "Other MCP clients" in `README.md` says, with the
  client's own `mcp add` command where it has one.
- **Change behavior here, in this repo.** The plugin's cache
  (`~/.claude/plugins/cache/`) is rewritten by every plugin update, so leave it
  untouched.
- **In the shared Chrome, work in tabs you open** (`new_page`) and close them when
  done; other sessions are using the same browser.

## Installing for a user

1. **Show the user what will change**: the "What `install.sh` changes" table in
   `README.md`. Continue once they agree.
2. **Run `./install.sh`** from the repo root (re-running is safe). If its
   preflight stops on something missing, tell the user what it is and how to get
   it, and ask before installing system packages yourself. Done when it prints
   "installed. Next:". It registers with Claude Code if `claude` is on PATH.
   For any other client the user runs, register it as "Other MCP clients" in
   `README.md` says, after showing them that change too.
3. **Verify with `./test/all.sh`** with the shared Chrome closed: the output shows
   `chrome already running: false`. If it's running, ask the user before quitting
   it. Done when every tier in the summary shows PASS and it exits 0.
4. **Tell the user** to restart their open agent sessions, and to log into
   the sites they test once in the shared Chrome (its Dock icon brings it
   forward).

## Changing this repo

These invariants are the point of the project. Each has a test that goes red
when it breaks:

- Chrome opens only on a session's first browser tool call.
- Chrome stays in the background: launching it and every tool call leave the
  user's front app in front.
- All sessions share one Chrome, launched once even when sessions call at once,
  and it outlives the session that launched it.
- Uninstall puts the user's config back the way it was before the first install.

1. **After every change**, run `./install.sh`, then `./test/all.sh`, with the
   shared Chrome closed. `all.sh` refuses to run while the installed copy differs
   from the repo.
2. **When you add behavior**, add the check that would go red without it to the
   matching tier ("Tests" in `README.md`).
3. **Before committing**, run `./test/all.sh --e2e`. Commit only when it exits 0.
4. **Update `README.md` in the same change** when behavior changes. Point at
   sections, files and commands; line numbers go stale.
5. **Add a line under "Unreleased" in `CHANGELOG.md`** for anything a user
   would notice: behavior, install, config, or the pinned `MCP_VERSION`.

## Releasing

Only when the user asks for a release, on `main` after `./test/all.sh --e2e`
passes:

1. In `CHANGELOG.md`, rename "Unreleased" to the new version, add the
   `chrome-devtools-mcp` version it was tested with, and start a new empty
   "Unreleased" above it. Update the compare links at the bottom.
2. Commit, tag `vX.Y.Z`, push the tag, and create the GitHub release with that
   version's changelog section as its notes
   (`gh release create vX.Y.Z --notes-file <file>`).

## Uninstalling

Before running `./install.sh --uninstall`, tell the user it quits the shared
Chrome. It keeps the Chrome profile (their logins); delete the profile folder
only once the user confirms.

## When something fails

Install, a test, or a tool call ("Shared Chrome is unavailable: …"): see
"Troubleshooting" in `README.md`.
