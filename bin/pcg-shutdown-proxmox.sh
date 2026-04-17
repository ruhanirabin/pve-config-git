#!/bin/bash

# ============================================================
# pcg-shutdown-proxmox.sh
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

NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
LOG_DIR="/var/log/pcg-shutdown"
LOG_FILE="$LOG_DIR/shutdown_$(date '+%Y-%m-%d').log"
pcg_rotate_log_family "$LOG_FILE" "${SHUTDOWN_LOG_RETENTION_DAYS:-7}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1" >> "$LOG_FILE"
}

# ============================================================
# Atomic Lock (flock) - Prevents duplicate execution
# ============================================================

LOCK_FILE="/var/lock/pcg-shutdown.lock"
exec 200>"$LOCK_FILE"

flock -n 200 || {
  log "Abort: another shutdown instance already running"
  exit 1
}

# ============================================================
# Execution guard: allow systemd invocation, or explicit SSH-triggered --execute
# ============================================================

EXECUTE_FLAG=0
for arg in "$@"; do
  if [ "$arg" = "--execute" ]; then
    EXECUTE_FLAG=1
  fi
done

if [ -n "${INVOCATION_ID:-}" ]; then
  CALLER="systemd"
elif [ "$EXECUTE_FLAG" -eq 1 ]; then
  CALLER="ssh"
else
  CALLER="unknown"
fi

log "EXECUTION START PID=$$ PPID=$PPID CALLER=$CALLER ARGS=$*"

if [ "$CALLER" = "unknown" ]; then
  log "Abort: not systemd and missing --execute flag"
  exit 1
fi

# ============================================================
# Shutdown-state detection (critical) - Prevents re-entry during shutdown
# ============================================================

if systemctl is-system-running 2>/dev/null | grep -q "stopping"; then
  log "Abort: system already in stopping state"
  exit 1
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
if [ "$uptime_secs" -lt 300 ]; then
  log "Skipping shutdown: booted recently ($uptime_secs sec) agent=v${AGENT_VERSION:-unknown}"
  logger "Proxmox shutdown skipped: $NODE_NAME booted recently"
  exit 0
fi

START_TS="$(date '+%Y-%m-%d %H:%M:%S %Z')"
log "==== $NODE_NAME shutdown started at $START_TS via $CALLER (agent v${AGENT_VERSION:-unknown}) ===="
logger "Proxmox $NODE_NAME shutdown initiated via $CALLER"

/usr/local/bin/pcg-send-telegram.sh "Proxmox $NODE_NAME shutdown started at <b>$START_TS</b> (agent v${AGENT_VERSION:-unknown})" || true
pcg_send_webhook "shutdown" "started" "Shutdown sequence started" "Node $NODE_NAME started graceful shutdown." || true

if /usr/local/bin/pcg-backup-config.sh; then
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

/usr/local/bin/pcg-send-telegram.sh "Proxmox host <b>$NODE_NAME</b> shutting down at <b>$FINAL_TS</b> (agent v${AGENT_VERSION:-unknown})" || true
pcg_send_webhook "shutdown" "success" "Shutdown sequence complete" "Node $NODE_NAME is shutting down now." || true

sleep 3

log "Shutting down host now"
logger "Proxmox $NODE_NAME shutting down"

/sbin/shutdown -h now
