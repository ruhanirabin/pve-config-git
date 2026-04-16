# Proxmox Agent Test Suite

Automated testing using a real Proxmox VE container environment.

## Overview

This test suite uses the `ghcr.io/longqt-sea/proxmox-ve` Docker image to provide a realistic Proxmox VE environment for testing the agent without affecting production systems.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Bash (Git Bash on Windows)

## Quick Start

```bash
cd tests
./run-tests.sh
```

## Test Environment

The `docker-compose.yml` creates:

- **pve-test**: Proxmox VE container with agent code mounted
- **git-server**: Bare git repo for backup target testing

### Ports (for debugging)

- `2222`: SSH access to PVE container
- `8006`: Proxmox Web UI (optional)

### Access the test container

```bash
# Get a shell in the running container
./run-tests.sh --shell

# Or manually:
docker-compose exec pve-test bash
```

## Test Scripts

| Script | Purpose |
|--------|---------|
| `run-tests.sh` | Main test runner - orchestrates all tests |
| `test-doctor.sh` | Doctor/preinstall-report validation |
| `test-install.sh` | Installation flow testing |
| `test-backup.sh` | Backup script execution |
| `test-shutdown.sh` | Hardening verification (flock, shutdown-state, PID tracing) |

## Running Tests

### Run all tests
```bash
./run-tests.sh
```

### Keep environment after tests (for debugging)
```bash
PA_TEST_KEEP=true ./run-tests.sh
```

### Get a shell in the test container
```bash
./run-tests.sh --shell
```

### Run individual tests manually
```bash
docker-compose up -d

# Wait for healthy, then:
docker-compose exec pve-test bash -c "
  cd /proxmox-agent
  bash tests/test-doctor.sh
"
```

## What Gets Tested

### 1. Doctor / Preinstall Report
- JSON and text output formats
- Install state detection
- Planned actions reporting

### 2. Installation
- Library loading
- Binary staging
- Unit file staging
- Script syntax validation

### 3. Backup
- Git repository initialization
- Backup script execution flow
- Logging functionality

### 4. Shutdown (Hardening)
- Atomic flock mechanism
- Shutdown-state detection
- PID/PPID execution tracing
- Boot protection (uptime check)
- Lock file location

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PA_TEST_KEEP` | `false` | Keep containers running after tests |
| `PA_TEST_IMAGE` | `ghcr.io/longqt-sea/proxmox-ve` | PVE image override |

## Limitations

Since this runs in a container:
- Real `qm`/`pct` commands may not work fully
- Systemd may not be PID 1 in all environments
- Some PVE-specific paths may be missing

These are integration/smoke tests — they verify script structure, logic, and hardening, not full PVE operations.

## Troubleshooting

### Container won't start
```bash
docker-compose down -v
docker-compose up -d
docker-compose logs pve-test
```

### Tests fail but container is running
```bash
# Get shell and debug
./run-tests.sh --shell
# Then manually run: cd /proxmox-agent && bash tests/test-<name>.sh
```

### Permission issues on Windows
Ensure the test scripts have Unix line endings:
```bash
dos2unix tests/*.sh
```

## Migration from Generic Ubuntu Tests

The old `docker-guided-smoke.sh` tested basic installer flow on Ubuntu. This new suite:
- Uses real Proxmox VE container
- Tests actual agent functionality
- Includes hardening verification
- Provides better debugging capabilities

Both can coexist — `docker-guided-smoke.sh` for quick Ubuntu flow checks, this suite for comprehensive PVE testing.
