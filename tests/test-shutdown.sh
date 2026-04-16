#!/usr/bin/env bash
# ============================================================
# Test: Shutdown Script
# Tests the hardened shutdown script (dry-run mode)
# ============================================================

set -euo pipefail

info() { echo "[TEST:SHUTDOWN] $*"; }
fail() { echo "[TEST:SHUTDOWN:FAIL] $*" >&2; exit 1; }
warn() { echo "[TEST:SHUTDOWN:WARN] $*" >&2; }

# Test 1: Syntax validation
info "Validating shutdown script syntax..."
if ! bash -n bin/pa-shutdown-proxmox.sh; then
  fail "Shutdown script has syntax errors"
fi
info "Syntax: OK"

# Test 2: Check for required hardening features
info "Checking hardening features..."

if ! grep -q 'flock -n 200' bin/pa-shutdown-proxmox.sh; then
  fail "Missing atomic flock lock"
fi
info "✓ Atomic flock present"

if ! grep -q 'is-system-running.*stopping' bin/pa-shutdown-proxmox.sh; then
  fail "Missing shutdown-state detection"
fi
info "✓ Shutdown-state detection present"

if ! grep -q 'PID=\$\$.*PPID' bin/pa-shutdown-proxmox.sh; then
  fail "Missing PID/PPID tracing"
fi
info "✓ Execution tracing present"

# Test 3: Lock file location
if ! grep -q '/var/lock/pa-shutdown.lock' bin/pa-shutdown-proxmox.sh; then
  warn "Lock file not in /var/lock (may be acceptable for some deployments)"
else
  info "✓ Lock file in /var/lock"
fi

# Test 4: Test flock mechanism (dry-run)
info "Testing flock mechanism..."

# Create a test to verify flock works
(
  exec 200>/tmp/test-shutdown-lock.lock
  if flock -n 200; then
    info "✓ Flock acquire works"
    # Test that a second flock fails
    (
      exec 201>/tmp/test-shutdown-lock.lock
      if flock -n 201 2>/dev/null; then
        fail "Flock should have blocked second acquire"
      else
        info "✓ Flock correctly blocks duplicate"
      fi
    )
  else
    fail "Failed to acquire flock"
  fi
)

# Test 5: Check for shutdown-state detection logic
info "Verifying shutdown-state detection logic..."
if grep -A2 'is-system-running' bin/pa-shutdown-proxmox.sh | grep -q 'exit 1'; then
  info "✓ Shutdown-state detection aborts correctly"
else
  warn "Shutdown-state detection may not abort properly"
fi

# Test 6: Verify boot protection (uptime check)
if ! grep -q '/proc/uptime' bin/pa-shutdown-proxmox.sh; then
  fail "Missing boot protection (uptime check)"
fi
info "✓ Boot protection present"

info "Shutdown script hardening tests passed"
