// Stdio relay between Claude Code and chrome-devtools-mcp.
//
// chrome-devtools-mcp (in --browserUrl mode) starts and lists its tools without
// a browser, and only connects on the first tool call. This relay passes every
// MCP message straight through, but before forwarding a `tools/call` it runs
// ensure-chrome.sh, so the shared Chrome opens only when a session actually
// uses the browser — not every time a session starts. It also keeps tool calls
// from bringing Chrome to the front over whatever the user is doing.
//
// Started by chrome-mcp-shared.sh, which sets CHROME_MCP_PORT.

const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const readline = require('readline');

const DIR = __dirname;
const PORT = process.env.CHROME_MCP_PORT;
if (!PORT) { console.error('CHROME_MCP_PORT is not set; start this through chrome-mcp-shared.sh'); process.exit(1); }
// ensure-chrome.sh waits up to 30s for the lock, 10s for a quitting Chrome to
// exit and 15s for a new one to answer.
const ENSURE_TIMEOUT_MS = 60000;
// Local time, matching ensure-chrome.sh's `date '+%F %T'`.
const stamp = () => new Date().toLocaleString('sv-SE');
const log = msg => fs.appendFileSync(path.join(DIR, 'wrapper.log'), `${stamp()} [${process.pid}] ${msg}\n`);

// --no-usage-statistics: no telemetry, and no extra watchdog process per session.
const server = spawn(
  path.join(DIR, 'node_modules/.bin/chrome-devtools-mcp'),
  ['--browserUrl', `http://127.0.0.1:${PORT}`, '--no-usage-statistics'],
  { stdio: ['pipe', 'pipe', 'inherit'] },
);
server.on('error', e => {
  log(`could not start chrome-devtools-mcp: ${e.message}`);
  console.error(`could not start chrome-devtools-mcp (${e.message}); re-run install.sh`);
  process.exit(1);
});

// The relay's own replies and the server's output share stdout, so both go out
// as whole lines from this one writer and can't interleave.
const send = line => process.stdout.write(line + '\n');
const serverOutput = readline.createInterface({ input: server.stdout }).on('line', send);

// Exit with the server's status once its last output line has been relayed
// (or after a second, in case something the server spawned holds stdout open).
server.on('exit', (code, signal) => {
  const status = code ?? 128 + (os.constants.signals[signal] || 0);
  const exit = () => process.exit(status);
  serverOutput.on('close', exit);
  setTimeout(exit, 1000);
});

// Resolves to null once Chrome is ready for this tool, or to the reason it isn't.
const ensureChrome = tool => new Promise(resolve => {
  // Its own process group, so a timeout can stop it and everything it started
  // (lockf and the locked re-run) — but not Chrome, which LaunchServices owns.
  const child = spawn(path.join(DIR, 'ensure-chrome.sh'), {
    stdio: ['ignore', 'ignore', 'pipe'],
    detached: true,
    env: { ...process.env, CHROME_MCP_TOOL: tool },
  });
  let stderr = '';
  child.stderr.on('data', d => { stderr += d; });
  const timer = setTimeout(() => { try { process.kill(-child.pid, 'SIGTERM'); } catch {} }, ENSURE_TIMEOUT_MS);
  child.on('error', e => { clearTimeout(timer); resolve(e.message); });
  child.on('exit', code => {
    clearTimeout(timer);
    resolve(code === 0 ? null : stderr.trim() || (code === null ? 'timed out launching Chrome' : 'unknown error'));
  });
});

const refusal = (id, reason) => ({
  jsonrpc: '2.0',
  id,
  result: { isError: true, content: [{ type: 'text', text: `Shared Chrome is unavailable: ${reason}` }] },
});

// Tool arguments that would bring Chrome to the front: new_page opens in the
// foreground unless told otherwise, and select_page can be asked to focus.
// Every page stays usable in the background (snapshots, screenshots, input).
function keepInBackground(params) {
  const args = params.arguments;
  if (!args) return false;
  if (params.name === 'new_page' && args.background !== true) { args.background = true; return true; }
  if (params.name === 'select_page' && args.bringToFront) { args.bringToFront = false; return true; }
  return false;
}

async function relay(line) {
  let msg;
  try { msg = JSON.parse(line); } catch { msg = null; }
  if (msg && msg.method === 'tools/call') {
    const params = msg.params || {};
    const reason = await ensureChrome(params.name || '');
    if (reason) {
      log(`tool call refused: ${reason}`);
      send(JSON.stringify(refusal(msg.id, reason)));
      return;
    }
    if (keepInBackground(params)) line = JSON.stringify(msg);
  }
  server.stdin.write(line + '\n');
}

// Messages are handled strictly in order, so a launch holds back the messages
// queued behind it. The launch runs asynchronously, so signals still get through.
let queue = Promise.resolve();
readline.createInterface({ input: process.stdin })
  .on('line', line => { queue = queue.then(() => relay(line)).catch(e => log(`relay error: ${e.message}`)); })
  .on('close', () => { queue = queue.then(() => server.stdin.end()); });

for (const sig of ['SIGTERM', 'SIGINT', 'SIGHUP']) process.on(sig, () => server.kill(sig));
