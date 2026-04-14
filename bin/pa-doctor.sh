#!/bin/bash

set -euo pipefail

if command -v proxmox-agent >/dev/null 2>&1; then
  exec proxmox-agent preinstall-report "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/proxmox-agent" preinstall-report "$@"
