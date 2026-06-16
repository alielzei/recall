#!/usr/bin/env bash
# Recall — session tracker. Claude Code exposes no "list sessions" API, so we
# event-source it: each lifecycle hook updates a per-session state file under
# ~/.recall/sessions/, which the extension's dashboard reads. State is derived from
# the hook event name; the terminal pid is resolved the same way notify.sh does.
input=$(cat)
sid=$(printf '%s' "$input"   | jq -r '.session_id // empty')
[ -n "$sid" ] || exit 0
event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty')
cwd=$(printf '%s' "$input"   | jq -r '.cwd // empty')

DIR="$HOME/.recall/sessions"
mkdir -p "$DIR"
FILE="$DIR/$sid.json"

case "$event" in
  SessionEnd)        rm -f "$FILE"; exit 0 ;;
  UserPromptSubmit)  state="working" ;;
  Stop)              state="idle" ;;
  Notification)      state="waiting" ;;
  SessionStart)      state="idle" ;;
  *)                 exit 0 ;;
esac

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
pid=$(resolve_recall_id)

# Preserve cwd across events that don't carry it.
[ -z "$cwd" ] && [ -f "$FILE" ] && cwd=$(jq -r '.cwd // empty' "$FILE" 2>/dev/null)

ts=$(date +%s)
tmp="$(mktemp)"
jq -n --arg sid "$sid" --arg cwd "$cwd" --arg pid "$pid" --arg state "$state" --argjson ts "$ts" \
  '{session_id:$sid, cwd:$cwd, pid:$pid, state:$state, ts:$ts}' > "$tmp" && mv "$tmp" "$FILE"
exit 0
