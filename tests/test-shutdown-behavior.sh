#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export T ROOT_DIR
unset INVOCATION_ID
# Redirect fixed production paths in a disposable copy; never run host shutdown.
python3 - <<'PY'
from pathlib import Path
import os
p=Path(os.environ['ROOT_DIR'])/'bin/pcg-shutdown-proxmox.sh'
s=p.read_text().replace('PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', '').replace('LOG_DIR="/var/log/pcg-shutdown"','LOG_DIR="$T/logs"').replace('LOCK_FILE="/var/lock/pcg-shutdown.lock"','LOCK_FILE="$T/shutdown.lock"').replace('/usr/local/bin/pcg-send-telegram.sh','mock_notify').replace('/usr/local/bin/pcg-backup-config.sh','mock_backup').replace('/sbin/shutdown -h now','mock_host_shutdown')
(Path(os.environ['T'])/'shutdown.sh').write_text(s)
PY
cat > "$T/lib.sh" <<'LIB'
source "$ROOT_DIR/bin/pcg-agent-lib.sh"
pcg_load_env() { :; }
pcg_load_version() { AGENT_VERSION=test; }
pcg_send_webhook() { :; }
systemctl() { echo "${MOCK_STATE:-running}"; [[ "${MOCK_STATE:-running}" != stopping ]]; }
qm() {
  case "$1" in
    list) printf 'VMID NAME\n100 first\n101 second\n' ;;
    status) echo 'status: running' ;;
    shutdown|stop) echo "vm $*" >> "$T/actions" ;;
  esac
}
pct() {
  case "$1" in
    list) printf 'VMID NAME\n200 container\n' ;;
    status) echo 'status: running' ;;
    shutdown|stop) echo "lxc $*" >> "$T/actions" ;;
  esac
}
cut() { echo 1000; }
sleep() { :; }
logger() { :; }
mock_notify() { :; }
mock_backup() { return 1; }
mock_host_shutdown() { echo host >> "$T/actions"; }
LIB
export LIB_FILE="$T/lib.sh"
if MOCK_STATE=stopping bash "$T/shutdown.sh" --execute; then echo 'Stopping guard failed'; exit 1; fi
[[ ! -f "$T/actions" ]]
bash "$T/shutdown.sh" --execute
for expected in 'vm stop 100' 'vm stop 101' 'lxc stop 200' host; do
  grep -qx "$expected" "$T/actions"
done
# Systemd invokes the service after entering stopping. It must perform the
# backup/guest flow and leave the selected halt/reboot action to systemd.
: > "$T/actions"
INVOCATION_ID=pcg-test MOCK_STATE=stopping bash "$T/shutdown.sh" --execute
for expected in 'vm stop 100' 'vm stop 101' 'lxc stop 200'; do
  grep -qx "$expected" "$T/actions"
done
! grep -qx host "$T/actions"
echo 'Shutdown manual/systemd guards and forced guest continuation: PASS'
