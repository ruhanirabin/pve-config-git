#!/usr/bin/env bash
# ============================================================
# Proxmox Agent Test Runner
# Automated testing using Proxmox VE Docker environment
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Cleanup function
cleanup() {
  if [[ "${PA_TEST_KEEP:-false}" != "true" ]]; then
    info "Cleaning up test environment..."
    docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
  else
    info "Keeping test environment (PA_TEST_KEEP=true)"
    info "Access PVE at: ssh root@localhost -p 2222 (password: testpass123)"
    info "Proxmox UI: https://localhost:8006"
  fi
}

trap cleanup EXIT

# Check dependencies
check_deps() {
  local missing=()
  for cmd in docker docker-compose; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing dependencies: ${missing[*]}"
    error "Please install Docker and Docker Compose"
    exit 1
  fi
}

# Wait for container health
wait_for_healthy() {
  local service="$1"
  local max_wait="${2:-120}"
  local elapsed=0
  
  info "Waiting for $service to be healthy (max ${max_wait}s)..."
  
  while [[ $elapsed -lt $max_wait ]]; do
    local status
    status=$(docker-compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null | \
      xargs docker inspect -f '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    
    if [[ "$status" == "healthy" ]]; then
      info "$service is healthy"
      return 0
    fi
    
    sleep 5
    elapsed=$((elapsed + 5))
    echo -n "."
  done
  
  error "Timeout waiting for $service"
  docker-compose -f "$COMPOSE_FILE" logs "$service" --tail 50
  return 1
}

# Copy agent code into container
copy_agent_to_container() {
  info "Copying agent code to test container..."
  
  # Create a tar archive of the agent code
  local tar_file
  tar_file=$(mktemp)
  
  (cd "$ROOT_DIR" && tar -czf "$tar_file" --exclude='.git' --exclude='tests' .)
  
  # Copy and extract in container
  docker-compose -f "$COMPOSE_FILE" cp "$tar_file" pve-test:/tmp/agent.tar.gz
  docker-compose -f "$COMPOSE_FILE" exec -T pve-test bash -c '
    mkdir -p /proxmox-agent &&
    cd /proxmox-agent &&
    tar -xzf /tmp/agent.tar.gz &&
    rm /tmp/agent.tar.gz &&
    chmod +x bin/*.sh install.sh
  '
  
  rm -f "$tar_file"
  info "Agent code copied successfully"
}

# Run a test inside the container
run_test_in_container() {
  local test_name="$1"
  local test_script="$2"
  
  info "Running test: $test_name"
  
  if docker-compose -f "$COMPOSE_FILE" exec -T pve-test bash -c "
    cd /proxmox-agent &&
    export PA_TEST_MODE=true &&
    export GIT_REMOTE_URL='ssh://git@git-test/srv/git/pve-config.git' &&
    export PA_LOG_RETENTION_DAYS=7 &&
    $test_script
  "; then
    info "✓ Test passed: $test_name"
    return 0
  else
    error "✗ Test failed: $test_name"
    return 1
  fi
}

# Main test execution
main() {
  info "Proxmox Agent Test Runner"
  info "=========================="
  
  check_deps
  
  # Start the test environment
  info "Starting test environment..."
  docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
  docker-compose -f "$COMPOSE_FILE" up -d
  
  # Wait for PVE to be ready
  wait_for_healthy pve-test
  
  # Copy agent code
  copy_agent_to_container
  
  # Run tests
  local failed=0
  
  # Test 1: Doctor (pre-install check)
  if ! run_test_in_container "Doctor Pre-Install" "bash tests/test-doctor.sh"; then
    ((failed++)) || true
  fi
  
  # Test 2: Installation
  if ! run_test_in_container "Installation" "bash tests/test-install.sh"; then
    ((failed++)) || true
  fi
  
  # Test 3: Post-install doctor
  if ! run_test_in_container "Doctor Post-Install" "bash tests/test-doctor.sh"; then
    ((failed++)) || true
  fi
  
  # Test 4: Backup dry-run
  if ! run_test_in_container "Backup Dry-Run" "bash tests/test-backup.sh"; then
    ((failed++)) || true
  fi
  
  # Test 5: Shutdown script (dry-run)
  if ! run_test_in_container "Shutdown Dry-Run" "bash tests/test-shutdown.sh"; then
    ((failed++)) || true
  fi
  
  # Summary
  info "=========================="
  if [[ $failed -eq 0 ]]; then
    info "All tests passed!"
    exit 0
  else
    error "$failed test(s) failed"
    exit 1
  fi
}

# Handle arguments
case "${1:-}" in
  --help|-h)
    cat <<'EOF'
Usage: run-tests.sh [OPTIONS]

Run automated tests for Proxmox Agent using PVE Docker environment.

Options:
  --help, -h      Show this help message
  --keep          Keep test environment running after tests
  --shell         Start a shell in the test container

Environment Variables:
  PA_TEST_KEEP=true    Keep containers running after tests
  PA_TEST_IMAGE        Override the PVE image to use

Examples:
  # Run all tests
  ./run-tests.sh

  # Keep environment running for debugging
  PA_TEST_KEEP=true ./run-tests.sh

  # Get a shell in the running container
  ./run-tests.sh --shell
EOF
    exit 0
    ;;
  --keep)
    export PA_TEST_KEEP=true
    main
    ;;
  --shell)
    docker-compose -f "$COMPOSE_FILE" exec pve-test bash
    ;;
  *)
    main
    ;;
esac
