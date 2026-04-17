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
pa_rotate_log_family "$LOG_FILE" "${BACKUP_LOG_RETENTION_DAYS:-}"
exec > >(tee -a "$LOG_FILE") 2>&1

REPO_DIR="${REPO_DIR:-/root/pve-config}"
REPO_BRANCH="${REPO_BRANCH:-main}"
NODE_NAME="$(hostname -s 2>/dev/null || hostname)"
TARGET_DIR="$REPO_DIR/$NODE_NAME"
DATE_TAG="$(date '+%Y-%m-%d %H:%M')"

TG_TOKEN="${BOT_TOKEN:-}"
TG_CHAT="${CHAT_ID:-}"

send_telegram() {
  local msg="$1"
  [[ -z "$TG_TOKEN" || -z "$TG_CHAT" ]] && return 0
  curl -s -X POST "https://api.telegram.org/bot$TG_TOKEN/sendMessage" \
    -d chat_id="$TG_CHAT" \
    -d text="$msg" \
    -d parse_mode="Markdown" >/dev/null || true
}

echo "=== Backup start: node=$NODE_NAME time=$DATE_TAG agent=v${AGENT_VERSION:-unknown} ==="

if [[ "$PWD" == "$REPO_DIR" || "$PWD" == "$REPO_DIR/"* ]]; then
  echo "Do not run this script from inside the git repo folder."
  pcg_send_webhook "backup" "failed" "Backup blocked" "Script executed from inside REPO_DIR." || true
  exit 1
fi

mkdir -p "$REPO_DIR"
[ -d "$REPO_DIR/.git" ] || git -C "$REPO_DIR" init -b "$REPO_BRANCH"
git -C "$REPO_DIR" checkout -B "$REPO_BRANCH" >/dev/null 2>&1 || true

mkdir -p "$TARGET_DIR"/{systemd,scripts,network,etc-pve,pve-lxc,pve-firewall,root-profile,extra}

echo "Collecting allowlisted configs..."

find /etc/systemd/system/ -type f \( -name "*.service" -o -name "*.timer" \) \
  ! -path "*/wanted/*" \
  -exec cp --parents {} "$TARGET_DIR/systemd/" \; 2>/dev/null || true

cp /usr/local/bin/*.sh "$TARGET_DIR/scripts/" 2>/dev/null || true
cp /etc/network/interfaces "$TARGET_DIR/network/" 2>/dev/null || true

cp /etc/pve/datacenter.cfg "$TARGET_DIR/etc-pve/" 2>/dev/null || true
cp /etc/pve/storage.cfg "$TARGET_DIR/etc-pve/" 2>/dev/null || true
cp /etc/pve/lxc/*.conf "$TARGET_DIR/pve-lxc/" 2>/dev/null || true
cp /etc/pve/firewall/* "$TARGET_DIR/pve-firewall/" 2>/dev/null || true

cp /root/.bashrc "$TARGET_DIR/root-profile/" 2>/dev/null || true
cp /root/.zshrc "$TARGET_DIR/root-profile/" 2>/dev/null || true
cp /root/.profile "$TARGET_DIR/root-profile/" 2>/dev/null || true
crontab -l -u root > "$TARGET_DIR/root-profile/crontab.txt" 2>/dev/null || true

if [ -n "${BACKUP_INCLUDE_EXTRA:-}" ]; then
  IFS=',' read -r -a extra_paths <<< "$BACKUP_INCLUDE_EXTRA"
  for p in "${extra_paths[@]}"; do
    p="$(echo "$p" | xargs)"
    [ -n "$p" ] || continue
    if [ -e "$p" ]; then
      cp -a --parents "$p" "$TARGET_DIR/extra/" 2>/dev/null || true
    fi
  done
fi

cd "$REPO_DIR"
git add -A

if git diff --cached --quiet; then
  echo "No changes detected."
  pcg_send_webhook "backup" "no_changes" "No backup changes" "No files changed for node $NODE_NAME." || true
  exit 0
fi

FULL_DIFF="$(git diff --cached --stat || true)"
CRITICAL="$(git diff --cached --name-only | grep -E "storage.cfg|lxc/|qemu-server/" || true)"
CHANGES="$(git diff --cached --name-only | wc -l | xargs)"
COMMIT_MSG="[$NODE_NAME] $CHANGES files changed - $DATE_TAG (agent v${AGENT_VERSION:-unknown})"

echo "=== Full diff ==="
echo "$FULL_DIFF"

git commit -m "$COMMIT_MSG"
if git -C "$REPO_DIR" remote get-url origin >/dev/null 2>&1; then
  if git -C "$REPO_DIR" ls-remote --exit-code --heads origin "$REPO_BRANCH" >/dev/null 2>&1; then
    git pull --rebase origin "$REPO_BRANCH"
  else
    echo "Remote branch origin/$REPO_BRANCH does not exist yet; skipping rebase pull."
  fi
fi
git push origin "$REPO_BRANCH"

TAG_BASE="$NODE_NAME-backup-$(date '+%Y-%m-%d-%H%M')"
TAG_NAME="$TAG_BASE"
tag_suffix=1
while git rev-parse -q --verify "refs/tags/$TAG_NAME" >/dev/null 2>&1 || \
      git ls-remote --exit-code --tags origin "refs/tags/$TAG_NAME" >/dev/null 2>&1; do
  TAG_NAME="${TAG_BASE}-${tag_suffix}"
  tag_suffix=$((tag_suffix + 1))
done
git tag "$TAG_NAME"
git push origin "$TAG_NAME"

if [[ -n "$CRITICAL" ]]; then
  MSG="*Proxmox Critical Change*\nNode: \`$NODE_NAME\`\nTime: $DATE_TAG\n\nChanges:\n\`\`\`\n$CRITICAL\n\`\`\`"
  send_telegram "$MSG"
fi

pcg_send_webhook "backup" "success" "Backup pushed" \
  "Committed $CHANGES changed file(s) on node $NODE_NAME to branch $REPO_BRANCH." || true

echo "Backup complete for $NODE_NAME (agent v${AGENT_VERSION:-unknown})."
