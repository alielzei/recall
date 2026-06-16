const vscode = require('vscode');
const fs = require('fs');
const os = require('os');
const path = require('path');
const cp = require('child_process');

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
    })
  );
}

function deactivate() {
  try { fs.unlinkSync(MY_FILE); } catch (_) {}
}

module.exports = { activate, deactivate };
