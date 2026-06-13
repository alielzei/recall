#!/usr/bin/env bash
# Recall — Claude Code Notification hook -> terminal-notifier.
# Shows notification kind, folder, AI session title, and the message. Clicking the
# notification opens a vscode:// link that focuses the exact terminal it came from,
# in the correct window.

input=$(cat)

msg=$(printf '%s' "$input"  | jq -r '.message // "Claude needs your attention"')
cwd=$(printf '%s' "$input"  | jq -r '.cwd // empty')
tpath=$(printf '%s' "$input" | jq -r '.transcript_path // .transcriptPath // empty')

# Folder name (fall back to the hook's own cwd)
folder=$(basename "${cwd:-$PWD}")

# Session title = latest ai-title entry in the transcript; fall back to folder
title=""
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  title=$(grep '"type":"ai-title"' "$tpath" 2>/dev/null | tail -1 \
          | jq -r '.aiTitle // empty' 2>/dev/null)
fi
[ -z "$title" ] && title="$folder"

# Resolve the VSCode terminal's shell PID (the deep-link id).
# Fast path: RECALL_ID exported by the optional shell snippet (== this terminal's $$).
# Fallback: walk up our own process tree to the shell whose parent is VSCode.
resolve_recall_id() {
  if [ -n "$RECALL_ID" ]; then printf '%s' "$RECALL_ID"; return; fi
  local pid=$$ ppid pcomm parent_comm
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$ppid" ] && break; [ "$ppid" -le 1 ] && break
    pcomm=$(ps -o comm= -p "$pid" 2>/dev/null)
    parent_comm=$(ps -o comm= -p "$ppid" 2>/dev/null)
    case "$pcomm" in
      *zsh|*bash|*fish|*/sh|sh)
        case "$parent_comm" in
          *"Code Helper"*|*"Code - Insiders Helper"*|*"Visual Studio Code"*)
            printf '%s' "$pid"; return ;;
        esac ;;
    esac
    pid=$ppid
  done
}
recall_id=$(resolve_recall_id)

# Build the focus link. The windowId is REQUIRED for cross-window routing, and only
# the extension knows it -> look it up in the per-window registry it publishes
# (keyed by terminal pid). Skip files whose owning window (ext-host pid == filename)
# is dead, and on a pid match prefer the freshest entry. Plain link as last resort.
recall_link=""
if [ -n "$recall_id" ]; then
  best_ts=-1
  for f in "$HOME"/.recall/windows/*.json; do
    [ -e "$f" ] || continue
    exthost=$(basename "$f" .json)
    kill -0 "$exthost" 2>/dev/null || continue   # dead window -> stale, skip
    url=$(jq -r --arg id "$recall_id" '.terminals[$id] // empty' "$f" 2>/dev/null)
    [ -n "$url" ] || continue
    ts=$(jq -r '.ts // 0' "$f" 2>/dev/null)
    if [ "$ts" -gt "$best_ts" ] 2>/dev/null; then best_ts="$ts"; recall_link="$url"; fi
  done
  [ -z "$recall_link" ] && recall_link="vscode://alielzei.recall/focus?id=${recall_id}"
fi

# Classify the message (for the title + sound).
case "$msg" in
  *permission*|*approve*|*Approve*)        kind="🔐 Permission needed"; sound="Morse" ;;
  *waiting*|*input*|*Waiting*)             kind="💬 Your turn";          sound="" ;;
  *)                                       kind="🔔 Attention";          sound="Morse" ;;
esac

# When we have a link, tell the user the notification is clickable.
click_hint=""
[ -n "$recall_link" ] && click_hint=" — 👆 CLICK TO OPEN TERMINAL"

args=(-title "$kind · $folder" -subtitle "$title" -message "${msg}${click_hint}")
[ -n "$sound" ] && args+=(-sound "$sound")
# Click the notification -> focus the exact VSCode terminal it came from.
[ -n "$recall_link" ] && args+=(-open "$recall_link")

# NOTE: we intentionally do NOT pass -timeout. terminal-notifier's -timeout *removes*
# the notification when it fires, which also clears it from Notification Center.
# Omitting it parks every notification in Notification Center until you click or
# dismiss it, so you can go back to ones you missed. On-screen dwell is then governed
# by the macOS notification style for terminal-notifier
# (System Settings > Notifications > terminal-notifier): "Banners" auto-hide from the
# screen but stay in the Center; "Alerts" stay on screen until dismissed.
terminal-notifier "${args[@]}" 2>/dev/null || true
