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
if ! bash -n bin/pcg-shutdown-proxmox.sh; then
  fail "Shutdown script has syntax errors"
fi
info "Syntax: OK"

# Test 2: Check for required hardening features
info "Checking hardening features..."

if ! grep -q 'flock -n 200' bin/pcg-shutdown-proxmox.sh; then
  fail "Missing atomic flock lock"
fi
info "✓ Atomic flock present"

if ! grep -q 'system_state.*stopping' bin/pcg-shutdown-proxmox.sh; then
  fail "Missing shutdown-state detection"
fi
info "✓ Shutdown-state detection present"

if ! grep -q 'PID=\$\$.*PPID' bin/pcg-shutdown-proxmox.sh; then
  fail "Missing PID/PPID tracing"
fi
info "✓ Execution tracing present"

# Test 3: Lock file location
if ! grep -q '/var/lock/pcg-shutdown.lock' bin/pcg-shutdown-proxmox.sh; then
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

# Test 5: Runtime guards and guest continuation are covered by the isolated
# test-shutdown-behavior.sh suite, rather than a source-text assertion.

# Test 6: Verify boot protection (uptime check)
if ! grep -q '/proc/uptime' bin/pcg-shutdown-proxmox.sh; then
  fail "Missing boot protection (uptime check)"
fi
info "✓ Boot protection present"

info "Shutdown script hardening tests passed"
