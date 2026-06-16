const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');
const http = require('http');

const AUTHORITY = 'alielzei.recall';

// id (process id, as string) -> Terminal  (this window only)
const sessions = new Map();

// Fallback: title the optional shell snippet stamps, "recall-<id>"
const ID_RE = /recall-([A-Za-z0-9]+)/;

// Shared cross-window registry: one file per window (named by ext-host pid).
const REG_DIR = path.join(os.homedir(), '.recall', 'windows');
const MY_FILE = path.join(REG_DIR, `${process.pid}.json`);
const CFG = path.join(os.homedir(), '.recall', 'config.json');

// Path to the RecallNotifier helper binary (signed UNUserNotificationCenter app).
// install.sh records the .app path; fall back to the standard ~/Applications spot.
let NOTIFIER = null;
function resolveNotifier() {
  const fromApp = (app) => path.join(app, 'Contents/MacOS/RecallNotifier');
  try {
    const c = JSON.parse(fs.readFileSync(CFG, 'utf8'));
    if (c.notifierApp && fs.existsSync(fromApp(c.notifierApp))) return fromApp(c.notifierApp);
  } catch (_) {}
  const probe = fromApp(path.join(os.homedir(), 'Applications/RecallNotifier.app'));
  return fs.existsSync(probe) ? probe : null;
}

// Dismiss the notification for a terminal (id = its pid) — called when the user
// brings that terminal into focus, so a stale notification clears at once.
function dismiss(pid) {
  if (!NOTIFIER || pid == null) return;
  cp.execFile(NOTIFIER, ['remove', '--id', String(pid)], () => {});
}

// Post a test notification (debug) via the helper. Clicking it focuses this
// window's active terminal, exercising the whole post -> click -> focus path.
async function postTest() {
  if (!NOTIFIER) return false;
  const app = path.dirname(path.dirname(path.dirname(NOTIFIER))); // .../RecallNotifier.app
  const folder = (vscode.workspace.workspaceFolders || [])[0];
  const args = ['-n', app, '--args', 'post',
    '--title', 'Recall — test',
    '--subtitle', folder ? folder.name : 'Recall',
    '--message', 'Test notification — click to focus this terminal.',
    '--id', 'recall-test', '--sound'];
  const active = vscode.window.activeTerminal;
  if (active) { try { args.push('--url', await focusUrl(await active.processId)); } catch (_) {} }
  cp.execFile('open', args, () => {});
  return true;
}

// ---- Dashboard: a local web UI listing live Claude sessions + status ----------
// Claude Code has no "list sessions" API, so session state is event-sourced by the
// hooks into ~/.recall/sessions/. This server joins that with the per-window
// registry (pid -> windowId focus URL) so clicking a session jumps to its terminal.
const DASH_PORT = 51789;
const SESS_DIR = path.join(os.homedir(), '.recall', 'sessions');

function readJSON(p) { try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) { return null; } }

function pidUrlMap() {
  const map = {};
  try {
    for (const name of fs.readdirSync(REG_DIR)) {
      if (!name.endsWith('.json')) continue;
      const ehpid = Number(name.replace('.json', ''));
      try { process.kill(ehpid, 0); } catch (e) { if (e && e.code === 'ESRCH') continue; }
      const d = readJSON(path.join(REG_DIR, name));
      if (d && d.terminals) for (const [pid, url] of Object.entries(d.terminals)) map[pid] = url;
    }
  } catch (_) {}
  return map;
}

function listSessions() {
  const urls = pidUrlMap();
  const out = [];
  let names = [];
  try { names = fs.readdirSync(SESS_DIR); } catch (_) {}
  for (const name of names) {
    if (!name.endsWith('.json')) continue;
    const s = readJSON(path.join(SESS_DIR, name));
    if (!s || !s.session_id) continue;
    // Prune if the terminal's shell pid is gone (terminal closed).
    if (s.pid) {
      try { process.kill(Number(s.pid), 0); }
      catch (e) { if (e && e.code === 'ESRCH') { try { fs.unlinkSync(path.join(SESS_DIR, name)); } catch (_) {} continue; } }
    }
    out.push({
      shortId: String(s.session_id).slice(0, 8),
      folder: s.cwd ? path.basename(s.cwd) : '(no folder)',
      cwd: s.cwd || '',
      state: s.state || 'idle',
      ts: s.ts || 0,
      url: s.pid ? (urls[s.pid] || `vscode://${AUTHORITY}/focus?id=${s.pid}`) : null,
    });
  }
  out.sort((a, b) => (b.ts || 0) - (a.ts || 0));
  return out;
}

const DASHBOARD_HTML = `<!doctype html><html><head><meta charset="utf-8">
<title>Recall</title><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root{color-scheme:dark}
  body{margin:0;background:#0f172a;color:#e2e8f0;font:15px -apple-system,system-ui,sans-serif}
  header{padding:20px 24px;border-bottom:1px solid #1e293b;display:flex;align-items:center;gap:10px}
  header h1{font-size:18px;margin:0;font-weight:700}
  header .dot{width:10px;height:10px;border-radius:50%;background:#f59e0b}
  main{padding:18px 24px;display:grid;gap:12px;max-width:760px}
  .card{display:flex;align-items:center;gap:14px;padding:14px 16px;background:#1e293b;border:1px solid #334155;border-radius:12px;cursor:pointer;transition:.15s}
  .card:hover{border-color:#64748b;transform:translateY(-1px)}
  .badge{font-size:12px;font-weight:700;padding:4px 10px;border-radius:999px;white-space:nowrap}
  .working{background:#1e3a8a;color:#bfdbfe}.waiting{background:#7c2d12;color:#fed7aa}.idle{background:#334155;color:#94a3b8}
  .meta{flex:1;min-width:0}
  .folder{font-weight:600}.sub{color:#94a3b8;font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .empty{color:#64748b;padding:40px 0;text-align:center}
  button{margin-left:auto;background:#334155;color:#e2e8f0;border:1px solid #475569;border-radius:8px;padding:7px 12px;font:13px inherit;cursor:pointer}
  button:hover{background:#475569}
  #count{color:#94a3b8;font-size:13px;margin-left:14px}
</style></head><body>
<header><span class="dot"></span><h1>Recall</h1>
<button id="test" onclick="test()">Send test notification</button>
<span id="count"></span></header>
<main id="list"></main>
<script>
const order={waiting:0,working:1,idle:2};
async function test(){const b=document.getElementById('test');const o=b.textContent;b.textContent='Sent ✓';setTimeout(()=>b.textContent=o,1500);try{await fetch('/api/test')}catch(e){}}
async function tick(){
  let data=[]; try{data=await (await fetch('/api/sessions')).json()}catch(e){}
  data.sort((a,b)=>(order[a.state]??9)-(order[b.state]??9)||b.ts-a.ts);
  const list=document.getElementById('list');
  document.getElementById('count').textContent=data.length?data.length+' session'+(data.length>1?'s':''):'';
  if(!data.length){list.innerHTML='<div class="empty">No Claude sessions running.</div>';return}
  list.innerHTML=data.map(s=>{
    const label=s.state==='waiting'?'NEEDS YOU':s.state==='working'?'WORKING':'IDLE';
    return '<div class="card" onclick="jump(\\''+(s.url||'')+'\\')">'
      +'<span class="badge '+s.state+'">'+label+'</span>'
      +'<div class="meta"><div class="folder">'+s.folder+'</div>'
      +'<div class="sub">'+(s.cwd||'')+' · '+s.shortId+'</div></div></div>';
  }).join('');
}
function jump(url){ if(url) location.href=url; }
tick(); setInterval(tick,1500);
</script></body></html>`;

let dashServer = null;
function startDashboard() {
  dashServer = http.createServer((req, res) => {
    if (req.url && req.url.startsWith('/api/sessions')) {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(listSessions()));
      return;
    }
    if (req.url && req.url.startsWith('/api/test')) {
      postTest().then((ok) => {
        res.writeHead(ok ? 200 : 503, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok }));
      });
      return;
    }
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(DASHBOARD_HTML);
  });
  dashServer.on('error', (e) => {
    dashServer = null;
    out(e && e.code === 'EADDRINUSE' ? 'dashboard: another window hosts it' : `dashboard error: ${e && e.message}`);
  });
  dashServer.listen(DASH_PORT, '127.0.0.1', () => out(`dashboard at http://127.0.0.1:${DASH_PORT}`));
}

let channel;
function out(msg) {
  if (channel) channel.appendLine(`[${new Date().toISOString()}] ${msg}`);
}

function indexName(terminal) {
  const m = terminal.name && terminal.name.match(ID_RE);
  if (m) sessions.set(m[1], terminal);
}

async function indexTerminal(terminal) {
  try {
    const pid = await terminal.processId;
    if (pid != null) sessions.set(String(pid), terminal);
  } catch (_) {}
  indexName(terminal);
}

async function rescan() {
  sessions.clear();
  await Promise.all(vscode.window.terminals.map(indexTerminal));
}

// This window's Electron id, recovered from asExternalUri (which stamps it but
// double-encodes the query, vscode#112383 — so we extract just the value).
async function getWindowId() {
  try {
    const base = vscode.Uri.parse(`vscode://${AUTHORITY}/focus?id=0`);
    const s = (await vscode.env.asExternalUri(base)).toString();
    const m = s.match(/windowId(?:=|%3D)([^&%]+)/i);
    return m ? m[1] : null;
  } catch (_) {
    return null;
  }
}

// Build a clean focus URL for a pid, tagged with this window's id.
// PR microsoft/vscode#80260 routes vscode:// opens to the window in `windowId`.
async function focusUrl(pid) {
  const windowId = await getWindowId();
  return windowId
    ? `vscode://${AUTHORITY}/focus?id=${pid}&windowId=${windowId}`
    : `vscode://${AUTHORITY}/focus?id=${pid}`;
}

// Publish this window's terminals -> windowId-tagged URLs to the shared registry.
async function publish() {
  try {
    fs.mkdirSync(REG_DIR, { recursive: true });
    await rescan();
    const terminals = {};
    for (const t of vscode.window.terminals) {
      const pid = await t.processId;
      if (pid == null) continue;
      terminals[String(pid)] = await focusUrl(pid);
    }
    fs.writeFileSync(MY_FILE, JSON.stringify({ terminals, ts: Date.now() }));
    out(`published ${Object.keys(terminals).length} terminal(s)`);
  } catch (e) {
    out(`publish error: ${e && e.message}`);
  }
}

// Remove registry files whose owning ext-host process is gone (stale after reload).
function cleanStaleFiles() {
  try {
    for (const name of fs.readdirSync(REG_DIR)) {
      const m = name.match(/^(\d+)\.json$/);
      if (!m || Number(m[1]) === process.pid) continue;
      try {
        process.kill(Number(m[1]), 0);
      } catch (e) {
        if (e && e.code === 'ESRCH') {
          try { fs.unlinkSync(path.join(REG_DIR, name)); } catch (_) {}
        }
      }
    }
  } catch (_) {}
}

async function focusSession(id) {
  await rescan();
  const term = sessions.get(id);
  if (term) {
    term.show(false); // false = take focus
    out(`focused terminal ${id}`);
    return true;
  }
  out(`terminal ${id} not in this window; known: ${[...sessions.keys()].join(',') || '(none)'}`);
  return false;
}

function activate(context) {
  channel = vscode.window.createOutputChannel('Recall');
  out(`activated (extHost pid ${process.pid})`);
  NOTIFIER = resolveNotifier();
  out(`notifier: ${NOTIFIER || '(not found — focus-dismiss disabled)'}`);
  fs.mkdirSync(REG_DIR, { recursive: true });
  cleanStaleFiles();
  publish();
  startDashboard();

  const statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
  statusItem.text = '$(history) Recall';
  statusItem.tooltip = 'Open the Recall dashboard';
  statusItem.command = 'recall.openDashboard';
  statusItem.show();

  context.subscriptions.push(
    channel,
    vscode.window.onDidOpenTerminal(() => setTimeout(publish, 800)),
    vscode.window.onDidCloseTerminal(() => publish()),
    // Republish on focus / active-terminal change so coverage self-heals and the
    // windowId stays fresh. Also dismiss the focused terminal's notification — this
    // is the "I brought the terminal back" signal the Claude hooks can't see.
    vscode.window.onDidChangeWindowState((s) => {
      if (!s.focused) return;
      publish();
      const t = vscode.window.activeTerminal;
      if (t) t.processId.then(dismiss);
    }),
    vscode.window.onDidChangeActiveTerminal((t) => {
      publish();
      if (t) t.processId.then(dismiss);
    }),
    vscode.window.registerUriHandler({
      async handleUri(uri) {
        out(`handleUri: ${uri.toString()}`);
        const id = new URLSearchParams(uri.query).get('id');
        if (!id) {
          vscode.window.showWarningMessage('Recall: no ?id= in link');
          return;
        }
        if (!(await focusSession(id))) {
          vscode.window.showWarningMessage(`Recall: terminal "${id}" is not in this window`);
        }
      },
    }),
    vscode.commands.registerCommand('recall.copyLink', async () => {
      const active = vscode.window.activeTerminal;
      if (!active) {
        vscode.window.showWarningMessage('Recall: no active terminal');
        return;
      }
      const pid = await active.processId;
      const link = await focusUrl(pid);
      await vscode.env.clipboard.writeText(link);
      vscode.window.showInformationMessage(`Recall: copied ${link}`);
    }),
    vscode.commands.registerCommand('recall.openDashboard', () => {
      vscode.env.openExternal(vscode.Uri.parse(`http://127.0.0.1:${DASH_PORT}`));
    }),
    vscode.commands.registerCommand('recall.sendTest', async () => {
      const ok = await postTest();
      vscode.window.showInformationMessage(ok ? 'Recall: test notification sent' : 'Recall: notifier not found');
    }),
    statusItem,
    { dispose: () => { if (dashServer) dashServer.close(); } }
  );
}

function deactivate() {
  try { fs.unlinkSync(MY_FILE); } catch (_) {}
  try { if (dashServer) dashServer.close(); } catch (_) {}
}

module.exports = { activate, deactivate };
