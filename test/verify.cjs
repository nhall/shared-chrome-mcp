// Verifies the installed wrapper: several independent MCP "sessions" share one
// Chrome. Each session is a separate wrapper process speaking MCP over stdio,
// exactly as a Claude Code session would run it.
//
//   node test/verify.cjs   (or test/verify.sh)
//
// Opens uniquely titled tabs and closes only those at the end, so an
// already-running shared Chrome (and its logins/tabs) is left alone. It only
// quits a Chrome it launched itself, and only while nothing else has tabs open.

const { spawn, execFile, execFileSync } = require('child_process');
const path = require('path');

const COMMON = path.join(__dirname, '../bin/common.sh');
const fromCommon = fn => execFileSync('bash', ['-c', `. "$1" && ${fn}`, '_', COMMON]).toString();

// Test what Claude Code runs: the overrides the server was registered with.
// The wrappers and common.sh calls below inherit them.
const [PORT, PROFILE, CHROME, INSTALL_DIR] = fromCommon('use_registered_overrides && printf "%s\\n" "$PORT" "$PROFILE" "$CHROME" "$INSTALL_DIR"').split('\n');
Object.assign(process.env, { CHROME_MCP_PORT: PORT, CHROME_MCP_PROFILE: PROFILE, CHROME_MCP_CHROME: CHROME });
const WRAPPER = path.join(INSTALL_DIR, 'chrome-mcp-shared.sh');
const BASE = `http://127.0.0.1:${PORT}`;
const TAG = `verify-${process.pid}`;

const sessions = [];
function session(name) {
  // Its own process group, so close() can signal the whole group the way a
  // session's processes may be torn down when Claude Code exits.
  const p = spawn(WRAPPER, [], { stdio: ['pipe', 'pipe', 'pipe'], detached: true });
  let buf = '', id = 0, err = '';
  const waits = {};
  p.stdout.on('data', d => {
    buf += d;
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i); buf = buf.slice(i + 1);
      try { const m = JSON.parse(line); if (m.id && waits[m.id]) { waits[m.id](m); delete waits[m.id]; } } catch {}
    }
  });
  p.stderr.on('data', d => { err += d; });
  const exited = new Promise(r => p.on('exit', code => r(code)));
  const rpc = (method, params) => Promise.race([
    new Promise(r => { const i = ++id; waits[i] = r; p.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: i, method, params }) + '\n'); }),
    exited.then(code => { throw new Error(`${name}: wrapper exited (${code}): ${err.trim().split('\n').pop()}`); }),
    new Promise((_, rej) => setTimeout(() => rej(new Error(`${name}: ${method} timed out`)), 60000)),
  ]);
  const s = {
    async init() {
      await rpc('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name, version: '0' } });
      p.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n');
    },
    async listTools() { return (await rpc('tools/list', {})).result.tools.length; },
    async call(tool, args = {}) {
      const m = await rpc('tools/call', { name: tool, arguments: args });
      if (m.error) throw new Error(`${name}: ${tool} failed: ${JSON.stringify(m.error)}`);
      const text = m.result.content.map(c => c.text).join('\n');
      if (m.result.isError) throw new Error(`${name}: ${tool} returned an error: ${text}`);
      return text;
    },
    close() {
      if (p.exitCode !== null || p.signalCode !== null) return;
      p.stdin.end();
      try { process.kill(-p.pid, 'SIGTERM'); } catch {}
    },
  };
  sessions.push(s);
  return s;
}

// Launches recorded by ensure-chrome.sh, to count how often Chrome was started.
const launches = () => Number(fromCommon('launch_count'));
const chromeUp = async () => { try { await fetch(`${BASE}/json/version`); return true; } catch { return false; } };
// PIDs of the shared Chrome's main process, using the installed common.sh.
const sharedChromePids = () => fromCommon('shared_chrome_pids').split('\n').filter(Boolean);
const pages = async () => { try { return (await (await fetch(`${BASE}/json/list`)).json()).filter(t => t.type === 'page'); } catch { return []; } };
const closeTestTabs = async () => { for (const t of await pages()) if (t.title.startsWith(TAG)) await fetch(`${BASE}/json/close/${t.id}`); };
// Chromes this test started (none were running when it began). It quits only
// those, and only if no other session has tabs open in them.
const launchedPids = new Set();
const noteLaunched = () => { for (const pid of sharedChromePids()) launchedPids.add(pid); };
async function quitLaunchedChrome() {
  const others = (await pages()).filter(t => !t.title.startsWith(TAG) && t.url !== 'about:blank');
  if (others.length) { console.log(`      not quitting Chrome: another session has ${others.length} tab(s) open`); return false; }
  for (const pid of sharedChromePids()) if (launchedPids.has(pid)) try { process.kill(Number(pid)); } catch {}
  return true;
}

// Samples which app is in front, so the test can tell whether the shared Chrome
// ever pulled itself over what the user was doing.
const frontPids = new Set();
const seenChromePids = new Set();
let focusSamples = 0;
const FRONT = 'tell application "System Events" to unix id of first process whose frontmost is true';
const focusSampler = setInterval(() => execFile('osascript', ['-e', FRONT], (e, out) => {
  if (!e) { frontPids.add(out.trim()); focusSamples++; }
}), 150);
const noteChrome = () => { for (const pid of sharedChromePids()) seenChromePids.add(pid); };

let failures = 0;
const check = (ok, msg) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${msg}`); if (!ok) failures++; };
const title = s => `${TAG}-${s}`;
const page = s => `data:text/html,<title>${title(s)}</title>${s}`;
const sleep = ms => new Promise(r => setTimeout(r, ms));

let wasRunning = true;
(async () => {
  wasRunning = (await chromeUp()) || sharedChromePids().length > 0;
  console.log(`wrapper: ${WRAPPER}\nport:    ${PORT}\nchrome already running: ${wasRunning}\n`);

  const A = session('A'), B = session('B');
  await Promise.all([A.init(), B.init()]);
  const tools = await A.listTools();
  if (!wasRunning) {
    await sleep(1000);
    check(!(await chromeUp()), `starting sessions (${tools} tools listed) does not open Chrome`);
  }
  // First tool calls from both sessions at once exercise the launch lock.
  const before = launches();
  await Promise.all([A.call('new_page', { url: page('A') }), B.call('new_page', { url: page('B') })]);
  if (!wasRunning) check(launches() - before === 1, `two sessions' first calls at once launch Chrome once (launched ${launches() - before}x)`);

  check((await A.call('list_pages')).includes(title('B')), 'session A sees the tab session B opened');
  check((await B.call('list_pages')).includes(title('A')), 'session B sees the tab session A opened');
  noteChrome();
  if (!wasRunning) noteLaunched();
  const browsers = sharedChromePids().length;
  check(browsers === 1, `exactly one shared browser process (found ${browsers})`);

  A.close();
  await sleep(1500);
  check(await chromeUp(), 'Chrome keeps running after the launching session\'s process group is killed');
  check((await B.call('list_pages')).includes(title('B')), 'session B still works after A exits');

  const C = session('C');
  await C.init();
  check((await C.call('list_pages')).includes(title('A')), 'a session that joins later sees existing tabs');
  // Calls that would bring Chrome to the front if the relay let them.
  await C.call('new_page', { url: page('fg'), background: false });
  await C.call('new_page', { url: page('iso'), isolatedContext: TAG });
  const line = (await C.call('list_pages')).split('\n').find(l => l.includes(title('A')));
  const pageId = Number((line || '').match(/^(\d+):/)?.[1]);
  if (pageId) await C.call('select_page', { pageId, bringToFront: true });
  await sleep(1000);
  B.close();
  await closeTestTabs();

  if (!wasRunning) {
    // This test launched Chrome, so it may quit it. The next call comes
    // straight away, while the old Chrome may still be shutting down.
    if (await quitLaunchedChrome()) {
      let ok = false;
      try { await C.call('list_pages'); ok = await chromeUp(); } catch (e) { console.log(`      ${e.message}`); }
      check(ok, 'a tool call made right after Chrome is quit relaunches it');
      noteChrome();
      noteLaunched();
    }

    // Sessions whose first call needs an existing page, against a Chrome that
    // has none: one launch, every call works, and no blank tabs left behind.
    await closeTestTabs();
    if (await quitLaunchedChrome()) {
      while (sharedChromePids().length) await sleep(250);
      const navs = ['D', 'E', 'F'].map(n => session(n));
      await Promise.all(navs.map(n => n.init()));
      const start = launches();
      // As an agent does: list the pages, then navigate the selected one.
      const results = await Promise.allSettled(navs.map(async (n, i) => {
        const listed = await n.call('list_pages');
        const id = Number(listed.match(/^(\d+):.*\[selected\]/m)?.[1] ?? listed.match(/^(\d+):/m)?.[1]);
        if (!id) throw new Error(`${'DEF'[i]}: list_pages showed no page: ${listed}`);
        return n.call('navigate_page', { pageId: id, type: 'url', url: page(`nav${i}`) });
      }));
      const failed = results.filter(r => r.status === 'rejected');
      for (const f of failed) console.log(`      ${f.reason.message}`);
      check(!failed.length, 'three sessions listing and navigating first on a page-less Chrome all succeed');
      check(launches() - start === 1, `...with one launch (launched ${launches() - start}x)`);
      const blank = (await pages()).filter(t => t.url === 'about:blank').length;
      check(blank === 0, `...and no blank tabs left behind (found ${blank})`);
      noteChrome();
      noteLaunched();
    }
  }
  clearInterval(focusSampler);
  if (!focusSamples) {
    check(false, 'could not read the frontmost app (allow your terminal to control System Events in Privacy & Security > Automation)');
  } else {
    const stole = [...frontPids].some(pid => seenChromePids.has(pid));
    check(!stole, `the shared Chrome never came to the front (${focusSamples} samples: launch, new pages, select_page)`);
  }
})().catch(e => {
  console.error(`FAIL  ${e.message}`);
  failures++;
}).finally(async () => {
  // Leave nothing behind, even when a check threw part-way through.
  clearInterval(focusSampler);
  await closeTestTabs();
  for (const s of sessions) s.close();
  if (!wasRunning) await quitLaunchedChrome();
  console.log(failures ? `\n${failures} check(s) failed` : '\nall checks passed');
  process.exit(failures ? 1 : 0);
});
