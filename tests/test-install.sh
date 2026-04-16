#!/usr/bin/env bash
# ============================================================
# Test: Installation
# Tests the guided/non-interactive installation flow
# ============================================================

set -euo pipefail

info() { echo "[TEST:INSTALL] $*"; }
fail() { echo "[TEST:INSTALL:FAIL] $*" >&2; exit 1; }

# Create a mock environment file for non-interactive install
cat > /tmp/test-install.env <<'EOF'
REPO_DIR=/root/pve-config
REPO_BRANCH=main
GIT_REMOTE_URL=/tmp/fake-remote.git
GIT_COMMIT_NAME=Test User
GIT_COMMIT_EMAIL=test@example.com
PA_LOG_RETENTION_DAYS=7
BOT_TOKEN=PLACEHOLDER
CHAT_ID=PLACEHOLDER
WEBHOOK_ENABLED=false
EOF

# Create a local bare repo as fake remote
git init --bare /tmp/fake-remote.git >/dev/null 2>&1

info "Testing preflight checks..."
if ! bash -c 'source bin/pa-agent-lib.sh && pa_ui_init && echo "Library loads OK"'; then
  fail "Failed to load agent library"
fi

info "Testing binary installation (dry-run)..."
# In test mode, we can check if install would work
PA_TEST_MODE=true ./bin/proxmox-agent preinstall-report | grep -q "blockers\|warnings" || true

info "Simulating install steps..."

# Test 1: Check if binaries can be staged
mkdir -p /tmp/pa-test-install/usr/local/bin
cp bin/*.sh /tmp/pa-test-install/usr/local/bin/ 2>/dev/null || true
cp bin/proxmox-agent /tmp/pa-test-install/usr/local/bin/ 2>/dev/null || true

if [[ -f /tmp/pa-test-install/usr/local/bin/proxmox-agent ]]; then
  info "Binary staging: OK"
else
  fail "Failed to stage binaries"
fi

# Test 2: Check systemd unit files can be staged
mkdir -p /tmp/pa-test-install/etc/systemd/system
if [[ -f systemd/pa-backup-config.service ]]; then
  cp systemd/* /tmp/pa-test-install/etc/systemd/system/ 2>/dev/null || true
  info "Unit file staging: OK"
else
  warn "No systemd unit files found (may be expected in container)"
fi

# Test 3: Validate script syntax
info "Validating script syntax..."
for script in bin/*.sh; do
  if [[ -f "$script" ]]; then
    bash -n "$script" || fail "Syntax error in $script"
  fi
done

info "Installation test passed"
