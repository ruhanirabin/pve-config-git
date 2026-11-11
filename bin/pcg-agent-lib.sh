#!/bin/bash

set -o pipefail

PCG_ENV_FILE_DEFAULT="/root/.pcg-agent.env"
PCG_ENV_FILE_LEGACY="/root/.backup-config.env"
PCG_VERSION_FILE="/usr/local/bin/pcg-agent-version"
PCG_VERSION_FILE_LEGACY="/usr/local/bin/proxmox-agent-version"

# Keep unattended operations bounded and never expose raw credential-bearing errors.
pcg_network_timeout() {
  local value="${GIT_TIMEOUT_SECONDS:-60}"
  [[ "$value" =~ ^[1-9][0-9]{0,3}$ ]] && [ "$value" -le 3600 ] || {
    echo 'GIT_TIMEOUT_SECONDS must be between 1 and 3600.' >&2
    return 1
  }
  printf '%s' "$value"
}

pcg_git_error() {
  local code="$1" file="$2"
  PCG_GIT_ERROR="Git operation failed. Check the repository URL, credentials and network, then run pcg doctor."
  if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
    PCG_GIT_ERROR="Git operation timed out. Check DNS, network access and credential helpers; adjust GIT_TIMEOUT_SECONDS if needed."
  elif grep -Eqi 'REMOTE HOST IDENTIFICATION HAS CHANGED|Host key verification failed' "$file"; then
    PCG_GIT_ERROR="SSH host verification failed. Verify GitHub's host key and root's known_hosts entry before retrying."
  elif grep -Eqi 'Permission denied \(publickey\)|no supported authentication methods' "$file"; then
    PCG_GIT_ERROR="SSH authentication failed. Add this node's root public key to GitHub and allow unattended use of the matching private key."
  elif grep -Eqi 'Could not resolve|Name or service not known|Connection timed out|Connection refused|Network is unreachable|Failed to connect|Could not read from remote repository' "$file"; then
    PCG_GIT_ERROR="Cannot connect to the Git repository. Check DNS, firewall, GitHub availability and SSH access from this node."
  elif grep -Eqi 'Repository not found|does not appear to be a git repository|not found' "$file"; then
    PCG_GIT_ERROR="Repository not found or not accessible. Check OWNER/REPO, that the repository exists, and that these credentials can access it."
  elif grep -Eqi 'Authentication failed|could not read Username|could not read Password|terminal prompts disabled|Invalid username or (password|token)|401' "$file"; then
    PCG_GIT_ERROR="HTTPS authentication failed or requires interaction. Configure a root credential helper with unattended credentials that can write this repository, or use SSH."
  elif grep -Eqi 'write access.*not granted|permission.*denied.*to|read.only|not allowed to push' "$file"; then
    PCG_GIT_ERROR="Repository write access denied. Grant this key or token write access and check organization authorization and repository rules."
  elif grep -Eqi '403|permission.*denied|access denied' "$file"; then
    PCG_GIT_ERROR="Repository access denied. Check key or token permissions, organization authorization and repository rules."
  elif grep -Eqi 'non-fast-forward|fetch first|rejected|protected branch|GH006|GH013' "$file"; then
    PCG_GIT_ERROR="Push rejected. Check branch protection, repository rules and remote changes; resolve conflicts before retrying the backup."
  elif grep -Eqi 'conflict|cannot rebase|unstaged changes' "$file"; then
    PCG_GIT_ERROR="Git synchronization needs attention. Resolve working-tree changes or rebase conflicts before retrying the backup."
  fi
}

pcg_git_network() {
  local seconds errors rc=0
  PCG_GIT_ERROR=""
  seconds="$(pcg_network_timeout)" || {
    PCG_GIT_ERROR="GIT_TIMEOUT_SECONDS must be between 1 and 3600."
    return 1
  }
  command -v timeout >/dev/null || {
    PCG_GIT_ERROR="Missing dependency: timeout (coreutils). Install it before running PCG network operations."
    echo "$PCG_GIT_ERROR" >&2
    return 1
  }
  errors="$(mktemp)" || return 1
  # Preserve root's SSH config, but disable passwords/passphrases and GUI prompts.
  # No raw remote output reaches logs: Git can echo embedded credentials in URLs.
  if LC_ALL=C GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
    GIT_ASKPASS=/bin/false SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=never \
    GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ConnectionAttempts=1' \
    timeout --kill-after=5 "$seconds" git -c credential.interactive=false "$@" </dev/null 2>"$errors"; then
    rm -f "$errors"
    return 0
  else
    rc=$?
  fi
  pcg_git_error "$rc" "$errors"
  rm -f "$errors"
  echo "$PCG_GIT_ERROR" >&2
  return "$rc"
}

# Read-only write-endpoint probe, including repositories with no commits yet.
# --dry-run does not execute server receive hooks or guarantee branch-rule acceptance.
pcg_git_check_push() (
  local repo="$1" work oid objects
  work="$(mktemp -d)" || exit 1
  trap 'rm -rf "$work"' EXIT
  objects="$(git -C "$repo" rev-parse --git-path objects)" || exit 1
  [[ "$objects" = /* ]] || objects="$(cd "$repo" && pwd)/$objects"
  mkdir "$work/objects" || exit 1
  # Use the real repository's transport/credential config without adding objects,
  # commits, refs, index entries or remote branches to the backup repository.
  export GIT_OBJECT_DIRECTORY="$work/objects"
  export GIT_ALTERNATE_OBJECT_DIRECTORIES="$objects"
  oid="$(printf '' | git -C "$repo" hash-object -t tree -w --stdin)" || exit 1
  oid="$(printf 'PCG access check (dry run only)\n' | \
    GIT_AUTHOR_NAME=PCG GIT_AUTHOR_EMAIL=pcg@localhost \
    GIT_COMMITTER_NAME=PCG GIT_COMMITTER_EMAIL=pcg@localhost \
    git -C "$repo" -c commit.gpgSign=false commit-tree "$oid")" || exit 1
  pcg_git_network -C "$repo" push --dry-run --no-verify --porcelain origin \
    "$oid:refs/heads/pcg-access-check-${work##*.}" > /dev/null
)

pcg_now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

pcg_bool_true() {
  local v
  v="$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [[ "$v" == "1" || "$v" == "true" || "$v" == "yes" || "$v" == "on" ]]
}

pcg_json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

pcg_ui_init() {
  PCG_UI_C_RESET=""
  PCG_UI_C_BOLD=""
  PCG_UI_C_CYAN=""
  PCG_UI_C_GREEN=""
  PCG_UI_C_YELLOW=""
  PCG_UI_C_RED=""
  PCG_UI_C_BLUE=""

  PCG_UI_ICON_INFO="[i]"
  PCG_UI_ICON_OK="[+]"
  PCG_UI_ICON_WARN="[!]"
  PCG_UI_ICON_ERR="[x]"
  PCG_UI_ICON_STEP="[>]"
  PCG_UI_ICON_Q="[?]"

  local can_color=0
  if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ] && [ "${TERM:-}" != "dumb" ]; then
    can_color=1
  fi

  if [ "$can_color" -eq 1 ]; then
    PCG_UI_C_RESET=$'\033[0m'
    PCG_UI_C_BOLD=$'\033[1m'
    PCG_UI_C_CYAN=$'\033[36m'
    PCG_UI_C_GREEN=$'\033[32m'
    PCG_UI_C_YELLOW=$'\033[33m'
    PCG_UI_C_RED=$'\033[31m'
    PCG_UI_C_BLUE=$'\033[34m'
  fi

  if [ -t 1 ] && [ "${PCG_UI_ASCII:-}" != "1" ] && locale charmap 2>/dev/null | grep -qi "utf-8"; then
    PCG_UI_ICON_INFO="ℹ"
    PCG_UI_ICON_OK="✔"
    PCG_UI_ICON_WARN="⚠"
    PCG_UI_ICON_ERR="✖"
    PCG_UI_ICON_STEP="➤"
    PCG_UI_ICON_Q="❯"
  fi
}

pcg_ui_info() { echo "${PCG_UI_C_CYAN}${PCG_UI_ICON_INFO}${PCG_UI_C_RESET} $*"; }
pcg_ui_ok() { echo "${PCG_UI_C_GREEN}${PCG_UI_ICON_OK}${PCG_UI_C_RESET} $*"; }
pcg_ui_warn() { echo "${PCG_UI_C_YELLOW}${PCG_UI_ICON_WARN}${PCG_UI_C_RESET} $*"; }
pcg_ui_err() { echo "${PCG_UI_C_RED}${PCG_UI_ICON_ERR}${PCG_UI_C_RESET} $*" >&2; }
pcg_ui_step() { echo "${PCG_UI_C_BLUE}${PCG_UI_ICON_STEP}${PCG_UI_C_RESET} $*"; }
pcg_ui_title() { echo "${PCG_UI_C_BOLD}$*${PCG_UI_C_RESET}"; }

pcg_load_version() {
  AGENT_VERSION="unknown"
  if [ -f "$PCG_VERSION_FILE" ]; then
    # shellcheck disable=SC1090
    source "$PCG_VERSION_FILE" || true
    return 0
  fi
  if [ -f "$PCG_VERSION_FILE_LEGACY" ]; then
    # shellcheck disable=SC1090
    source "$PCG_VERSION_FILE_LEGACY" || true
  fi
}

pcg_load_env() {
  local source_rc
  local had_errexit=0
  [[ $- == *e* ]] && had_errexit=1
  local source_err_file
  pcg_source_env_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    source_err_file="$(mktemp)"
    # shellcheck disable=SC1090
    set +e
    source "$file" 2>"$source_err_file"
    source_rc=$?
    if [ "$had_errexit" -eq 1 ]; then set -e; else set +e; fi
    if [ "$source_rc" -ne 0 ]; then
      echo "[!] Warning: failed to fully parse $file (rc=$source_rc). Continue with loaded values and fix invalid lines." >&2
      if [ -s "$source_err_file" ]; then
        sed -n '1,3p' "$source_err_file" >&2 || true
      fi
    fi
    rm -f "$source_err_file"
  }

  if [ -n "${ENV_FILE:-}" ]; then
    pcg_source_env_file "$ENV_FILE"
    return 0
  fi

  if [ -f "$PCG_ENV_FILE_DEFAULT" ]; then
    ENV_FILE="$PCG_ENV_FILE_DEFAULT"
  elif [ -f "$PCG_ENV_FILE_LEGACY" ]; then
    ENV_FILE="$PCG_ENV_FILE_LEGACY"
  else
    ENV_FILE="$PCG_ENV_FILE_DEFAULT"
  fi

  pcg_source_env_file "$ENV_FILE"
}

pcg_log_retention_days() {
  local raw="${1:-${PCG_LOG_RETENTION_DAYS:-14}}"
  if [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -ge 1 ]; then
    echo "$raw"
  else
    echo "14"
  fi
}

pcg_rotate_log_family() {
  local log_file="$1"
  local retention_input="${2:-}"
  local retention_days
  local log_dir log_base

  retention_days="$(pcg_log_retention_days "$retention_input")"
  log_dir="$(dirname "$log_file")"
  log_base="$(basename "$log_file")"

  mkdir -p "$log_dir"
  # Daily shutdown filenames share one retention family.
  if [[ "$log_base" == shutdown_????-??-??.log ]]; then
    log_base="shutdown_"
  elif [ -f "$log_file" ]; then
    local today modified
    today="$(date +%F)"
    modified="$(date -r "$log_file" +%F)"
    if [ "$modified" != "$today" ]; then
      mv "$log_file" "$log_file.$modified.$(date +%s).$$" || return 1
    fi
  fi
  find "$log_dir" -maxdepth 1 -type f -name "${log_base}*" -mtime +"$retention_days" -exec rm -f {} \; 2>/dev/null || true
}

pcg_event_enabled() {
  local event="${1:-}"
  local configured list
  configured="${WEBHOOK_EVENTS:-install,doctor,backup,shutdown}"
  configured="$(echo "$configured" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
  [ -z "$configured" ] && return 1
  [ "$configured" = "*" ] && return 0
  IFS=',' read -r -a list <<< "$configured"
  for item in "${list[@]}"; do
    [ "$item" = "$event" ] && return 0
  done
  return 1
}

pcg_send_webhook() {
  local event status summary details node ts enabled url token timeout retries payload try delay auth_header
  event="${1:-}"
  status="${2:-unknown}"
  summary="${3:-}"
  details="${4:-}"
  node="${5:-$(hostname -s 2>/dev/null || hostname)}"
  ts="$(pcg_now_utc)"

  enabled="${WEBHOOK_ENABLED:-false}"
  url="${WEBHOOK_URL:-}"
  token="${WEBHOOK_BEARER_TOKEN:-}"
  timeout="${WEBHOOK_TIMEOUT_SECONDS:-10}"
  retries="${WEBHOOK_MAX_RETRIES:-3}"

  pcg_bool_true "$enabled" || return 0
  [ -n "$url" ] || return 0
  pcg_event_enabled "$event" || return 0

  payload=$(
    cat <<EOF
{"schema_version":"1","event_type":"$(pcg_json_escape "$event")","timestamp":"$ts","node":"$(pcg_json_escape "$node")","status":"$(pcg_json_escape "$status")","summary":"$(pcg_json_escape "$summary")","details":"$(pcg_json_escape "$details")","agent_version":"$(pcg_json_escape "${AGENT_VERSION:-unknown}")"}
EOF
  )

  try=1
  delay=1
  while [ "$try" -le "$retries" ]; do
    auth_header=()
    if [ -n "$token" ]; then
      auth_header=(-H "Authorization: Bearer $token")
    fi

    if curl -fsS --max-time "$timeout" -X POST "$url" \
      -H "Content-Type: application/json" \
      "${auth_header[@]}" \
      --data "$payload" >/dev/null 2>&1; then
      return 0
    fi

    [ "$try" -eq "$retries" ] && break
    sleep "$delay"
    delay=$((delay * 2))
    try=$((try + 1))
  done

  return 1
}
