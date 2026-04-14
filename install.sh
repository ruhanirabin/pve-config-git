#!/bin/bash

set -euo pipefail

PA_WORK_DIR="/tmp/proxmox-agent-install"
PA_BRANCH="${PA_BRANCH:-main}"
PA_REPO_SLUG="${PA_REPO_SLUG:-ruhanirabin/proxmox-agent}"
PA_INSTALL_MODE="${PA_INSTALL_MODE:-auto}"
PA_BANNER_FILE=""
PA_CAN_COLOR=0

if [ -t 1 ]; then
  PA_CAN_COLOR=1
fi

if [ "$PA_CAN_COLOR" -eq 1 ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_BLUE=$'\033[34m'
else
  C_RESET=""
  C_BOLD=""
  C_CYAN=""
  C_GREEN=""
  C_YELLOW=""
  C_RED=""
  C_BLUE=""
fi

ICON_INFO="[i]"
ICON_OK="[+]"
ICON_WARN="[!]"
ICON_ERR="[x]"
ICON_STEP="[>]"
ICON_Q="[?]"

ui_info() { echo "${C_CYAN}${ICON_INFO}${C_RESET} $*" >&2; }
ui_ok() { echo "${C_GREEN}${ICON_OK}${C_RESET} $*" >&2; }
ui_warn() { echo "${C_YELLOW}${ICON_WARN}${C_RESET} $*" >&2; }
ui_err() { echo "${C_RED}${ICON_ERR}${C_RESET} $*" >&2; }
ui_step() { echo "${C_BLUE}${ICON_STEP}${C_RESET} $*" >&2; }
ui_title() { echo "${C_BOLD}$*${C_RESET}" >&2; }

die() { ui_err "$*"; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

progress_line() {
  local current="$1"
  local total="$2"
  local label="$3"
  local width=30
  local filled=$((current * width / total))
  local percent=$((current * 100 / total))
  local done_bar todo_bar
  done_bar="$(printf '%*s' "$filled" '' | tr ' ' '=')"
  todo_bar="$(printf '%*s' "$((width - filled))" '' | tr ' ' ' ')"
  printf '\r%s[%s>%s] %3d%% %s%s' "$C_BLUE" "$done_bar" "$todo_bar" "$percent" "$label" "$C_RESET"
  if [ "$current" -eq "$total" ]; then
    printf '\n'
  fi
}

run_with_spinner() {
  local label="$1"
  shift
  local pid spin='|/-\' i=0
  "$@" >/tmp/pa-installer-cmd.out 2>/tmp/pa-installer-cmd.err &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf '\r%s[%c]%s %s' "$C_BLUE" "${spin:$i:1}" "$C_RESET" "$label" >&2
    sleep 0.1
  done
  wait "$pid"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '\r%s%s%s %s\n' "$C_GREEN" "$ICON_OK" "$C_RESET" "$label" >&2
  else
    printf '\r%s%s%s %s\n' "$C_RED" "$ICON_ERR" "$C_RESET" "$label" >&2
    cat /tmp/pa-installer-cmd.err >&2 || true
    cat /tmp/pa-installer-cmd.out >&2 || true
  fi
  rm -f /tmp/pa-installer-cmd.out /tmp/pa-installer-cmd.err
  return "$rc"
}

prompt() {
  local p="$1"
  local default="${2:-}"
  local answer
  if [ -n "$default" ]; then
    read -r -p "${ICON_Q} ${p} [${default}]: " answer
    echo "${answer:-$default}"
  else
    read -r -p "${ICON_Q} ${p}: " answer
    echo "$answer"
  fi
}

prompt_yes_no() {
  local p="$1"
  local default="${2:-y}"
  local answer
  while true; do
    if [ "$default" = "y" ]; then
      read -r -p "${ICON_Q} ${p} [Y/n]: " answer
      answer="${answer:-y}"
    else
      read -r -p "${ICON_Q} ${p} [y/N]: " answer
      answer="${answer:-n}"
    fi
    case "$(echo "$answer" | tr '[:upper:]' '[:lower:]')" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
  done
}

resolve_banner_file() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  if [ -f "$script_dir/assets/installer-banner.txt" ]; then
    PA_BANNER_FILE="$script_dir/assets/installer-banner.txt"
    return 0
  fi

  mkdir -p "$PA_WORK_DIR"
  local banner_url="https://raw.githubusercontent.com/${PA_REPO_SLUG}/${PA_BRANCH}/assets/installer-banner.txt"
  local banner_path="$PA_WORK_DIR/installer-banner.txt"
  if curl -fsSL "$banner_url" -o "$banner_path" >/dev/null 2>&1; then
    PA_BANNER_FILE="$banner_path"
    return 0
  fi
  return 1
}

print_intro() {
  resolve_banner_file || true
  if [ -n "${PA_BANNER_FILE:-}" ] && [ -f "$PA_BANNER_FILE" ]; then
    echo >&2
    cat "$PA_BANNER_FILE" >&2
    echo >&2
  fi
  ui_title "Proxmox Agent Guided Installer"
  ui_info "This installer will validate host prerequisites, detect old installs,"
  ui_info "fetch source, and run a guided proxmox-agent install."
  echo >&2
}

preflight() {
  [ "$(id -u)" -eq 0 ] || die "Run as root."
  local c missing=0
  for c in bash curl tar git ssh ssh-keygen; do
    if command -v "$c" >/dev/null 2>&1; then
      ui_ok "dependency: $c"
    else
      ui_err "dependency missing: $c"
      missing=1
    fi
  done
  if [ "${PA_TEST_MODE:-false}" = "true" ]; then
    ui_warn "PA_TEST_MODE=true -> skipping hard dependency check for systemctl."
  else
    if command -v systemctl >/dev/null 2>&1; then
      ui_ok "dependency: systemctl"
    else
      ui_err "dependency missing: systemctl"
      missing=1
    fi
  fi
  [ "$missing" -eq 0 ] || die "Install blocked due to missing dependencies."
}

detect_existing() {
  if [ -f /usr/local/bin/pa-agent-version ]; then
    # shellcheck disable=SC1091
    source /usr/local/bin/pa-agent-version || true
    ui_info "Detected canonical install: v${AGENT_VERSION:-unknown}"
  elif [ -f /usr/local/bin/proxmox-agent-version ]; then
    # shellcheck disable=SC1091
    source /usr/local/bin/proxmox-agent-version || true
    ui_warn "Detected legacy install: v${AGENT_VERSION:-unknown}"
  else
    ui_info "No existing installed version file detected."
  fi

  if compgen -G "/etc/systemd/system/backup-config.*" >/dev/null || \
     [ -f /etc/systemd/system/proxmox-bootup-telegram.service ] || \
     [ -f /etc/systemd/system/shutdown-proxmox.service ]; then
    ui_warn "Legacy unit names detected; migration will run automatically."
  fi
}

fetch_source() {
  rm -rf "$PA_WORK_DIR"
  mkdir -p "$PA_WORK_DIR"

  if [ -x "./bin/proxmox-agent" ] && [ -f "./VERSION" ] && [ "$PA_INSTALL_MODE" != "remote" ]; then
    ui_ok "Using local repository source."
    echo "$(pwd)"
    return 0
  fi

  if [ -z "$PA_REPO_SLUG" ]; then
    PA_REPO_SLUG="$(prompt "Enter GitHub repo slug (owner/repo)")"
  fi
  [ -n "$PA_REPO_SLUG" ] || die "Repo slug is required."

  local archive="$PA_WORK_DIR/src.tgz"
  local url="https://codeload.github.com/${PA_REPO_SLUG}/tar.gz/refs/heads/${PA_BRANCH}"
  ui_step "Downloading source archive..."
  run_with_spinner "Download ${PA_REPO_SLUG}@${PA_BRANCH}" curl -fsSL "$url" -o "$archive" || die "Failed to download source archive."

  ui_step "Extracting source archive..."
  run_with_spinner "Extract archive" tar -xzf "$archive" -C "$PA_WORK_DIR" || die "Failed to extract source archive."

  local srcdir
  srcdir="$(find "$PA_WORK_DIR" -maxdepth 3 -type f -name proxmox-agent | head -n 1 | xargs dirname)"
  [ -n "$srcdir" ] || die "Could not locate bin/proxmox-agent in extracted archive."
  echo "$(cd "$srcdir/.." && pwd)"
}

main() {
  local total=6
  local step=0

  print_intro

  step=$((step + 1)); progress_line "$step" "$total" "Preflight checks"
  preflight

  step=$((step + 1)); progress_line "$step" "$total" "Detect existing install"
  detect_existing

  step=$((step + 1)); progress_line "$step" "$total" "Fetch installer source"
  local src_root
  src_root="$(fetch_source)"
  ui_info "Source root: $src_root"

  step=$((step + 1)); progress_line "$step" "$total" "Prepare installer binary"
  [ -x "$src_root/bin/proxmox-agent" ] || chmod +x "$src_root/bin/proxmox-agent"

  step=$((step + 1)); progress_line "$step" "$total" "Preinstall simulation report"
  ui_step "Generating simulation report..."
  (cd "$src_root" && ./bin/proxmox-agent preinstall-report) || true

  step=$((step + 1)); progress_line "$step" "$total" "Run guided install"
  if ! prompt_yes_no "Proceed with installation changes on this host?" "n"; then
    ui_warn "Installer aborted before making changes."
    exit 0
  fi
  ui_step "Starting proxmox-agent install..."
  (cd "$src_root" && ./bin/proxmox-agent install)

  ui_ok "Installer finished successfully."
}

main "$@"
