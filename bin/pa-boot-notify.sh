#!/bin/bash

# ============================================================
# pa-boot-notify.sh
# Agent Version: runtime sourced from pa-agent-version
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_FILE="${LIB_FILE:-$SCRIPT_DIR/pa-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="/usr/local/bin/pa-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"

pa_load_version
pa_load_env

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
BOOT_TIME="$(uptime -s 2>/dev/null || echo "unknown")"
LOG_FILE="/var/log/pa-boot-notify.log"
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
LOCK_FILE="/tmp/pa_boot_notify_${BOOT_ID}.lock"

pa_rotate_log_family "$LOG_FILE" "${BOOT_NOTIFY_LOG_RETENTION_DAYS:-}"

if [ -f "$LOCK_FILE" ]; then
  echo "[$TIMESTAMP] INFO duplicate boot notification skipped for $NODE_NAME" >> "$LOG_FILE"
  exit 0
fi

sleep 5

MESSAGE=$(cat <<EOF
<b>Proxmox host $NODE_NAME</b> booted
Time: <b>$TIMESTAMP</b>
Boot time: <b>$BOOT_TIME</b>
Agent: <b>v${AGENT_VERSION:-unknown}</b>
EOF
)

if [ -z "${MESSAGE//[[:space:]]/}" ]; then
  echo "[$TIMESTAMP] ERROR empty boot message blocked for $NODE_NAME" >> "$LOG_FILE"
  exit 0
fi

if /usr/local/bin/pa-send-telegram.sh "$MESSAGE"; then
  touch "$LOCK_FILE"
  echo "[$TIMESTAMP] OK boot notification sent for $NODE_NAME" >> "$LOG_FILE"
else
  echo "[$TIMESTAMP] ERROR failed to send boot notification for $NODE_NAME" >> "$LOG_FILE"
fi
