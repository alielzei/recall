# Recall (VSCode extension)

Resolves `vscode://alielzei.recall/focus?id=<pid>&windowId=<N>` links to the matching
integrated terminal and focuses it — routing to the correct window via `windowId`.

It also publishes a per-window registry to `~/.recall/windows/<extHostPid>.json`
mapping each terminal's shell PID to its windowId-tagged URL, which the Recall
notification hook reads to build a link that points at the exact terminal.

This is the VSCode half of [Recall](https://github.com/alielzei/recall). See the repo
root for the full setup (the notification hook + one-command installer).

## Command
- **Recall: Copy focus link for active terminal** — copies a focus link for the
  active terminal to the clipboard.
