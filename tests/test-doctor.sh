#!/usr/bin/env bash
# ============================================================
# Test: Doctor / Preinstall Report
# Tests the health check and pre-install simulation
# ============================================================

set -euo pipefail

info() { echo "[TEST:DOCTOR] $*"; }
fail() { echo "[TEST:DOCTOR:FAIL] $*" >&2; exit 1; }

info "Running doctor preinstall-report..."

if ! ./bin/proxmox-agent preinstall-report >/tmp/doctor-output.txt 2>&1; then
  # Preinstall-report may fail due to missing remote URL, which is expected
  info "Preinstall-report completed (may show blockers - that's OK)"
fi

# Check output has expected sections
if ! grep -q "install_state" /tmp/doctor-output.txt; then
  fail "Missing install_state in output"
fi

if ! grep -q "planned_actions" /tmp/doctor-output.txt; then
  fail "Missing planned_actions in output"
fi

# Check JSON output works
info "Testing JSON output..."
if ! ./bin/proxmox-agent preinstall-report --json >/tmp/doctor-json.txt 2>&1; then
  info "JSON report completed (may show blockers)"
fi

if ! grep -q '"install_state"' /tmp/doctor-json.txt; then
  fail "JSON output missing install_state field"
fi

info "Doctor tests passed"
