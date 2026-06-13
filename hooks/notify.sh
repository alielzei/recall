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

# Classify: does this actually need my input, or is it just attention?
#   permission -> sound + persistent (stays until dismissed)
#   your turn  -> silent  + auto-dismiss after a few seconds
#   attention  -> sound   + auto-dismiss after a few seconds
case "$msg" in
  *permission*|*approve*|*Approve*)        kind="🔐 Permission needed"; sound="Morse"; timeout="" ;;
  *waiting*|*input*|*Waiting*)             kind="💬 Your turn";          sound="";      timeout="8" ;;
  *)                                       kind="🔔 Attention";          sound="Morse"; timeout="8" ;;
esac

args=(-title "$kind · $folder" -subtitle "$title" -message "$msg")
[ -n "$sound" ] && args+=(-sound "$sound")
# Click the notification -> focus the exact VSCode terminal it came from.
[ -n "$recall_link" ] && args+=(-open "$recall_link")

if [ -n "$timeout" ]; then
  # Auto-dismiss: -timeout keeps terminal-notifier alive to close it, so background it.
  ( terminal-notifier "${args[@]}" -timeout "$timeout" >/dev/null 2>&1 ) &
else
  # Persistent: no timeout, stays until dismissed (requires Alerts style — see README).
  terminal-notifier "${args[@]}" 2>/dev/null || true
fi
