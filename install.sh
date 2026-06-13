#!/usr/bin/env bash
# Recall — one-command installer.
#   curl -fsSL https://raw.githubusercontent.com/alielzei/recall/main/install.sh | bash
# or, from a clone:  ./install.sh
#
# Installs the VSCode extension and wires the Claude Code notification hook.
set -euo pipefail

REPO_URL="https://github.com/alielzei/recall.git"
EXT_ID="alielzei.recall"
HOOK_DEST="$HOME/.claude/hooks/recall-notify.sh"
SETTINGS="$HOME/.claude/settings.json"
HOOK_CMD="bash \"$HOME/.claude/hooks/recall-notify.sh\""

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
command -v code >/dev/null || die "the 'code' CLI is not on PATH. In VSCode run: Shell Command: Install 'code' command in PATH."
command -v jq >/dev/null   || die "jq is required. Install it (macOS: brew install jq)."
if ! command -v terminal-notifier >/dev/null; then
  warn "terminal-notifier not found — notifications won't show until you install it:"
  warn "    brew install terminal-notifier"
fi

# --- Build & install the extension ------------------------------------------
say "building the VSCode extension…"
VSIX="$(mktemp -d)/recall.vsix"
( cd "$REPO/extension" && npx --yes @vscode/vsce package --allow-missing-repository -o "$VSIX" >/dev/null )
say "installing the extension…"
code --install-extension "$VSIX" --force >/dev/null

# --- Install the notification hook ------------------------------------------
say "installing the notification hook…"
mkdir -p "$(dirname "$HOOK_DEST")"
cp "$REPO/hooks/notify.sh" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

# --- Merge the Notification hook into settings.json (idempotent) ------------
say "wiring the Claude Code Notification hook…"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
tmp="$(mktemp)"
jq --arg cmd "$HOOK_CMD" '
  .hooks //= {} |
  .hooks.Notification //= [] |
  if any(.hooks.Notification[]?; (.hooks[]?.command) == $cmd)
  then .
  else .hooks.Notification += [ { "hooks": [ { "type": "command", "command": $cmd } ] } ]
  end
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

say "done."
echo
say "Last step: reload each open VSCode window once (Cmd+Shift+P → \"Developer: Reload Window\")"
say "so the extension activates and publishes its window registry."
