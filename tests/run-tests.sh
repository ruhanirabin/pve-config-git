#!/usr/bin/env bash
# ============================================================
# Proxmox Agent Test Runner
# Automated testing using Proxmox VE Docker environment
#
# Modes:
#   - Default (Ubuntu mode): Uses Ubuntu 22.04 container for Windows compatibility
#   - PVE mode (--pve-mode): Uses real Proxmox VE container (Linux only)
#
# The PVE container (ghcr.io/longqt-sea/proxmox-ve) requires Linux cgroups
# and does NOT work on Windows Docker. Use Ubuntu mode for Windows.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# Mode detection
PA_PVE_MODE="${PA_PVE_MODE:-false}"
TEST_SERVICE="ubuntu-test"
TEST_PROFILE="ubuntu"
SSH_PORT="2223"

if [[ "$PA_PVE_MODE" == "true" ]]; then
  TEST_SERVICE="pve-test"
  TEST_PROFILE="pve"
  SSH_PORT="2222"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
highlight() { echo -e "${BLUE}[MODE]${NC} $*"; }

# Cleanup function
cleanup() {
  if [[ "${PA_TEST_KEEP:-false}" != "true" ]]; then
    info "Cleaning up test environment..."
    docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
  else
    info "Keeping test environment (PA_TEST_KEEP=true)"
    info "Access container at: ssh root@localhost -p $SSH_PORT (password: testpass123)"
    if [[ "$PA_PVE_MODE" == "true" ]]; then
      info "Proxmox UI: https://localhost:8006"
    fi
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

# Detect if running on Windows
detect_windows() {
  if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "win32" ]]; then
    echo "true"
  elif [[ -n "${WINDIR:-}" ]] && [[ -n "${OS:-}" ]]; then
    echo "true"
  else
    # Check Docker Desktop for Windows
    if docker info 2>/dev/null | grep -qi "windows\|desktop"; then
      echo "possible"
    else
      echo "false"
    fi
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
  docker-compose -f "$COMPOSE_FILE" cp "$tar_file" "$TEST_SERVICE:/tmp/agent.tar.gz"
  docker-compose -f "$COMPOSE_FILE" exec -T "$TEST_SERVICE" bash -c '
    mkdir -p /proxmox-agent &&
    cd /proxmox-agent &&
    tar -xzf /tmp/agent.tar.gz &&
    rm /tmp/agent.tar.gz &&
    chmod +x bin/*.sh install.sh 2>/dev/null || true
  '
  
  rm -f "$tar_file"
  info "Agent code copied successfully"
}

# Run a test inside the container
run_test_in_container() {
  local test_name="$1"
  local test_script="$2"
  
  info "Running test: $test_name"
  
  if docker-compose -f "$COMPOSE_FILE" exec -T "$TEST_SERVICE" bash -c "
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

# Print mode banner
print_mode_banner() {
  echo ""
  if [[ "$PA_PVE_MODE" == "true" ]]; then
    highlight "═══════════════════════════════════════════════════════════"
    highlight "  PVE MODE (Proxmox VE Container)"
    highlight "  Using: ghcr.io/longqt-sea/proxmox-ve"
    highlight "  Platform: Linux only - requires cgroup support"
    highlight "═══════════════════════════════════════════════════════════"
  else
    highlight "═══════════════════════════════════════════════════════════"
    highlight "  UBUNTU MODE (Windows Compatible)"
    highlight "  Using: ubuntu:22.04"
    highlight "  Platform: Windows Docker compatible"
    highlight "  Note: Tests script syntax/structure, not actual PVE ops"
    highlight "═══════════════════════════════════════════════════════════"
  fi
  echo ""
}

# Main test execution
main() {
  print_mode_banner
  
  info "Proxmox Agent Test Runner"
  info "=========================="
  
  check_deps
  
  # Start the test environment
  info "Starting test environment ($TEST_SERVICE)..."
  docker-compose -f "$COMPOSE_FILE" down -v 2>/dev/null || true
  docker-compose -f "$COMPOSE_FILE" --profile "$TEST_PROFILE" up -d
  
  # Wait for container to be ready
  wait_for_healthy "$TEST_SERVICE"
  
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

# Show help
show_help() {
  cat <<'EOF'
Usage: run-tests.sh [OPTIONS]

Run automated tests for Proxmox Agent using Docker environment.

MODES:
  Default (Ubuntu mode):  Uses Ubuntu 22.04 container - compatible with Windows Docker
  PVE mode (--pve-mode):  Uses real Proxmox VE container - Linux only, requires cgroups

OPTIONS:
  --help, -h          Show this help message
  --pve-mode          Use real PVE container (Linux only, requires cgroups v2)
  --ubuntu-mode       Use Ubuntu container (default, Windows compatible)
  --keep              Keep test environment running after tests
  --shell             Start a shell in the test container
  --detect            Detect platform and recommend mode

ENVIRONMENT VARIABLES:
  PA_TEST_KEEP=true       Keep containers running after tests
  PA_TEST_IMAGE           Override the PVE image (PVE mode only)
  PA_PVE_MODE=true        Force PVE mode (equivalent to --pve-mode)

EXAMPLES:
  # Run tests in Ubuntu mode (default, Windows compatible)
  ./run-tests.sh

  # Run tests with real PVE container (Linux only)
  ./run-tests.sh --pve-mode

  # Keep environment running for debugging
  PA_TEST_KEEP=true ./run-tests.sh

  # Get a shell in the running container
  ./run-tests.sh --shell

WINDOWS COMPATIBILITY:
  The PVE container (ghcr.io/longqt-sea/proxmox-ve) requires Linux cgroups
  and will NOT work on Windows Docker. Use the default Ubuntu mode for
  Windows, which tests script syntax and structure without requiring PVE.

  For full PVE testing on Windows, consider:
  - Running tests on WSL2 (Windows Subsystem for Linux)
  - Using a Linux VM with Docker
  - Using GitHub Actions or other Linux CI environment
EOF
}

# Detect platform and provide recommendations
detect_platform() {
  local is_windows
  is_windows=$(detect_windows)
  
  echo ""
  info "Platform Detection"
  info "=================="
  
  # Show OS info
  info "Detected OS type: ${OSTYPE:-unknown}"
  
  # Show Docker info
  if docker info >/dev/null 2>&1; then
    info "Docker: Available"
    docker version --format '{{.Server.Os}}' 2>/dev/null | xargs -I {} info "Docker OS: {}"
  else
    error "Docker: Not available or not running"
  fi
  
  # Windows detection
  if [[ "$is_windows" == "true" ]] || [[ "$is_windows" == "possible" ]]; then
    warn "Windows environment detected"
    info "Recommendation: Use default Ubuntu mode (./run-tests.sh)"
    info "PVE mode is NOT compatible with Windows Docker"
  else
    info "Linux/Unix environment detected"
    info "Recommendation: Use either mode"
    info "  - Ubuntu mode: ./run-tests.sh (faster, tests structure)"
    info "  - PVE mode:    ./run-tests.sh --pve-mode (tests actual PVE)"
  fi
  
  echo ""
}

# Handle arguments
case "${1:-}" in
  --help|-h)
    show_help
    exit 0
    ;;
  --detect)
    detect_platform
    exit 0
    ;;
  --pve-mode)
    PA_PVE_MODE=true
    TEST_SERVICE="pve-test"
    TEST_PROFILE="pve"
    SSH_PORT="2222"
    main
    ;;
  --ubuntu-mode)
    PA_PVE_MODE=false
    TEST_SERVICE="ubuntu-test"
    TEST_PROFILE="ubuntu"
    SSH_PORT="2223"
    main
    ;;
  --keep)
    export PA_TEST_KEEP=true
    main
    ;;
  --shell)
    # Determine which service is running
    if docker-compose -f "$COMPOSE_FILE" ps | grep -q "pa-test-pve"; then
      docker-compose -f "$COMPOSE_FILE" exec pve-test bash
    elif docker-compose -f "$COMPOSE_FILE" ps | grep -q "pa-test-ubuntu"; then
      docker-compose -f "$COMPOSE_FILE" exec ubuntu-test bash
    else
      error "No test container is running. Start tests first or use --keep flag."
      exit 1
    fi
    ;;
  "")
    # Default: Ubuntu mode (Windows compatible)
    main
    ;;
  *)
    error "Unknown option: $1"
    error "Use --help for usage information"
    exit 1
    ;;
esac
