#!/usr/bin/env bash
# ============================================================
# Test: Backup Script
# Tests the backup configuration collection
# ============================================================

set -euo pipefail

info() { echo "[TEST:BACKUP] $*"; }
fail() { echo "[TEST:BACKUP:FAIL] $*" >&2; exit 1; }
warn() { echo "[TEST:BACKUP:WARN] $*" >&2; }

# Setup test environment
export REPO_DIR=/tmp/test-pve-config
export REPO_BRANCH=main
export GIT_COMMIT_NAME="Test Backup"
export GIT_COMMIT_EMAIL="test@backup.local"
export BOT_TOKEN=""
export CHAT_ID=""
export PA_LOG_RETENTION_DAYS=7
export BACKUP_LOG_FILE=/tmp/test-backup.log

info "Setting up test git repo at $REPO_DIR..."
rm -rf "$REPO_DIR"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init -b main >/dev/null
git -C "$REPO_DIR" config user.name "Test"
git -C "$REPO_DIR" config user.email "test@test.local"

# Create a fake git remote
export GIT_REMOTE_URL=/tmp/test-backup-remote.git
rm -rf "$GIT_REMOTE_URL"
git init --bare "$GIT_REMOTE_URL" >/dev/null 2>&1

git -C "$REPO_DIR" remote add origin "$GIT_REMOTE_URL" 2>/dev/null || true

info "Testing backup script execution (may fail due to missing PVE files)..."

# The backup script will fail in Docker because there's no real PVE,
# but we can test the script structure and basic flow
if ! bash -n bin/pa-backup-config.sh; then
  fail "Backup script has syntax errors"
fi

info "Backup script syntax: OK"

# Test the backup from outside the repo (it should detect this)
cd /tmp
if ./proxmox-agent/bin/pa-backup-config.sh 2>&1 | grep -q "Backup complete\|No changes"; then
  info "Backup script executed (may have no changes - that's OK in test)"
else
  warn "Backup script may have encountered issues (expected in test environment)"
fi

# Check log file was created
if [[ -f /tmp/test-backup.log ]] || [[ -f /var/log/pa-backup-config.log ]]; then
  info "Backup logging: OK"
else
  warn "No backup log file found"
fi

info "Backup test completed"
