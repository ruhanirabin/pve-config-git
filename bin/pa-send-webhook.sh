#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_FILE="${LIB_FILE:-$SCRIPT_DIR/pa-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="/usr/local/bin/pa-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"
pa_ui_init

pa_load_version
pa_load_env

EVENT="${1:-}"
STATUS="${2:-}"
SUMMARY="${3:-}"
DETAILS="${4:-}"

if [ -z "$EVENT" ]; then
  pa_ui_err "Usage: pa-send-webhook.sh <event> [status] [summary] [details]"
  exit 1
fi

if pa_send_webhook "$EVENT" "${STATUS:-info}" "$SUMMARY" "$DETAILS"; then
  pa_ui_ok "Webhook sent for event: $EVENT"
  exit 0
fi

pa_ui_err "Webhook send failed for event: $EVENT"
exit 1
