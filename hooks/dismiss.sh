#!/usr/bin/env bash
# Recall — dismiss the macOS notification for a terminal once you re-engage with it
# (a tool runs after a granted permission -> PreToolUse; or you submit a prompt ->
# UserPromptSubmit). Notifications are grouped by the terminal's shell pid, so we
# resolve that pid the same way notify.sh does, then remove that group.
# (The extension also dismisses by pid the instant you focus the terminal.)
input=$(cat)

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
# Background it so this never adds latency to the tool call; no-op if nothing grouped.
[ -n "$recall_id" ] && ( terminal-notifier -remove "$recall_id" >/dev/null 2>&1 & )
exit 0
