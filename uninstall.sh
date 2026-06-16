#!/usr/bin/env bash
# Recall — uninstaller. Reverses install.sh.
set -euo pipefail

EXT_ID="alielzei.recall"
NOTIFY_DEST="$HOME/.claude/hooks/recall-notify.sh"
DISMISS_DEST="$HOME/.claude/hooks/recall-dismiss.sh"
SESSION_DEST="$HOME/.claude/hooks/recall-session.sh"
SETTINGS="$HOME/.claude/settings.json"
NOTIFY_CMD="bash \"$HOME/.claude/hooks/recall-notify.sh\""
DISMISS_CMD="bash \"$HOME/.claude/hooks/recall-dismiss.sh\""
SESSION_CMD="bash \"$HOME/.claude/hooks/recall-session.sh\""

say() { printf '\033[1;36mrecall\033[0m %s\n' "$*"; }

if command -v code >/dev/null; then
  say "uninstalling the extension…"
  code --uninstall-extension "$EXT_ID" >/dev/null 2>&1 || true
fi

say "removing the hook scripts…"
rm -f "$NOTIFY_DEST" "$DISMISS_DEST" "$SESSION_DEST"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  say "removing the hooks from settings.json…"
  remove_hook() {  # $1=event  $2=command
    local tmp; tmp="$(mktemp)"
    jq --arg ev "$1" --arg cmd "$2" '
      if .hooks[$ev] then
        .hooks[$ev] |= map(select( ((.hooks // []) | any(.command == $cmd)) | not ))
        | (if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end)
      else . end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  }
  remove_hook Notification     "$NOTIFY_CMD"
  remove_hook PreToolUse       "$DISMISS_CMD"
  remove_hook UserPromptSubmit "$DISMISS_CMD"
  for ev in SessionStart SessionEnd UserPromptSubmit Stop Notification; do
    remove_hook "$ev" "$SESSION_CMD"
  done
fi

say "removing the notifier helper…"
rm -rf "$HOME/Applications/RecallNotifier.app"

say "removing the registry (~/.recall)…"
rm -rf "$HOME/.recall"

say "done. Reload your VSCode windows to fully unload the extension."
