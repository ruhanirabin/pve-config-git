# Proxmox Agent Test Suite

Automated testing using Docker environment with support for both real Proxmox VE (Linux only) and generic Ubuntu (Windows compatible) modes.

## Overview

This test suite supports two testing modes:

1. **Ubuntu Mode (Default)**: Uses Ubuntu 22.04 container - compatible with Windows Docker. Tests script syntax, structure, and basic flow without requiring real PVE.

2. **PVE Mode**: Uses the `ghcr.io/longqt-sea/proxmox-ve` Docker image to provide a realistic Proxmox VE environment. **Linux only** - requires cgroup support.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Bash (Git Bash on Windows)

## Quick Start

```bash
cd tests
./run-tests.sh
```

## Platform Compatibility

### Windows Docker

**⚠️ Important**: The Proxmox VE container (`ghcr.io/longqt-sea/proxmox-ve`) **does NOT work** on Windows Docker Desktop because:
- It requires Linux cgroups v1/v2 support
- It needs systemd as PID 1 with full privileges
- Windows Docker lacks the necessary kernel features

**Use the default Ubuntu mode** on Windows:
```bash
./run-tests.sh              # Ubuntu mode (default, Windows compatible)
```

### Linux / WSL2

On Linux or WSL2, you can use either mode:

```bash
# Ubuntu mode (faster, tests script structure)
./run-tests.sh

# PVE mode (tests actual PVE operations - Linux only)
./run-tests.sh --pve-mode
```

## Test Environment

The `docker-compose.yml` creates services based on selected mode:

### Ubuntu Mode (Default)
- **ubuntu-test**: Ubuntu 22.04 container with PA_TEST_MODE=true
- **git-server**: Bare git repo for backup target testing

### PVE Mode (`--pve-mode`)
- **pve-test**: Proxmox VE container with agent code mounted
- **git-server**: Bare git repo for backup target testing

### Ports (for debugging)

Ubuntu mode:
- `2223`: SSH access to Ubuntu container

PVE mode:
- `2222`: SSH access to PVE container
- `8006`: Proxmox Web UI (optional)

## Running Tests

### Run all tests (Ubuntu mode, Windows compatible)
```bash
./run-tests.sh
```

### Run tests with real PVE container (Linux only)
```bash
./run-tests.sh --pve-mode
```

### Keep environment after tests (for debugging)
```bash
PA_TEST_KEEP=true ./run-tests.sh
```

### Get a shell in the test container
```bash
./run-tests.sh --shell
```

### Detect platform and get recommendations
```bash
./run-tests.sh --detect
```

### Run individual tests manually (Ubuntu mode)
```bash
docker-compose --profile ubuntu up -d

# Wait for healthy, then:
docker-compose exec ubuntu-test bash -c "
  cd /proxmox-agent
  bash tests/test-doctor.sh
"
```

### Run individual tests manually (PVE mode)
```bash
docker-compose --profile pve up -d

# Wait for healthy, then:
docker-compose exec pve-test bash -c "
  cd /proxmox-agent
  bash tests/test-doctor.sh
"
```

## Test Scripts

| Script | Purpose |
|--------|---------|
| `run-tests.sh` | Main test runner - orchestrates all tests |
| `test-doctor.sh` | Doctor/preinstall-report validation |
| `test-install.sh` | Installation flow testing |
| `test-backup.sh` | Backup script execution |
| `test-shutdown.sh` | Hardening verification (flock, shutdown-state, PID tracing) |

These test scripts work in both modes since they primarily test:
- Script syntax and structure
- Configuration validation
- Code paths and logic
- Hardening mechanisms

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
| `PA_TEST_IMAGE` | `ghcr.io/longqt-sea/proxmox-ve` | PVE image override (PVE mode only) |
| `PA_PVE_MODE` | `false` | Set to `true` to force PVE mode |

## Mode Differences

| Feature | Ubuntu Mode | PVE Mode |
|---------|-------------|----------|
| Windows compatible | ✅ Yes | ❌ No |
| Tests script syntax | ✅ Yes | ✅ Yes |
| Tests PVE operations | ❌ No* | ✅ Yes |
| Startup time | ~30s | ~60s |
| Container size | ~200MB | ~1GB |

*The Ubuntu mode tests script structure and basic flow, but cannot test actual `qm`/`pct` commands since there's no real PVE.

## Limitations

### Ubuntu Mode
- Real `qm`/`pct` commands are not available (expected)
- Some PVE-specific paths may be missing (expected)
- Tests focus on script structure, syntax, and hardening

### PVE Mode
- Requires Linux with proper cgroup support
- Will fail on Windows Docker Desktop
- Systemd must be able to run as PID 1

## Windows Workarounds

For full PVE testing on Windows, consider:

1. **WSL2 with Docker**: Install Docker Desktop with WSL2 backend
   ```powershell
   # In WSL2 terminal:
   cd tests
   ./run-tests.sh --pve-mode
   ```

2. **Linux VM**: Use a Linux VM (VirtualBox, VMware, Hyper-V)

3. **CI/CD**: Use GitHub Actions or similar Linux-based CI

4. **Remote Linux**: SSH to a Linux machine with Docker

## Troubleshooting

### Container won't start (Ubuntu mode)
```bash
docker-compose --profile ubuntu down -v
docker-compose --profile ubuntu up -d
docker-compose logs ubuntu-test
```

### Container won't start (PVE mode on Linux)
```bash
docker-compose --profile pve down -v
docker-compose --profile pve up -d
docker-compose logs pve-test
```

### PVE mode fails on Windows
This is expected. The PVE container requires Linux cgroups. Use the default Ubuntu mode:
```bash
./run-tests.sh  # Ubuntu mode (default)
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
- Supports both Ubuntu (Windows compatible) and PVE (Linux only) modes
- Tests actual agent functionality
- Includes hardening verification
- Provides better debugging capabilities

Both can coexist — `docker-guided-smoke.sh` for quick Ubuntu flow checks, this suite for comprehensive testing.

## Quick Reference

```bash
# Windows - use Ubuntu mode (default)
./run-tests.sh

# Linux - choose your mode
./run-tests.sh              # Ubuntu mode
./run-tests.sh --pve-mode   # PVE mode

# Platform detection
./run-tests.sh --detect

# Help
./run-tests.sh --help
```
