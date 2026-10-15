# Troubleshooting

Every launch and every refused tool call is logged in
`~/.local/share/shared-chrome-mcp/wrapper.log`; start there.

| Symptom | Check / fix |
|---|---|
| A test reports the wrapper exited, or Chrome did not start | Read `wrapper.log`. Confirm the Chrome path, or set `CHROME_MCP_CHROME`. |
| "port 9333 is in use by another program" | Something else owns the port. Find it with `lsof -nP -iTCP:9333 -sTCP:LISTEN`, then re-run with `CHROME_MCP_PORT=<free port> ./install.sh` (it saves the port for every client). |
| A session still shows "browser is already running for …/chrome-devtools-mcp/chrome-profile" | That session started before the install — restart it. Confirm the deny rule is in `~/.claude/settings.json` and `claude mcp get chrome-devtools` shows the wrapper. In another client, check its server list ([clients.md](clients.md)) for a second Chrome DevTools server still running `chrome-devtools-mcp` directly. |
| A tool call returns "Shared Chrome is unavailable: …" | The reason follows the colon; it's also in `wrapper.log`. Usually the Chrome path or the port. |
| "timed out waiting for another session to launch Chrome" | Another session's launch held the lock for 30s. Check `wrapper.log` for why that launch is slow. The lock is a kernel lock, released when its holder exits, so it can't go stale. |
| Chrome opens as soon as a session starts | An old wrapper is installed. Re-run `./install.sh` and restart the session. |
| `claude mcp get chrome-devtools` not found | Re-run `./install.sh`. |
