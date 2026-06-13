#!/usr/bin/env bash
# Recall — uninstaller. Reverses install.sh.
set -euo pipefail

EXT_ID="alielzei.recall"
HOOK_DEST="$HOME/.claude/hooks/recall-notify.sh"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="bash \"$HOME/.claude/hooks/recall-notify.sh\""

say() { printf '\033[1;36mrecall\033[0m %s\n' "$*"; }

if command -v code >/dev/null; then
  say "uninstalling the extension…"
  code --uninstall-extension "$EXT_ID" >/dev/null 2>&1 || true
fi

say "removing the notification hook…"
rm -f "$HOOK_DEST"

if [ -f "$SETTINGS" ] && command -v jq >/dev/null; then
  say "removing the Notification hook from settings.json…"
  tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    if .hooks.Notification then
      .hooks.Notification |= map(select( ((.hooks // []) | any(.command == $cmd)) | not ))
      | (if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end)
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
fi

say "removing the registry (~/.recall)…"
rm -rf "$HOME/.recall"

say "done. Reload your VSCode windows to fully unload the extension."
