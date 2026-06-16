#!/usr/bin/env bash
# Recall — one-command installer.
#   curl -fsSL https://raw.githubusercontent.com/alielzei/recall/main/install.sh | bash
# or, from a clone:  ./install.sh
#
# Installs the VSCode extension and wires the Claude Code notification hook.
set -euo pipefail

REPO_URL="https://github.com/alielzei/recall.git"
EXT_ID="alielzei.recall"
NOTIFY_DEST="$HOME/.claude/hooks/recall-notify.sh"
DISMISS_DEST="$HOME/.claude/hooks/recall-dismiss.sh"
SETTINGS="$HOME/.claude/settings.json"
NOTIFY_CMD="bash \"$HOME/.claude/hooks/recall-notify.sh\""
DISMISS_CMD="bash \"$HOME/.claude/hooks/recall-dismiss.sh\""

say() { printf '\033[1;36mrecall\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mrecall\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mrecall\033[0m %s\n' "$*" >&2; exit 1; }

# --- Locate sources (run from a clone, or self-clone when piped) -------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/extension/package.json" ]; then
  REPO="$SCRIPT_DIR"
else
  command -v git >/dev/null || die "git is required to bootstrap. Install git or clone the repo."
  REPO="$(mktemp -d)/recall"
  say "fetching sources…"
  git clone --depth 1 "$REPO_URL" "$REPO" >/dev/null 2>&1 || die "git clone failed."
fi

# --- Dependency checks -------------------------------------------------------
command -v code >/dev/null   || die "the 'code' CLI is not on PATH. In VSCode run: Shell Command: Install 'code' command in PATH."
command -v jq >/dev/null     || die "jq is required (macOS: brew install jq)."
command -v swiftc >/dev/null || die "swiftc is required to build the notifier. Install Xcode Command Line Tools: xcode-select --install"

# --- Build & install the extension ------------------------------------------
say "building the VSCode extension…"
VSIX="$(mktemp -d)/recall.vsix"
( cd "$REPO/extension" && npx --yes @vscode/vsce package --allow-missing-repository -o "$VSIX" >/dev/null )
say "installing the extension…"
code --install-extension "$VSIX" --force >/dev/null

# --- Install the hooks ------------------------------------------------------
say "installing the notification hooks…"
mkdir -p "$(dirname "$NOTIFY_DEST")"
cp "$REPO/hooks/notify.sh"  "$NOTIFY_DEST"  && chmod +x "$NOTIFY_DEST"
cp "$REPO/hooks/dismiss.sh" "$DISMISS_DEST" && chmod +x "$DISMISS_DEST"

# --- Build & install the notifier helper ------------------------------------
# A small signed UNUserNotificationCenter app. terminal-notifier's legacy click
# handling is dead on current macOS; this delivers native, clickable, persistent
# notifications. It MUST live in a stable location (~/Applications) or macOS refuses
# notification authorization.
say "building the notifier helper…"
NOTIFIER_APP="$HOME/Applications/RecallNotifier.app"
mkdir -p "$HOME/Applications"
bash "$REPO/notifier/build.sh" "$HOME/Applications" >/dev/null
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$NOTIFIER_APP" 2>/dev/null || true
mkdir -p "$HOME/.recall"
printf '{\n  "notifierApp": "%s"\n}\n' "$NOTIFIER_APP" > "$HOME/.recall/config.json"
# Trigger the one-time notification-permission prompt with a welcome notification.
say "requesting notification permission (click Allow if macOS prompts)…"
open -n "$NOTIFIER_APP" --args post --title "Recall" \
  --message "Notifications enabled — click one to jump to its terminal." --id recall-welcome 2>/dev/null || true

# --- Merge hooks into settings.json (idempotent) ----------------------------
say "wiring the Claude Code hooks…"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

add_hook() {  # $1=event  $2=command  — append once; no-op if already present
  local tmp; tmp="$(mktemp)"
  jq --arg ev "$1" --arg cmd "$2" '
    .hooks //= {} |
    .hooks[$ev] //= [] |
    if any(.hooks[$ev][]?; (.hooks[]?.command) == $cmd)
    then .
    else .hooks[$ev] += [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
    end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

remove_hook() {  # $1=event $2=command — drop matching entries (for migrations)
  local tmp; tmp="$(mktemp)"
  jq --arg ev "$1" --arg cmd "$2" '
    if .hooks[$ev] then
      .hooks[$ev] |= map(select( ((.hooks // []) | any(.command == $cmd)) | not ))
      | (if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end)
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

add_hook Notification     "$NOTIFY_CMD"    # fire the notification
add_hook UserPromptSubmit "$DISMISS_CMD"   # you came back and typed -> clear it
# Focus-dismiss is handled in-extension on terminal focus. PreToolUse fires on every
# tool call (too often), so drop it if an older install added it.
remove_hook PreToolUse    "$DISMISS_CMD"

say "done."
echo
say "Last step: reload each open VSCode window once (Cmd+Shift+P → \"Developer: Reload Window\")"
say "so the extension activates and publishes its window registry."
