#!/bin/bash

# ============================================================
# pcg-send-telegram.sh
# Agent Version: runtime sourced from pcg-agent-version
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_FILE="${LIB_FILE:-$SCRIPT_DIR/pcg-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="/usr/local/bin/pcg-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"

pcg_load_version
pcg_load_env

LOG_FILE="${TELEGRAM_LOG_FILE:-/var/log/pcg-send-telegram.log}"
TIMEOUT="${TELEGRAM_TIMEOUT_SECONDS:-10}"
RETRIES="${TELEGRAM_MAX_RETRIES:-2}"
MESSAGE="${1:-}"

pcg_rotate_log_family "$LOG_FILE" "${TELEGRAM_LOG_RETENTION_DAYS:-}"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
log() { echo "[$(timestamp)] $*" >> "$LOG_FILE"; }

BOT_TOKEN="${BOT_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}"
CHAT_ID="${CHAT_ID:-${TELEGRAM_CHAT_ID:-}}"

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  log "ERROR missing BOT_TOKEN/CHAT_ID (agent v${AGENT_VERSION:-unknown})"
  exit 1
fi

if [ -z "$MESSAGE" ] || [[ "$MESSAGE" =~ ^[[:space:]]*$ ]]; then
  log "ERROR empty message blocked"
  exit 1
fi

API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
response="$(curl -s --max-time "$TIMEOUT" --retry "$RETRIES" --retry-delay 2 \
  -X POST "$API_URL" \
  -d chat_id="$CHAT_ID" \
  -d text="$MESSAGE" \
  -d parse_mode="HTML" || true)"

if echo "$response" | grep -q '"ok":true'; then
  log "OK telegram sent (len=${#MESSAGE}) agent=v${AGENT_VERSION:-unknown}"
  exit 0
fi

log "ERROR telegram failed response=$response"
exit 1
