#!/usr/bin/env bash
# loop-notify.sh — send the loop pipeline's exit DM to the developer running it.
#
# The loop is autonomous: the only time it needs a human is when its retry budget
# is exhausted. This script is how it asks for help — a bot DM, which unlike a
# self-DM through an MCP connector produces a real Slack notification.
#
# Usage:
#   loop-notify.sh "<message>"   send the DM (mrkdwn: single \n = line break, *bold*)
#   loop-notify.sh --check       validate configuration, resolve the recipient, send nothing
#
# Stdout on success: CH=<channel-id> TS=<message-ts> USER=<recipient-user-id>
#   CH + TS are what the feedback-wait polling needs; USER is the only id whose
#   replies count as the operator's.
# Exit: 0 ok | 1 configuration/resolution error | 2 Slack rejected the send
#
# Configuration — per developer, nothing about the author is baked in:
#   SLACK_LOOP_BOT_TOKEN  required. Bot token of a Slack app you can DM yourself
#                         with. Scopes: chat:write, im:write, im:history
#                         (+ users:read.email if you rely on email resolution).
#   SLACK_LOOP_USER_ID    optional. Your own Slack member ID (Slack profile →
#                         "Copy member ID"). Set it and resolution is instant.
#                         Unset → resolved from `git config user.email`.
set -euo pipefail

MSG="${1:-}"
if [ -z "$MSG" ]; then
  echo "usage: loop-notify.sh \"<message>\" | loop-notify.sh --check" >&2
  exit 1
fi

if [ -z "${SLACK_LOOP_BOT_TOKEN:-}" ]; then
  echo "SLACK_LOOP_BOT_TOKEN is not set — see .agents/skills/loop-run/README.md (Setup)" >&2
  exit 1
fi

for bin in curl jq git; do
  command -v "$bin" >/dev/null || { echo "$bin is required but not installed" >&2; exit 1; }
done

slack_post() { # slack_post <method> <json-body>
  curl -sS -X POST "https://slack.com/api/$1" \
    -H "Authorization: Bearer $SLACK_LOOP_BOT_TOKEN" \
    -H 'Content-type: application/json; charset=utf-8' \
    -d "$2"
}

# --- resolve the recipient: explicit id, else the git identity of this checkout ---
USER_ID="${SLACK_LOOP_USER_ID:-}"
RESOLVED_VIA="SLACK_LOOP_USER_ID"

if [ -z "$USER_ID" ]; then
  RESOLVED_VIA="git user.email"
  EMAIL=$(git config user.email 2>/dev/null || true)
  if [ -z "$EMAIL" ]; then
    echo "cannot resolve the Slack recipient: SLACK_LOOP_USER_ID unset and git user.email empty" >&2
    exit 1
  fi
  LOOKUP=$(curl -sS --get "https://slack.com/api/users.lookupByEmail" \
    --data-urlencode "email=$EMAIL" \
    -H "Authorization: Bearer $SLACK_LOOP_BOT_TOKEN")
  USER_ID=$(echo "$LOOKUP" | jq -r '.user.id // empty')
  if [ -z "$USER_ID" ]; then
    echo "Slack lookup failed for $EMAIL: $(echo "$LOOKUP" | jq -r '.error // "unknown error"')" >&2
    echo "set SLACK_LOOP_USER_ID to your Slack member ID to skip email resolution" >&2
    exit 1
  fi
fi

# --- open the DM channel ---
OPEN=$(slack_post conversations.open "$(jq -n --arg u "$USER_ID" '{users:$u}')")
CH=$(echo "$OPEN" | jq -r '.channel.id // empty')
if [ -z "$CH" ]; then
  echo "conversations.open failed: $(echo "$OPEN" | jq -r '.error // "unknown error"')" >&2
  exit 1
fi

if [ "$MSG" = "--check" ]; then
  echo "ok: recipient $USER_ID (via $RESOLVED_VIA), DM channel $CH — nothing sent"
  exit 0
fi

# --- send ---
SEND=$(slack_post chat.postMessage "$(jq -n --arg ch "$CH" --arg t "$MSG" '{channel:$ch,text:$t}')")
if [ "$(echo "$SEND" | jq -r '.ok')" != "true" ]; then
  echo "chat.postMessage failed: $(echo "$SEND" | jq -r '.error // "unknown error"')" >&2
  exit 2
fi

echo "CH=$CH TS=$(echo "$SEND" | jq -r '.ts') USER=$USER_ID"
