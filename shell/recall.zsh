# Recall — OPTIONAL shell snippet (zsh).
# Not required: the notification hook resolves the terminal PID on its own and the
# extension supplies the windowId. This only adds a clickable link printed in the
# terminal + a "recall-<id>" tab title.
#
# Install: add `source /path/to/recall.zsh` to your ~/.zshrc.

if [[ "$TERM_PROGRAM" == "vscode" ]]; then
  export RECALL_ID="$$"
  # NOTE: this printed link has no windowId, so it only focuses within the CURRENT
  # window. Cross-window focus is handled by the notification hook (which looks the
  # windowId up in the registry the extension publishes).
  recall_link="vscode://alielzei.recall/focus?id=${RECALL_ID}"

  # Stamp the tab title so it's human-identifiable (also feeds the extension's
  # name-based fallback).
  _recall_settitle() { printf '\e]0;recall-%s\a' "$RECALL_ID"; }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _recall_settitle
  _recall_settitle

  # Print a clickable link (OSC 8 hyperlink) once at shell start.
  printf '\e]8;;%s\e\\→ focus this terminal\e]8;;\e\\  (%s)\n' \
    "$recall_link" "$recall_link"
fi
