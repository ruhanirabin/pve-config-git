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

    # Mock systemd + github ssh auth for container-only smoke test.
    mkdir -p /mockbin
    cat > /mockbin/systemctl <<EOF
#!/usr/bin/env bash
echo "[mock-systemctl] $*" >&2
exit 0
EOF
    chmod +x /mockbin/systemctl

    cat > /mockbin/ssh <<EOF
#!/usr/bin/env bash
if echo "$*" | grep -q "git@github.com"; then
  echo "Hi test-user! You''ve successfully authenticated, but GitHub does not provide shell access."
  exit 1
fi
exec /usr/bin/ssh "$@"
EOF
    chmod +x /mockbin/ssh
    export PATH="/mockbin:$PATH"

    # Guided answers:
    # install.sh confirm -> y
    # proxmox-agent install confirm -> y
    # repo dir -> /root/pve-config
    # branch -> main
    # git remote -> git@github.com:test/test.git
    # retention -> 14
    # notify mode -> none
    # reinstall confirm (if shown) -> y
    printf "y\ny\n/root/pve-config\nmain\ngit@github.com:test/test.git\n14\nnone\ny\n" | PA_INSTALL_MODE=auto bash ./install.sh
  '
