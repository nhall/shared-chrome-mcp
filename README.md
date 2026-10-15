# shared-chrome-mcp

A small wrapper that makes the
[Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp)
work the way you'd expect it to out of the box: every agent session on a Mac
(Claude Code, Codex, Gemini CLI, Cursor, or any MCP client) uses it at the same
time, in one shared Chrome, with logins that persist. Chrome opens only when a
session actually uses it, and stays in the background.

It doesn't fork or replace the Chrome DevTools MCP. The real
`chrome-devtools-mcp`, maintained by the Chrome DevTools team, runs underneath
unchanged, at a pinned version you can upgrade.

## The problem

Out of the box, each agent session starts its own copy of the Chrome DevTools
MCP, and each copy launches Chrome with the same profile. Chrome allows one
instance per profile, so the first session wins and every other one fails with:

> The browser is already running for …/chrome-profile. Use --isolated to run
> multiple browser instances.

## Install

Requirements: macOS, Google Chrome, Node 22+ and npm, `jq`, `curl`, `lsof`.

```bash
git clone https://github.com/nhall/shared-chrome-mcp.git ~/repos/shared-chrome-mcp
cd ~/repos/shared-chrome-mcp
./install.sh
```

If Claude Code is installed, `install.sh` registers the wrapper with it. For
Codex, Gemini CLI, Cursor or another client, add it yourself:
[docs/clients.md](docs/clients.md).

Then restart open sessions, and log into the sites you test once in the shared
Chrome. Every session reuses those logins.

Prefer to have an agent do it? Open your agent in this folder and say
"install this" — see [AGENTS.md](AGENTS.md).

## Good to know

- **Finding the shared Chrome.** It's a separate instance from your everyday
  Chrome, with its own Dock icon while it runs. Click it to log in or to watch
  an agent work.
- **Sessions share tabs.** Each session sees every tab, so agents should act
  only on tabs they opened, and close them when done. Tabs aren't closed when
  a session ends.
- **Links can open in it.** If your everyday Chrome isn't running but the
  shared one is, a link you click in another app can open in the shared Chrome.
  Start your everyday Chrome first, or see
  [Configuration](docs/install.md#configuration) to use a separate browser build.
- **Security.** Any local process can drive the shared Chrome. It uses its own
  profile and listens on `127.0.0.1` only, but don't log it into anything you
  wouldn't hand to an agent.

## Uninstall

```bash
./install.sh --uninstall
```

This restores your config, quits the shared Chrome and keeps its profile, so
your logins survive a reinstall. Details: [docs/install.md](docs/install.md#uninstall).

## More

- [Other MCP clients](docs/clients.md): Codex, Gemini CLI, Cursor
- [Install details](docs/install.md): what `install.sh` changes, configuration,
  upgrading `chrome-devtools-mcp`, manual install, uninstall
- [How it works](docs/how-it-works.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Development](docs/development.md): tests and file map
- [Changelog](CHANGELOG.md)

## License

MIT
