# Recall — design notes & ideas (brainstorm)

> Status: **brainstorming**, not committed design. The shipped architecture lives in
> the README / DISTRIBUTION. This file is the scratchpad for where it could go next.

## Seed (from notes.txt)

> what if the code extension was the one to
> - send the notifications
> - watch the output
> - …

That's the thread below: make the **extension** the owner of the notification
lifecycle instead of the hook.

---

## Idea 1 — Make the extension the notification owner

**Today:** the Claude Code hook calls `terminal-notifier` directly. The extension
just publishes a registry (pid → windowId URL) and dismisses on focus.

**Proposed:** the hook hands the request to the extension; the extension decides
whether/what to post and calls `terminal-notifier`. The extension becomes the single
owner of notify **and** dismiss.

```
CC hook  ──(pid + message)──>  extension (resident process)  ──>  terminal-notifier
```

### Why this is worth it
- **Focus-aware suppression** — don't notify at all when you're *already looking at
  that terminal*. Only the extension can see focus, so this is impossible with the
  hook posting directly. (Biggest win — it's the whole "stop useless notifications"
  goal.)
- **Eliminates the registry** — the window that owns the terminal posts the
  notification and bakes in *its own* windowId firsthand. No lookup file.
- **Single lifecycle owner** — post + dismiss + suppress in one place, less
  duplication.

### How the hook reaches the extension (transport)

The extension already runs as a long-lived **Node.js process** (the VSCode Extension
Host) — one per window. Not a server by default, but it can be.

- **A. File-drop + `fs.watch` (recommended).** Hook writes `~/.recall/outbox/<pid>.json`
  and exits. Every window watches the dir; the window that **owns** that PID handles
  it. No ports, no auth — reuses `~/.recall` + `fs.watch` we already have.
- **B. Socket server.** Extension `listen()`s on a port and writes a lockfile
  (exactly how Claude's own `ide` integration works); hook `curl`s it. More machinery,
  and *N windows = N ports* → the hook has to find the right one.
- **(rejected) `vscode://alielzei.recall/<id>`.** Tempting and simple, but a `vscode://`
  open routes to the **focused** window (wrong target) and is awkward for carrying the
  message payload / deciding to post. Calling a process is strictly better.

### The "process with a map" note
The idea of *a resident process holding a `PID → terminal/window` map that the hook
calls with a PID* — that resident process **is the extension host**. It already keeps
an in-memory `sessions` map (pid → Terminal). So "call a process with a PID" == drop a
file / hit a socket that the extension picks up and resolves. No separate daemon needed.

### New flow (transport A)
```
hook: resolve terminal pid → write outbox/<pid>.json {message, cwd}
every window: watch outbox/
  owner of pid?  no  → ignore (another window has it)
                 yes → focused & this terminal active? → SUPPRESS (delete, post nothing)
                                                  else → terminal-notifier \
                                                           -open vscode://…&windowId=<OWN> \
                                                           -group <pid>
```

### Costs / open questions
- **Notifications require the extension to be running.** If VSCode/ext-host is down the
  request file just sits there. (But no VSCode = no terminal to focus anyway.) Optional
  fallback: hook waits ~1s and, if the file wasn't consumed, posts via terminal-notifier
  itself — at the cost of latency. Start without it.
- **Stale requests** (terminal died, nobody owns the pid) → add an `outbox/` sweep
  (we already sweep stale window files).
- Keep `handleUri` (click-to-focus) and the hook's process-walk (it still needs the pid).

---

## Idea 2 — Toggle notifications on/off from the extension

Make it one click to mute/unmute.

- A **status-bar item** (🔔 on / 🔕 off) + a command `recall.toggleNotifications`,
  and/or a `recall.enabled` setting.
- If the **extension owns posting** (Idea 1): "off" simply means don't post — clean.
- If the **hook still posts**: the hook reads an `enabled` flag from
  `~/.recall/config.json` and skips when false. (Another reason to centralize posting
  in the extension.)
- Could also support per-window or per-workspace muting since the extension knows which
  window it is.

---

## Decisions pending
- Transport **A (file-drop)** vs **B (socket)**.
- **Suppress-when-focused**: on by default, or opt-in?
- Remove the registry outright, or keep it as a fallback during the transition?
- Toggle scope: global vs per-window/workspace.
