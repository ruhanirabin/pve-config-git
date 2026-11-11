#!/bin/bash

# ============================================================
# pcg-backup-config.sh
# Agent Version: runtime sourced from pcg-agent-version
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_FILE="${LIB_FILE:-$SCRIPT_DIR/pcg-agent-lib.sh}"
[ -f "$LIB_FILE" ] || LIB_FILE="/usr/local/bin/pcg-agent-lib.sh"
# shellcheck disable=SC1090
source "$LIB_FILE"

pcg_load_version
pcg_load_env

LOG_FILE="${BACKUP_LOG_FILE:-/var/log/pcg-backup-config.log}"
pcg_rotate_log_family "$LOG_FILE" "${BACKUP_LOG_RETENTION_DAYS:-}"
exec > >(tee -a "$LOG_FILE") 2>&1

REPO_DIR="${REPO_DIR:-/root/pve-config}"
REPO_BRANCH="${REPO_BRANCH:-main}"
NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TARGET_DIR="$REPO_DIR/$NODE_NAME"
DATE_TAG="$(date '+%Y-%m-%d %H:%M')"

send_telegram() {
  [[ -z "${BOT_TOKEN:-}" || -z "${CHAT_ID:-}" ]] && return 0
  if ! bash "$SCRIPT_DIR/pcg-send-telegram.sh" "$1"; then
    echo "WARNING Telegram delivery failed; check the Telegram log."
  fi
}

echo "=== Backup start: node=$NODE_NAME time=$DATE_TAG agent=v${AGENT_VERSION:-unknown} ==="

if [[ "$PWD" == "$REPO_DIR" || "$PWD" == "$REPO_DIR/"* ]]; then
  echo "Do not run this script from inside the git repo folder."
  pcg_send_webhook "backup" "failed" "Backup blocked" "Script executed from inside REPO_DIR." || true
  exit 1
fi

command -v flock >/dev/null || { echo "Missing dependency: flock (util-linux)"; exit 1; }
mkdir -p "$REPO_DIR"
REPO_DIR="$(cd "$REPO_DIR" && pwd -P)"
TARGET_DIR="$REPO_DIR/$NODE_NAME"
# The same repository lock covers timer, CLI and shutdown invocations.
exec 200>"$REPO_DIR/.pcg-backup.lock"
flock -w "${BACKUP_LOCK_TIMEOUT_SECONDS:-120}" 200 || {
  echo "Backup repository is busy; lock wait expired."
  exit 1
}
[ -d "$REPO_DIR/.git" ] || git -C "$REPO_DIR" init -b "$REPO_BRANCH"
# Never reset an existing branch or discard another operation's work.
if git -C "$REPO_DIR" show-ref --verify --quiet "refs/heads/$REPO_BRANCH"; then
  git -C "$REPO_DIR" checkout "$REPO_BRANCH"
else
  git -C "$REPO_DIR" checkout -b "$REPO_BRANCH"
fi
[ ! -d "$REPO_DIR/.git/rebase-merge" ] && [ ! -d "$REPO_DIR/.git/rebase-apply" ] || {
  echo "Resolve the interrupted Git rebase before running backup."
  exit 1
}
git -C "$REPO_DIR" remote get-url origin >/dev/null || {
  echo "Missing origin remote. Run pcg install to configure the backup repository."
  exit 1
}
if [ -n "$(git -C "$REPO_DIR" diff --cached --name-only)" ]; then
  echo "Resolve existing staged changes before running backup."
  exit 1
fi

# Build a complete new snapshot before replacing the previous collection.
# BACKUP_SOURCE_ROOT permits isolated fixtures; production defaults to /.
SOURCE_ROOT="${BACKUP_SOURCE_ROOT:-}"
STAGE="$(mktemp -d "$REPO_DIR/.pcg-collection.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE"/{systemd,scripts,network,etc-pve,pve-lxc,pve-qemu-server,pve-firewall,root-profile,extra}
copy_optional() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then
    cp -a "$source" "$destination" || return 1
  fi
}
# Refuse to replace a good snapshot when the PVE configuration mount is absent.
[ -d "$SOURCE_ROOT/etc/pve/lxc" ] && [ -d "$SOURCE_ROOT/etc/pve/qemu-server" ] || {
  echo "PVE configuration directories unavailable; preserving the previous snapshot."
  exit 1
}
shopt -s nullglob
echo "Collecting allowlisted configs..."
find "$SOURCE_ROOT/etc/systemd/system" -type f \( -name '*.service' -o -name '*.timer' \) -print0 > "$STAGE/units.list"
while IFS= read -r -d '' file; do
  relative="${file#"$SOURCE_ROOT"}"
  mkdir -p "$STAGE/systemd/$(dirname "$relative")"
  cp -a "$file" "$STAGE/systemd/$relative"
done < "$STAGE/units.list"
rm "$STAGE/units.list"
for name in pcg pcg-agent-lib.sh pcg-doctor.sh pcg-backup-config.sh pcg-boot-notify.sh pcg-send-telegram.sh pcg-send-webhook.sh pcg-shutdown-proxmox.sh; do
  copy_optional "$SOURCE_ROOT/usr/local/bin/$name" "$STAGE/scripts/"
done
copy_optional "$SOURCE_ROOT/etc/network/interfaces" "$STAGE/network/"
for name in datacenter.cfg storage.cfg; do
  copy_optional "$SOURCE_ROOT/etc/pve/$name" "$STAGE/etc-pve/"
done
for file in "$SOURCE_ROOT"/etc/pve/lxc/*.conf; do cp -a "$file" "$STAGE/pve-lxc/"; done
for file in "$SOURCE_ROOT"/etc/pve/qemu-server/*.conf; do cp -a "$file" "$STAGE/pve-qemu-server/"; done
for file in "$SOURCE_ROOT"/etc/pve/firewall/*; do cp -a "$file" "$STAGE/pve-firewall/"; done
for name in .bashrc .zshrc .profile; do copy_optional "$SOURCE_ROOT/root/$name" "$STAGE/root-profile/"; done
if [ -z "$SOURCE_ROOT" ]; then
  command -v crontab >/dev/null || { echo "Missing dependency: crontab (cron)"; exit 1; }
  crontab -l -u root > "$STAGE/root-profile/crontab.txt" 2>"$STAGE/cron-error" || {
    grep -qi 'no crontab' "$STAGE/cron-error" || { echo "Cannot read root crontab"; exit 1; }
  }
  rm -f "$STAGE/cron-error"
fi
if [ -n "${BACKUP_INCLUDE_EXTRA:-}" ]; then
  IFS=',' read -r -a extra_paths <<< "$BACKUP_INCLUDE_EXTRA"
  for p in "${extra_paths[@]}"; do
    p="$(echo "$p" | xargs)"
    [ -n "$p" ] || continue
    [[ "$p" = /* ]] || { echo "Extra backup paths must be absolute."; exit 1; }
    if [ -e "$SOURCE_ROOT$p" ]; then
      (cd "${SOURCE_ROOT:-/}" && cp -a --parents ".${p}" "$STAGE/extra/")
    fi
  done
fi
# Preserve unrelated node files while refreshing every owned collection family.
mkdir -p "$TARGET_DIR"
for family in systemd scripts network etc-pve pve-lxc pve-qemu-server pve-firewall root-profile extra; do
  rm -rf "$TARGET_DIR/$family"
  mv "$STAGE/$family" "$TARGET_DIR/$family"
done
cd "$REPO_DIR"
git add -A -- "$NODE_NAME"

if git diff --cached --quiet; then
  echo "No configuration changes detected; synchronizing unpublished commits."
  pcg_git_network pull --rebase origin "$REPO_BRANCH" || {
    # An empty remote has no branch to pull yet; all other failures are fatal.
    refs="$(pcg_git_network ls-remote --heads origin "refs/heads/$REPO_BRANCH")" || exit 1
    [ -z "$refs" ] || exit 1
  }
  pcg_git_network push origin "$REPO_BRANCH"
  pcg_send_webhook "backup" "no_changes" "Backup synchronized" "No files changed for node $NODE_NAME; local commits pushed." || true
  exit 0
fi

FULL_DIFF="$(git diff --cached --stat || true)"
CRITICAL="$(git diff --cached --name-only | grep -E "storage.cfg|pve-lxc/|pve-qemu-server/" || true)"
CHANGES="$(git diff --cached --name-only | wc -l | xargs)"
COMMIT_MSG="[$NODE_NAME] $CHANGES files changed - $DATE_TAG (agent v${AGENT_VERSION:-unknown})"

echo "=== Full diff ==="
echo "$FULL_DIFF"

git commit -m "$COMMIT_MSG"
remote_refs="$(pcg_git_network ls-remote --heads origin "refs/heads/$REPO_BRANCH")"
if [ -n "$remote_refs" ]; then
    pcg_git_network pull --rebase origin "$REPO_BRANCH"
else
  echo "Remote branch does not exist yet; skipping rebase pull."
fi
pcg_git_network push origin "$REPO_BRANCH"

TAG_BASE="$NODE_NAME-backup-$(date '+%Y-%m-%d-%H%M')"
TAG_NAME="$TAG_BASE"
tag_suffix=1
while true; do
  tag_refs="$(pcg_git_network ls-remote --tags origin "refs/tags/$TAG_NAME")"
  if ! git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null && [ -z "$tag_refs" ]; then
    break
  fi
  TAG_NAME="${TAG_BASE}-${tag_suffix}"
  tag_suffix=$((tag_suffix + 1))
done
git tag "$TAG_NAME"
pcg_git_network push origin "$TAG_NAME"

if [[ -n "$CRITICAL" ]]; then
  MSG="Proxmox critical change on $NODE_NAME at $DATE_TAG ($CHANGES files)."
  send_telegram "$MSG"
fi

pcg_send_webhook "backup" "success" "Backup pushed" \
  "Committed $CHANGES changed file(s) on node $NODE_NAME to branch $REPO_BRANCH." || true

echo "Backup complete for $NODE_NAME (agent v${AGENT_VERSION:-unknown})."
