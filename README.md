# Recall

**Click a Claude Code notification → jump straight back to the exact terminal it came from, in the right window.**

When Claude Code needs your attention (a permission prompt, your turn, a finished task), Recall fires a native macOS notification. Clicking it focuses the precise integrated terminal that raised it — even if it's a different tab in a different VSCode window.

---

## Why

Run several Claude sessions across tabs and windows and you lose track of *which* one just pinged you. macOS notifications can't deep-link to a specific terminal on their own, and VSCode has no public API to focus a terminal by id. Recall bridges that gap.

## How it works

```
Claude notification ──> notify.sh (hook) ──> terminal-notifier  ──click──> vscode:// link
                              │                                                   │
                   resolves the terminal's                          routed by windowId to the
                   shell PID (process walk)                         right window, focuses the tab
                              │                                                   ▲
                              └──> looks up windowId in ◀── extension publishes ──┘
                                   ~/.recall/windows/*.json     (per-window registry)
```

1. **Extension** registers a `vscode://alielzei.recall/focus?id=<pid>&windowId=<N>` handler and publishes a per-window registry mapping each terminal's shell PID → a windowId-tagged URL. `windowId` routing ([VSCode PR #80260](https://github.com/microsoft/vscode/pull/80260)) sends the click to the correct window and raises it.
2. **Notification hook** (`notify.sh`) resolves the terminal's PID, looks up its windowId-tagged link in the registry, and opens it via `terminal-notifier`.

Only the extension can learn a window's id, so the registry is the bridge between "a notification fired in some shell" and "focus that shell's tab in its window."

## Requirements

- macOS
- [VSCode](https://code.visualstudio.com/) with the `code` CLI on PATH (*Shell Command: Install 'code' command in PATH*)
- [`terminal-notifier`](https://github.com/julienXX/terminal-notifier) — `brew install terminal-notifier`
- `jq` — `brew install jq`
- [Claude Code](https://claude.com/claude-code)

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/alielzei/recall/main/install.sh | bash
```

Or clone and run:

```sh
git clone https://github.com/alielzei/recall.git && cd recall && ./install.sh
```

The installer builds + installs the extension, drops the hook at `~/.claude/hooks/recall-notify.sh`, and merges a `Notification` hook into `~/.claude/settings.json` (without touching your existing hooks).

**Then reload each open VSCode window once** (Cmd+Shift+P → *Developer: Reload Window*) so the extension activates and publishes its registry.

## Uninstall

```sh
./uninstall.sh
```

## Notes & caveats

- **Reload after install.** A window's terminals are only focusable once that window's extension has activated. Reload each window once; the extension then covers even already-open terminals (it republishes on activate, terminal open/close, and focus change).
- **Persistent notifications** (permission prompts) only stay on screen if terminal-notifier's notification style is set to **Alerts** (not Banners) in *System Settings → Notifications*.
- **PID resolution** walks the process tree to the shell under VSCode's pty host. It's shell-agnostic (zsh/bash/fish) but may not resolve under tmux, `screen`, or remote-SSH shells.
- **Optional shell snippet** (`shell/recall.zsh`) only adds a clickable link printed in the terminal and a `recall-<id>` tab title — not needed for notifications.

## License

MIT — see [LICENSE](LICENSE).
