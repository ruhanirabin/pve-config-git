#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT_DIR/tests/test-backup-startup.sh"
bash "$ROOT_DIR/tests/test-reliability.sh"
bash "$ROOT_DIR/tests/test-git-access.sh"
