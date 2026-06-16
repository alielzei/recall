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

# Post via RecallNotifier.app — a signed helper using the modern UserNotifications
# framework. terminal-notifier's legacy NSUserNotification click handling is dead on
# current macOS; this delivers real, clickable, persistent notifications. The helper
# must run from a stable location (~/Applications) or macOS refuses notification auth.
# Identifier = terminal pid, so a newer notification replaces the older one and the
# dismiss paths (hook + extension on focus) can clear it by pid.
APP="$HOME/Applications/RecallNotifier.app"
post_args=(post --title "$kind · $folder" --subtitle "$title" --message "${msg}${click_hint}")
[ -n "$recall_link" ] && post_args+=(--url "$recall_link")
[ -n "$recall_id" ]   && post_args+=(--id "$recall_id")
[ -n "$sound" ]       && post_args+=(--sound)

if [ -d "$APP" ]; then
  open -n "$APP" --args "${post_args[@]}"
elif command -v terminal-notifier >/dev/null; then
  # Fallback (display only; click won't work on current macOS).
  tn=(-title "$kind · $folder" -subtitle "$title" -message "${msg}${click_hint}")
  [ -n "$sound" ] && tn+=(-sound "Morse")
  terminal-notifier "${tn[@]}" 2>/dev/null || true
fi
