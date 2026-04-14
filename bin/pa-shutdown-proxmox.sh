#!/bin/bash

# ============================================================
# pa-shutdown-proxmox.sh
# Agent Version: runtime sourced from pa-agent-version
# ============================================================

set -euo pipefail

LIB_FILE="${LIB_FILE:-/usr/local/bin/pa-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="$(cd "$(dirname "$0")" && pwd)/pa-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"

pa_load_version
pa_load_env

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG_DIR="/var/log/pa-shutdown"
LOG_FILE="$LOG_DIR/shutdown_$(date '+%Y-%m-%d').log"
pa_rotate_log_family "$LOG_FILE" "${SHUTDOWN_LOG_RETENTION_DAYS:-}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" >> "$LOG_FILE"
}

# Safety guard: only run from systemd unit with explicit execute flag.
if [ "${1:-}" != "--execute" ]; then
  log "Abort: missing required --execute flag"
  exit 0
fi

if [ -z "${INVOCATION_ID:-}" ]; then
  log "Abort: script not invoked by systemd"
  exit 0
fi

wait_for_shutdown() {
  local TYPE="$1"
  local ID="$2"
  local TIMEOUT=120
  local INTERVAL=5
  local ELAPSED=0
  local STATUS

  while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    if [ "$TYPE" = "vm" ]; then
      STATUS="$(qm status "$ID" 2>/dev/null | awk '{print $2}')"
    else
      STATUS="$(pct status "$ID" 2>/dev/null | awk '{print $2}')"
    fi

    if [ "$STATUS" != "running" ]; then
      log "$TYPE $ID stopped successfully"
      return 0
    fi

    sleep "$INTERVAL"
    ELAPSED=$((ELAPSED + INTERVAL))
  done

  log "WARNING $TYPE $ID did not stop, forcing stop"
  if [ "$TYPE" = "vm" ]; then
    qm stop "$ID" >> "$LOG_FILE" 2>&1 || true
  else
    pct stop "$ID" >> "$LOG_FILE" 2>&1 || true
  fi
  return 1
}

uptime_secs="$(cut -d. -f1 /proc/uptime)"
if [ "$uptime_secs" -lt 900 ]; then
  log "Skipping shutdown: booted recently ($uptime_secs sec) agent=v${AGENT_VERSION:-unknown}"
  logger "Proxmox shutdown skipped: $NODE_NAME booted recently"
  exit 0
fi

START_TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"
log "==== $NODE_NAME shutdown started at $START_TS (agent v${AGENT_VERSION:-unknown}) ===="
log "Invocation ID: ${INVOCATION_ID}"
logger "Proxmox $NODE_NAME shutdown initiated"

/usr/local/bin/pa-send-telegram.sh "Proxmox $NODE_NAME shutdown started at <b>$START_TS</b> (agent v${AGENT_VERSION:-unknown})" || true
pa_send_webhook "shutdown" "started" "Shutdown sequence started" "Node $NODE_NAME started graceful shutdown." || true

if /usr/local/bin/pa-backup-config.sh; then
  log "Pre-shutdown backup completed."
else
  log "WARNING pre-shutdown backup failed; continuing shutdown."
fi

log "Shutting down VMs..."
for vmid in $(qm list | awk 'NR>1 {print $1}'); do
  STATUS="$(qm status "$vmid" 2>/dev/null | awk '{print $2}')"
  if [ "$STATUS" = "running" ]; then
    log "Shutting down VM $vmid"
    qm shutdown "$vmid" --timeout 90 >> "$LOG_FILE" 2>&1 || true
    wait_for_shutdown "vm" "$vmid"
  else
    log "VM $vmid already stopped"
  fi
done

log "Shutting down LXCs..."
for lxcid in $(pct list | awk 'NR>1 {print $1}'); do
  STATUS="$(pct status "$lxcid" 2>/dev/null | awk '{print $2}')"
  if [ "$STATUS" = "running" ]; then
    log "Shutting down LXC $lxcid"
    pct shutdown "$lxcid" >> "$LOG_FILE" 2>&1 || true
    wait_for_shutdown "lxc" "$lxcid"
  else
    log "LXC $lxcid already stopped"
  fi
done

FINAL_TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"
log "Sending final shutdown notification"

/usr/local/bin/pa-send-telegram.sh "Proxmox host <b>$NODE_NAME</b> shutting down at <b>$FINAL_TS</b> (agent v${AGENT_VERSION:-unknown})" || true
pa_send_webhook "shutdown" "success" "Shutdown sequence complete" "Node $NODE_NAME is shutting down now." || true

sleep 3

log "Shutting down host now"
logger "Proxmox $NODE_NAME shutting down"

/sbin/shutdown -h now
