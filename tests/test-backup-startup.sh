#!/bin/bash
# Isolated startup regression: no host config collection or network access.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
export PCG_TEST_LIB="$ROOT_DIR/bin/pcg-agent-lib.sh"
cat > "$TEST_DIR/lib.sh" <<'LIB'
source "$PCG_TEST_LIB"
pcg_load_version() { AGENT_VERSION=test; }
pcg_load_env() { :; }
pcg_send_webhook() { :; }
LIB
mkdir -p "$TEST_DIR/repo"
# The in-repo guard safely stops execution after real log initialization.
set +e
(cd "$TEST_DIR/repo" && LIB_FILE="$TEST_DIR/lib.sh" REPO_DIR="$TEST_DIR/repo" \
  BACKUP_LOG_FILE="$TEST_DIR/logs/backup.log" \
  bash "$ROOT_DIR/bin/pcg-backup-config.sh") > "$TEST_DIR/output" 2>&1
rc=$?
set -e
[[ "$rc" -eq 1 ]] || { cat "$TEST_DIR/output"; exit 1; }
grep -q 'Do not run this script from inside the git repo folder' "$TEST_DIR/output"
[[ -f "$TEST_DIR/logs/backup.log" ]]
! grep -q 'command not found' "$TEST_DIR/output"
set +e
LIB_FILE="$TEST_DIR/lib.sh" bash "$ROOT_DIR/bin/pcg-send-webhook.sh" > "$TEST_DIR/webhook" 2>&1
rc=$?
set -e
[[ "$rc" -eq 1 ]]
grep -q 'Usage: pcg-send-webhook.sh' "$TEST_DIR/webhook"
! grep -q 'command not found' "$TEST_DIR/webhook"
echo 'Backup startup and webhook usage regressions: PASS'
