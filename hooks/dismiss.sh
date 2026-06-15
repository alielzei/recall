#!/usr/bin/env bash
# Recall — dismiss the macOS notification for a session once you re-engage with it
# (a tool runs after a granted permission -> PreToolUse; or you submit a prompt ->
# UserPromptSubmit). There is no "permission answered" hook event, so this infers
# resolution from re-engagement and clears the now-stale notification by session id.
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
# Background it so this never adds latency to the tool call; no-op if nothing grouped.
[ -n "$sid" ] && ( terminal-notifier -remove "$sid" >/dev/null 2>&1 & )
exit 0
