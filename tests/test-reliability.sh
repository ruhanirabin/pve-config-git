#!/bin/bash
# Isolated behavior tests: no host config writes or external network access.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export T ROOT_DIR
fail() { echo "FAIL: $*" >&2; exit 1; }
# Load functions without dispatching the CLI.
LIB_FILE="$ROOT_DIR/bin/pcg-agent-lib.sh"
source <(sed '$d' "$ROOT_DIR/bin/pcg")
PCG_BIN_TARGET="$T/bin"
PCG_SYSTEMD_TARGET="$T/units"
PCG_ENV_TARGET="$T/config.env"
PCG_ENV_LEGACY="$T/legacy.env"
PCG_SOURCE_CACHE_ROOT="$T/cache"
mkdir -p "$PCG_BIN_TARGET" "$PCG_SYSTEMD_TARGET"
PCG_ENV_FILE_DEFAULT="$PCG_ENV_TARGET"
PCG_ENV_FILE_LEGACY="$PCG_ENV_LEGACY"
ENV_FILE="$T/empty.env"
: > "$ENV_FILE"
set +e
pcg_load_env
[[ $- != *e* ]] || fail 'env loading enabled errexit'
set -e
pcg_load_env
[[ $- == *e* ]] || fail 'env loading disabled errexit'
[[ "$(prompt_notification_mode <<< $'bad\n4')" == later ]] || fail 'menu warning leaked'
[[ "$(prompt_final_action <<< $'bad\n2')" == save ]] || fail 'final action warning leaked'
[[ "$(prompt_existing_install_action <<< $'bad\n1')" == reinstall ]] || fail 'existing action warning leaked'
[[ "$(prompt_choice Test yes yes no <<< $'bad\nyes')" == yes ]] || fail 'choice warning leaked'
for unit in "${PCG_CANONICAL_UNIT_FILES[@]}"; do
  [[ "$unit" == pcg-* ]] || fail 'wrong canonical unit'
done
printf 'REPO_DIR=/legacy/settings\n' > "$PCG_ENV_LEGACY"
install_canonical_files_from_source_dir "$ROOT_DIR"
grep -q /legacy/settings "$PCG_ENV_TARGET" || fail 'legacy settings replaced'
[[ -f "$PCG_SOURCE_CACHE_ROOT/$(cat "$ROOT_DIR/VERSION")/systemd/pcg-backup-config.timer" ]] || fail 'source cache missing'
# Missing payload and failed writes must return failure even with errexit disabled.
mkdir -p "$T/broken/env" "$T/broken/bin" "$T/broken/systemd"
cp "$ROOT_DIR/VERSION" "$T/broken/"
cp "$ROOT_DIR/env/pcg-agent.env.example" "$T/broken/env/"
set +e
install_canonical_files_from_source_dir "$T/broken"
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail 'missing files reported success'
install() { return 73; }
set +e
install_canonical_files_from_source_dir "$ROOT_DIR"
rc=$?
set -e
unset -f install
[[ "$rc" -ne 0 ]] || fail 'failed copy reported success'
# Snapshot and rollback must include canonical and pa-* units.
pcg_systemctl() { echo "$*" >> "$T/systemctl-actions"; }
systemctl() { [[ "$2" == pcg-backup-config.timer ]]; }
echo old > "$PCG_SYSTEMD_TARGET/pcg-backup-config.service"
echo legacy > "$PCG_SYSTEMD_TARGET/pa-backup-config.timer"
backup_current_install "$T/snapshot"
echo new > "$PCG_SYSTEMD_TARGET/pcg-backup-config.service"
restore_from_backup "$T/snapshot"
grep -qx old "$PCG_SYSTEMD_TARGET/pcg-backup-config.service" || fail rollback
grep -qx legacy "$PCG_SYSTEMD_TARGET/pa-backup-config.timer" || fail 'legacy rollback'
grep -qx 'enable pcg-backup-config.timer' "$T/systemctl-actions" || fail 'enabled state rollback'
unset -f systemctl
# Installed source resolution uses the cached payload instead of /usr/local.
pcg_load_version() { AGENT_VERSION="$(cat "$ROOT_DIR/VERSION")"; }
VERSION_FILE="$T/missing/VERSION"
ensure_install_source
[[ "$REPO_ROOT" == "$PCG_SOURCE_CACHE_ROOT/$(cat "$ROOT_DIR/VERSION")" ]] || fail 'installed source resolution'
# A failed post-upgrade doctor must restore old files, version and settings.
cp -a "$ROOT_DIR/bin" "$ROOT_DIR/systemd" "$ROOT_DIR/env" "$T/broken/"
echo 0.8.2 > "$T/broken/VERSION"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/broken/bin/pcg"
git -C "$T/broken" init -q
git -C "$T/broken" -c user.name=Test -c user.email=test@example.com add .
git -C "$T/broken" -c user.name=Test -c user.email=test@example.com commit -qm fixture
git -C "$T/broken" tag v0.8.2
PCG_RUNTIME_VERSION_FILE="$PCG_BIN_TARGET/pcg-agent-version"
printf 'AGENT_VERSION="%s"\n' "$(cat "$ROOT_DIR/VERSION")" > "$PCG_RUNTIME_VERSION_FILE"
PCG_BACKUP_DIR_BASE="$T/snapshots"
PCG_UPGRADE_LOG="$T/upgrade.log"
AGENT_UPDATE_SOURCE="$T/broken"
old_binary="$(sha256sum "$PCG_BIN_TARGET/pcg")"
set +e
(TMPDIR="$T"; export TMPDIR; require_root() { :; }; pcg_load_env() { :; }; cmd_upgrade --target v0.8.2) > "$T/upgrade-output" 2>&1
rc=$?
set -e
[[ "$rc" -ne 0 ]] || fail 'failed doctor accepted'
[[ "$(sha256sum "$PCG_BIN_TARGET/pcg")" == "$old_binary" ]] || fail 'upgrade binary rollback'
grep -q "$(cat "$ROOT_DIR/VERSION")" "$PCG_RUNTIME_VERSION_FILE" || fail 'upgrade version rollback'
grep -q 'rolled back' "$T/upgrade-output" || { cat "$T/upgrade-output"; fail 'rollback not reached'; }
# Daily families and continuously appended logs both expire.
mkdir -p "$T/logs"
touch -d '30 days ago' "$T/logs/shutdown_2020-01-01.log" "$T/logs/backup.log"
pcg_rotate_log_family "$T/logs/shutdown_$(date +%F).log" 7
[[ ! -e "$T/logs/shutdown_2020-01-01.log" ]] || fail 'dated retention'
pcg_rotate_log_family "$T/logs/backup.log" 7
[[ ! -e "$T/logs/backup.log" ]] || fail 'active rotation'
[[ -z "$(find "$T/logs" -type f -print)" ]] || fail 'expired rotated log retained'
# Real Git collection and publication against a local bare repository.
F="$T/source"
mkdir -p "$F"/{etc/pve/lxc,etc/pve/qemu-server,etc/pve/firewall,etc/systemd/system,usr/local/bin,etc/network,root}
echo vm > "$F/etc/pve/qemu-server/100.conf"
echo lxc > "$F/etc/pve/lxc/101.conf"
echo firewall > "$F/etc/pve/firewall/101.fw"
echo unit > "$F/etc/systemd/system/custom.service"
echo managed > "$F/usr/local/bin/pcg-backup-config.sh"
echo secret > "$F/usr/local/bin/unrelated.sh"
export PCG_REAL_LIB="$ROOT_DIR/bin/pcg-agent-lib.sh"
cat > "$T/lib.sh" <<'LIB'
source "$PCG_REAL_LIB"
pcg_load_env() { :; }
pcg_load_version() { AGENT_VERSION=test; }
pcg_send_webhook() { :; }
LIB
export LIB_FILE="$T/lib.sh" REPO_DIR="$T/repo" REPO_BRANCH=main
export BACKUP_SOURCE_ROOT="$F" BACKUP_LOG_FILE="$T/backup.log" BOT_TOKEN='' CHAT_ID=''
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
git init -q --bare "$T/remote"
git init -q -b main "$REPO_DIR"
git -C "$REPO_DIR" remote add origin "$T/remote"
logger() { printf '%s\n' "${@: -1}" >> "$T/journal-events.jsonl"; }
export -f logger
run_backup() { (cd "$T" && bash "$ROOT_DIR/bin/pcg-backup-config.sh") > "$T/output" 2>&1 || { cat "$T/output"; return 1; }; }
run_backup
node="$(hostname -s)"
[[ -f "$REPO_DIR/$node/pve-qemu-server/100.conf" ]] || fail 'VM definition missing'
[[ ! -e "$REPO_DIR/$node/scripts/unrelated.sh" ]] || fail 'unrelated script collected'
rm "$F/etc/pve/lxc/101.conf" "$F/etc/pve/firewall/101.fw" "$F/etc/systemd/system/custom.service"
run_backup
[[ ! -e "$REPO_DIR/$node/pve-lxc/101.conf" ]] || fail 'stale LXC'
[[ ! -e "$REPO_DIR/$node/pve-firewall/101.fw" ]] || fail 'stale firewall'
[[ ! -e "$REPO_DIR/$node/systemd/etc/systemd/system/custom.service" ]] || fail 'stale unit'
# Failed push followed by no config changes must still publish the local commit.
cat > "$T/remote/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$T/remote/hooks/pre-receive"
echo changed >> "$F/etc/pve/qemu-server/100.conf"
if run_backup; then fail 'rejected push reported success'; fi
local_head="$(git -C "$REPO_DIR" rev-parse HEAD)"
rm "$T/remote/hooks/pre-receive"
run_backup
[[ "$(git --git-dir="$T/remote" rev-parse refs/heads/main)" == "$local_head" ]] || fail 'unpublished commit not retried'
# Rejected Telegram responses are bounded, logged and non-blocking.
curl() {
  [[ " $* " == *' --max-time '* ]] || return 1
  echo bounded > "$T/curl-timeout"
  echo '{"ok":false}'
}
export -f curl
export BOT_TOKEN=dummy CHAT_ID=dummy TELEGRAM_LOG_FILE="$T/telegram.log"
echo notify >> "$F/etc/pve/qemu-server/100.conf"
run_backup
[[ -f "$T/curl-timeout" ]] || fail 'notification lacked timeout'
grep -q 'WARNING Telegram delivery failed' "$T/output" || fail 'notification failure hidden'
unset -f curl
unset BOT_TOKEN CHAT_ID
# Missing configuration mount must preserve the last snapshot.
mv "$F/etc/pve" "$F/etc/pve-hidden"
if run_backup; then fail 'missing PVE mount reported success'; fi
[[ -f "$REPO_DIR/$node/pve-qemu-server/100.conf" ]] || fail 'snapshot lost'
mv "$F/etc/pve-hidden" "$F/etc/pve"
# A competing entry point must not touch the repository.
(exec 201>"$REPO_DIR/.pcg-backup.lock"; flock 201; BACKUP_LOCK_TIMEOUT_SECONDS=0 run_backup && exit 1; exit 0) || fail 'lock did not serialize'
python3 - <<'CHECK'
import json,os
from pathlib import Path
rows=[json.loads(x) for x in (Path(os.environ['T'])/'journal-events.jsonl').read_text().splitlines()]
assert any(x['event']=='backup_success' and x['branch_push']=='confirmed' and x['outcome']=='changed' and len(x['commit'])==40 for x in rows)
assert any(x['event']=='backup_success' and x['branch_push']=='confirmed' and x['outcome']=='unchanged' for x in rows)
assert any(x['event']=='backup_failed' and x['phase']=='push_branch' and x['branch_push']=='not_confirmed' and x['exit_status']!=0 for x in rows)
assert any(x['event']=='backup_failed' and x['phase']=='collect' for x in rows)
assert any(x['event']=='backup_failed' and x['phase']=='lock' for x in rows)
CHECK
echo 'Reliability regressions: PASS'
