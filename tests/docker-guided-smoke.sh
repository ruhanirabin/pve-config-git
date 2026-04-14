#!/usr/bin/env bash

set -euo pipefail

# Runs a non-live smoke test of the guided installer in Docker.
# Usage:
#   bash tests/docker-guided-smoke.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${PA_TEST_IMAGE:-ubuntu:22.04}"

docker run --rm -i \
  -v "${ROOT_DIR}:/work" \
  -w /work \
  "${IMAGE}" \
  bash -lc '
    set -euo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq bash curl git ca-certificates openssh-client tar >/dev/null

    # Local bare remote for non-live git reachability checks.
    git init --bare /tmp/remote.git >/dev/null

    # Guided answers:
    # install.sh confirm -> y
    # proxmox-agent install confirm -> y
    # repo dir -> /root/pve-config
    # branch -> main
    # git remote -> /tmp/remote.git
    # retention -> 14
    # notify mode -> none
    # reinstall confirm (if shown) -> y
    PA_TEST_MODE=true PA_INSTALL_MODE=auto bash ./install.sh <<EOF
y
y
/root/pve-config
main
/tmp/remote.git
14
none
y
EOF
  '
