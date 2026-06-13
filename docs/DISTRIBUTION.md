# Maintainer / distribution notes

## Components
1. **VSCode extension** (`extension/`) — registers the
   `vscode://alielzei.recall/focus?id=<pid>&windowId=<N>` handler, routes via
   `windowId` (VSCode PR #80260), and publishes the per-window registry
   `~/.recall/windows/<extHostPid>.json` (pid → windowId-tagged URL). The registry is
   the single source of truth for resolving a terminal's windowId from outside VSCode.
2. **Notification hook** (`hooks/notify.sh` → installed as
   `~/.claude/hooks/recall-notify.sh`, plus a `Notification` entry in
   `~/.claude/settings.json`) — resolves the terminal's shell PID by walking its own
   process tree (shell-agnostic), looks the PID up in the registry, and fires
   `terminal-notifier -open <windowId-tagged-url>`.
3. **Optional shell snippet** (`shell/recall.zsh`) — only prints an in-terminal link
   and a `recall-<id>` tab title. Not needed for notifications. zsh-only.

The id everywhere is the terminal's shell PID (`Terminal.processId` == the PID the
process-walk finds).

## Key facts
- `windowId` is **mandatory** for cross-window routing; only the extension can mint
  it (via `asExternalUri`, which double-encodes the query — vscode#112383 — so we
  extract just the value). The shell has no access to it.
- Resolution is **lazy** via the registry: the notification fires long after the
  extension activated/published, so a terminal is covered as soon as its window's
  extension is active — including already-open terminals (it republishes on activate,
  open/close, and focus/active-terminal change). Requirement: reload each window once
  after install.
- An earlier design injected the windowId into the terminal env
  (`environmentVariableCollection`); it was inherently racy (only reaches terminals
  opened after activation; the only race-free mode caches globally → stale,
  wrong-window id) and was removed. The registry is the race-free replacement.

## Publishing the extension
- The publish identity sets the URI authority: `vscode://alielzei.recall/…`. If the
  `publisher`/`name` ever changes, update it in **three places together**:
  `extension/extension.js` (`AUTHORITY`), `hooks/notify.sh`, `shell/recall.zsh`.
- Publish to the **VS Marketplace** (`vsce publish`) *and* **Open VSX** (`ovsx publish`)
  so VSCodium/Cursor/Windsurf users can install it.
- Once published, `install.sh` can `code --install-extension alielzei.recall` instead
  of building from source.

## Caveats to document
- **macOS only** today (terminal-notifier, the `ps` walk, the `Code Helper` match).
- Process-walk can miss tmux/screen/remote-SSH/login-shell wrappers.
- Persistent (permission) notifications need terminal-notifier's **Alerts** style.
- Stale registry files from crashed windows are skipped by the hook and pruned on the
  next extension activation.

## Hardening checklist before shipping wide
- [ ] Publish to Marketplace + Open VSX; switch `install.sh` to install from there.
- [ ] OS-aware notifier (notify-send / PowerShell) or document macOS-only.
- [ ] Sturdier PID resolution for tmux/SSH/wrapper shells, or document the limit.
- [ ] Optional: ship a Claude Code plugin variant that auto-wires the hook and runs
      the extension install on `SessionStart`.
