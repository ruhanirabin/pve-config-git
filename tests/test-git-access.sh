#!/bin/bash
# Local repositories plus deterministic transport failures; no external accounts.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
export T
fail() { echo "FAIL: $*" >&2; exit 1; }
LIB_FILE="$ROOT_DIR/bin/pcg-agent-lib.sh"
source <(sed '$d' "$ROOT_DIR/bin/pcg")
export GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null
export REAL_GIT="$(command -v git)" REAL_SLEEP="$(command -v sleep)"
git init -q --bare "$T/remote"
git init -q -b main "$T/repo"
git -C "$T/repo" remote add origin "$T/remote"
export REPO_DIR="$T/repo"
pcg_load_env() { :; }
# Before HEAD exists: read and dry-run push both work without changing anything.
find "$T/repo/.git" -type f -exec sha256sum {} \; | sort > "$T/before"
validate_git_remote_access 1 || fail 'empty repository rejected'
find "$T/repo/.git" -type f -exec sha256sum {} \; | sort > "$T/after"
cmp "$T/before" "$T/after" || fail 'doctor modified local repository'
[[ -z "$(git --git-dir="$T/remote" for-each-ref)" ]] || fail 'probe created remote refs'
# Root's repository-local credential/transport configuration must be retained.
git -C "$T/repo" config pcg.test-marker retained
mkdir "$T/mocks"
cat > "$T/mocks/git" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' ls-remote '* || " $* " == *' push '* || " $* " == *' pull '* || " $* " == *' clone '* ]]; then
  [[ "$GIT_TERMINAL_PROMPT" == 0 && "$GCM_INTERACTIVE" == Never ]]
  [[ "$GIT_SSH_COMMAND" == *BatchMode=yes* && "$GIT_SSH_COMMAND" == *ConnectTimeout=10* ]]
  [[ "$*" == *credential.interactive=false* ]]
  if read -r unexpected; then echo 'consumed installer input' >&2; exit 87; fi
  case "${MOCK_MODE:-}" in
    ssh) echo 'Permission denied (publickey). SECRET_SENTINEL' >&2; exit 128 ;;
    https) echo 'fatal: could not read Username for https://SECRET_SENTINEL@github.com: terminal prompts disabled' >&2; exit 128 ;;
    missing) echo 'remote: Repository not found. SECRET_SENTINEL' >&2; exit 128 ;;
    dns) echo 'Could not resolve host: github.com SECRET_SENTINEL' >&2; exit 128 ;;
    hostkey) echo 'Host key verification failed. SECRET_SENTINEL' >&2; exit 128 ;;
    protected) echo 'remote: GH013: protected branch SECRET_SENTINEL' >&2; exit 1 ;;
    sleep) exec "$REAL_SLEEP" 10 ;;
    readonly)
      if [[ " $* " == *' push '* ]]; then
        echo 'remote: Write access to repository not granted. SECRET_SENTINEL' >&2
        exit 128
      fi ;;
  esac
  if [[ " $* " == *' push '* ]]; then
    [[ "$*" == *--dry-run* && "$*" == *--no-verify* ]]
    [[ "$($REAL_GIT -C "$REPO_DIR" config pcg.test-marker)" == retained ]]
    echo called > "$T/push-probed"
  fi
fi
exec "$REAL_GIT" "$@"
MOCK
chmod +x "$T/mocks/git"
export PATH="$T/mocks:$PATH"
validate_git_remote_access 1 || fail 'unattended wrapper configuration'
[[ -f "$T/push-probed" ]] || fail 'push check not run'
for pair in 'ssh:SSH authentication failed' 'https:HTTPS authentication failed' 'missing:Repository not found or not accessible' 'dns:Cannot connect' 'hostkey:SSH host verification failed' 'readonly:write access denied' 'protected:Push rejected'; do
  export MOCK_MODE="${pair%%:*}"
  expected="${pair#*:}"
  if validate_git_remote_access 1 > "$T/output" 2>&1; then fail "accepted $MOCK_MODE"; fi
  [[ "$PCG_REMOTE_ERROR" == *"$expected"* ]] || fail "wrong diagnostic for $MOCK_MODE: $PCG_REMOTE_ERROR"
  [[ "$PCG_REMOTE_ERROR" != *SECRET_SENTINEL* ]] || fail 'secret leaked in doctor result'
  ! grep -q SECRET_SENTINEL "$T/output" || fail 'secret leaked to console'
done
# Doctor's JSON carries the sanitized write failure, rather than claiming that
# a successful ls-remote proves backup access.
export MOCK_MODE=readonly
PCG_ENV_TARGET="$T/config.env"
: > "$PCG_ENV_TARGET"
GIT_REMOTE_URL=https://github.com/example/backup.git
pcg_load_version() { AGENT_VERSION=test; }
pcg_send_webhook() { :; }
if cmd_doctor --json > "$T/doctor.json" 2> "$T/doctor.stderr"; then fail 'doctor accepted denied write access'; fi
python3 - <<'CHECK'
import json,os
from pathlib import Path
p=Path(os.environ['T'])
r=json.loads((p/'doctor.json').read_text())
check=next(x for x in r['results'] if x['key']=='git_remote')
assert not r['ok'] and check['status']=='fail'
assert 'write access denied' in check['message']
assert 'SECRET_SENTINEL' not in (p/'doctor.json').read_text()+(p/'doctor.stderr').read_text()
CHECK
# Slow helpers/network cannot wait indefinitely or consume the installer answers.
export MOCK_MODE=sleep GIT_TIMEOUT_SECONDS=1
start=$SECONDS
if pcg_git_network ls-remote https://github.com/example/private.git > "$T/output" 2>&1; then fail 'timeout reported success'; fi
[[ $((SECONDS-start)) -lt 8 && "$PCG_GIT_ERROR" == *'timed out'* ]] || fail 'timeout not enforced'
export GIT_TIMEOUT_SECONDS=0
if pcg_git_network ls-remote example > "$T/output" 2>&1; then fail 'zero timeout accepted'; fi
unset MOCK_MODE GIT_TIMEOUT_SECONDS
# --dry-run cannot discover receive-hook rejection: keep that boundary explicit.
cat > "$T/remote/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$T/remote/hooks/pre-receive"
validate_git_remote_access 1 || fail 'dry run unexpectedly executed server hook'
[[ -z "$(git --git-dir="$T/remote" for-each-ref)" ]] || fail 'dry run altered remote'
# GitHub uses exit 1 even for successful SSH authentication. Do not mistake
# that status for failure, or accept a timed-out greeting as success.
cat > "$T/mocks/ssh" <<'SSH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == *BatchMode=yes* && "$*" == *ConnectTimeout=10* ]]
case "${MOCK_SSH_MODE:-success}" in
  success) echo "Hi test! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1 ;;
  key) echo 'Permission denied (publickey). SECRET_SENTINEL' >&2; exit 255 ;;
  slow) exec "$REAL_SLEEP" 10 ;;
esac
SSH
chmod +x "$T/mocks/ssh"
is_test_mode() { return 1; }
validate_github_ssh || fail 'GitHub exit 1 greeting rejected'
export MOCK_SSH_MODE=key
if validate_github_ssh > "$T/output" 2>&1; then fail 'missing key accepted'; fi
grep -q 'SSH authentication failed' "$T/output" || fail 'SSH guidance missing'
! grep -q SECRET_SENTINEL "$T/output" || fail 'raw SSH error leaked'
export MOCK_SSH_MODE=slow GIT_TIMEOUT_SECONDS=1
if validate_github_ssh > "$T/output" 2>&1; then fail 'SSH timeout accepted'; fi
grep -q 'timed out' "$T/output" || fail 'SSH timeout guidance missing'
unset MOCK_SSH_MODE GIT_TIMEOUT_SECONDS
echo 'Unattended Git, dry-run access, safe errors and timeout regressions: PASS'
