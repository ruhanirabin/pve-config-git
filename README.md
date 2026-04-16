# Proxmox Agent

Proxmox Agent is a lightweight Bash + systemd toolkit that snapshots important Proxmox host configuration into your private Git repository, on schedule and on shutdown, with optional Telegram/Webhook notifications.

It is designed for operators who want a practical change-history trail for node config without standing up a full backup platform.

## What it helps with

- Tracks Proxmox host config changes over time in Git.
- Automatically commits and pushes only when changes exist.
- Runs on both periodic timer and shutdown trigger.
- Sends notifications to Telegram and/or webhook endpoints.
- Migrates older legacy naming (`backup-config*`, `shutdown-proxmox*`, etc.) to canonical `pa-*` names.
- Provides `doctor` and preinstall simulation reporting for safer operations.

## Key features

- Canonical `pa-*` runtime naming for scripts, units, env, and logs.
- Single runtime version source: `/usr/local/bin/pa-agent-version` generated from repo `VERSION`.
- Guided installer flow (`install.sh`) with preflight checks and confirmation gate.
- Lifecycle CLI:
  - `proxmox-agent install [--resume|--clear-draft]`
  - `proxmox-agent doctor [--json]`
  - `proxmox-agent preinstall-report [--json]` (alias: `pa-doctor`)
  - `proxmox-agent backup`
  - `proxmox-agent notify [message]`
  - `proxmox-agent uninstall`
  - `proxmox-agent upgrade [--channel stable|edge] [--target <tag>]`
- Automatic backup/rollback safety during install and upgrade.

## Requirements

- Proxmox VE host with root shell access.
- `bash`, `curl`, `git`, `ssh`, `ssh-keygen`, `tar`.
- `systemctl` (required for live install; skipped only in `PA_TEST_MODE=true`).
- A reachable Git remote (SSH recommended).

## Installation

### One-liner bootstrap (guided)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/proxmox-agent/main/install.sh)"
```

The guided bootstrap will:

1. Run dependency preflight.
2. Detect existing/legacy install.
3. Run a read-only simulation report.
4. Ask for explicit confirmation before mutating the host.
5. Launch guided `proxmox-agent install`.

### Local repo install

```bash
git clone https://github.com/ruhanirabin/proxmox-agent.git
cd proxmox-agent
sudo ./bin/proxmox-agent install
```

## Guided install behavior

`proxmox-agent install` is interactive and will prompt for:

- Backup repo path (`REPO_DIR`)
- Branch (`REPO_BRANCH`)
- Git remote URL (`GIT_REMOTE_URL`)
- Git commit author full name (`GIT_COMMIT_NAME`)
- Git commit author email (`GIT_COMMIT_EMAIL`)
- Log retention days (`PA_LOG_RETENTION_DAYS`)
- Notification mode (`telegram`, `webhook`, `both`) - at least one is required
- Telegram values (`BOT_TOKEN`, `CHAT_ID`) if selected
- Webhook URL/token if selected

At final confirmation, you can choose:

- `install` (apply and continue)
- `save` (save draft and continue later)
- `exit` (abort without applying)

Draft settings are saved at `/root/.pa-agent-install-draft.env`.

If an existing install is detected, installer shows an early action menu:

- `Reinstall`
- `Uninstall`
- `Exit without making changes`

Use explicit draft controls:

```bash
proxmox-agent install --resume
proxmox-agent install --clear-draft
proxmox-agent uninstall
```

It also validates GitHub SSH auth and helps users retry after adding public keys.
SSH auth checks are enforced only when `GIT_REMOTE_URL` is SSH; HTTPS remotes are allowed and skip SSH validation.

## Console UI

Installer and CLI status messages use a shared color/icon system with automatic fallback.

- UTF-8 terminal: icon cues (for example `ℹ`, `✔`, `⚠`, `✖`)
- Non-UTF-8 terminal: ASCII cues (`[i]`, `[+]`, `[!]`, `[x]`)

Controls:

- `NO_COLOR=1` disables ANSI colors
- `PA_UI_ASCII=1` forces ASCII icons

## Preflight simulation (`pa-doctor`)

Use this before installing/upgrading to see what will change.

```bash
proxmox-agent preinstall-report
proxmox-agent preinstall-report --json
# alias
pa-doctor
```

Report includes:

- Current install state (none/legacy/canonical)
- Installed version and env source
- Planned actions installer will apply
- Blockers (missing deps, missing remote URL)
- Warnings (auth issues, etc.)

## Doctor health checks

```bash
proxmox-agent doctor
proxmox-agent doctor --json
```

Checks include:

- Required binaries and executable scripts
- Runtime version file presence
- Env file presence
- Canonical systemd unit enable/active state
- Legacy artifact detection status
- GitHub SSH auth + Git remote reachability
- Notification config sanity

Non-zero exit means hard failure.

## Runtime layout

Installed runtime paths:

- Scripts: `/usr/local/bin/pa-*.sh`
- CLI: `/usr/local/bin/proxmox-agent`
- Version: `/usr/local/bin/pa-agent-version`
- Env: `/root/.pa-agent.env`
- Units: `/etc/systemd/system/pa-*.service|timer`
- Backups (rollback snapshots): `/root/proxmox-agent-backups/<timestamp>/`

## Configuration

Primary config file: `/root/.pa-agent.env`

Template source: `env/pa-agent.env.example`

Important variables:

- `REPO_DIR`, `REPO_BRANCH`, `GIT_REMOTE_URL`
- `GIT_COMMIT_NAME`, `GIT_COMMIT_EMAIL`
- `BACKUP_INCLUDE_EXTRA`
- `BOT_TOKEN`, `CHAT_ID`
- `WEBHOOK_ENABLED`, `WEBHOOK_URL`, `WEBHOOK_BEARER_TOKEN`
- `WEBHOOK_EVENTS` (`install,doctor,backup,shutdown` by default)
- `WEBHOOK_TIMEOUT_SECONDS`, `WEBHOOK_MAX_RETRIES`
- `PA_LOG_RETENTION_DAYS`
- Optional per-log overrides:
  - `BACKUP_LOG_RETENTION_DAYS`
  - `TELEGRAM_LOG_RETENTION_DAYS`
  - `BOOT_NOTIFY_LOG_RETENTION_DAYS`
  - `SHUTDOWN_LOG_RETENTION_DAYS`
- Upgrade controls:
  - `AGENT_UPDATE_CHANNEL=stable|edge`
  - `AGENT_UPDATE_SOURCE=<git-url-or-raw-archive-url>`

## Scheduled + shutdown behavior

- `pa-backup-config.timer` triggers periodic backups via `pa-backup-config.service`.
- `pa-shutdown-proxmox.service` runs graceful VM/LXC/host shutdown with pre-shutdown backup.
- Shutdown script invocation supports:
  - systemd service execution
  - explicit SSH/manual trigger with `--execute`
- Duplicate shutdown runs are blocked with a lock file guard.
- Shutdown aborts safely when host uptime is under 5 minutes (boot protection).
- `pa-boot-notify.service` can send boot notifications.

## Upgrades

```bash
proxmox-agent upgrade --channel stable --target v0.7.8
proxmox-agent upgrade --channel edge
```

Upgrade flow:

1. Snapshot current managed files.
2. Fetch target source.
3. Apply canonical files.
4. Re-enable canonical units.
5. Run post-upgrade doctor.
6. Roll back automatically on failure.

## Legacy migration

Legacy names are auto-detected and migrated during `install` and `upgrade`.

After successful migration, legacy artifacts are removed to prevent duplicate timers/services.

For already-deployed older nodes, run once per node:

```bash
proxmox-agent install
```

## Test mode (safe lab runs)

Use `PA_TEST_MODE=true` to relax `systemctl` and GitHub SSH enforcement for local/container testing.

```bash
PA_TEST_MODE=true ./bin/proxmox-agent preinstall-report
PA_TEST_MODE=true ./bin/proxmox-agent doctor
```

### Automated Test Suite

For comprehensive testing with a real Proxmox VE environment:

```bash
cd tests
./run-tests.sh
```

This uses Docker with the `ghcr.io/longqt-sea/proxmox-ve` image to test:
- Doctor/preinstall-report functionality
- Installation flow
- Backup script execution
- Shutdown script hardening (flock, shutdown-state detection)

See `tests/README.md` for detailed usage.

### Quick smoke test (Ubuntu)

For a lightweight installer flow check on generic Ubuntu:

```bash
tests/docker-guided-smoke.sh
```

## Troubleshooting

- `GitHub SSH authentication failed`
  - Confirm the exact public key on the current node (`/root/.ssh/id_ed25519.pub`) is added to your GitHub account.
  - Old keys from other nodes/containers do not satisfy this host.
- `git_remote unreachable`
  - Verify `GIT_REMOTE_URL` and SSH access: `ssh -T git@github.com` and `git -C "$REPO_DIR" ls-remote origin`.
- Duplicate legacy/canonical units
  - Re-run `proxmox-agent install` and then `proxmox-agent doctor` to complete migration cleanup.

## Security notes

- Secret files are excluded by default from backup collection.
- Webhook bearer tokens are supported for outbound webhook auth.
- Keep `/root/.pa-agent.env` at mode `600`.

## Development notes

- Source of truth version: `VERSION`
- Runtime version file is generated from `VERSION` during install/upgrade.
- End-user changelog: `docs/CHANGELOG.md`
- Contributor and automation rules: `AGENTS.md`

## License

MIT License. See [LICENSE](LICENSE).
