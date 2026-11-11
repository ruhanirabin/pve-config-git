#!/bin/bash
# Isolated Ubuntu guided install, installed reinstall/save/resume and doctor.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="${PCG_CONTAINER_RUNTIME:-docker}"
IMAGE="${PCG_TEST_IMAGE:-ubuntu:24.04}"
command -v "$RUNTIME" >/dev/null || { echo "Missing container runtime: $RUNTIME" >&2; exit 1; }
"$RUNTIME" run --rm -i -v "${ROOT_DIR}:/work:ro" -w /work "$IMAGE" bash -s <<'CONTAINER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive PCG_TEST_MODE=true
apt-get update -qq
apt-get install -y -qq bash curl git ca-certificates openssh-client tar util-linux cron python3 >/dev/null
git init --bare /tmp/remote.git >/dev/null
# Exercise real Git against a local remote while keeping production URL validation.
git config --global url.file:///tmp/remote.git.insteadOf https://github.com/pcg-test/backup.git
timeout 120 bash ./install.sh <<'ANSWERS'
y
y
https://github.com/pcg-test/backup.git
/root/pve-config
main
14
PCG Test
test@example.com
4
1
ANSWERS
pcg doctor --json
# Save a reinstall draft, restoring the original installation.
timeout 120 pcg install <<'ANSWERS'
1
y






4
2
ANSWERS
test -f /root/.pcg-agent-install-draft.env
test -x /usr/local/bin/pcg
timeout 120 pcg install --resume <<'ANSWERS'
1
y






4
1
ANSWERS
test ! -e /root/.pcg-agent-install-draft.env
pcg doctor --json
bash tests/test-backup.sh
bash tests/test-shutdown.sh
bash tests/test-shutdown-behavior.sh
echo 'Guided installation, installed save/resume and doctor: PASS'
CONTAINER
