#!/bin/bash

set -euo pipefail

if command -v pcg >/dev/null 2>&1; then
  exec pcg preinstall-report "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/pcg" preinstall-report "$@"
