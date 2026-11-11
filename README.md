# Proxmox (PVE) Config Git
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q2100Q59)

> **Quick Links:** [Changelog](docs/CHANGELOG.md) • [License](LICENSE)

PCG (Proxmox Config Git) uses Bash and systemd to **back up selected Proxmox host configuration files to GitHub**. Git keeps a history so you can inspect changes and recover earlier configurations.

## Configuration backups, not VM backups

PCG backs up configuration files. It does not back up VM or LXC disks and data.

| This Tool DOES | This Tool DOES NOT |
|----------------|-------------------|
| ✅ Back up Proxmox config files (`/etc/pve/`, `/etc/network/interfaces`, etc.) | ❌ Back up VM/LXC disk images or container files |
| ✅ Track changes to your node setup over time in Git | ❌ Create full system images for disaster recovery |
| ✅ Show who changed what and when | ❌ Replace traditional VM backup solutions |
| ✅ Help you roll back configuration mistakes | ❌ Back up your actual VMs or their data |

If a configuration change breaks your network or storage setup, the Git history helps you find the change and recover an earlier config. Recovering VM disks or data requires a separate backup, such as Proxmox Backup Server or `vzdump`.

I made this because I wanted to look back through Git and see what had changed in my Proxmox configuration.

---

## What it helps with

- Tracks Proxmox host config changes over time in Git.
- Commits configuration changes and pushes them to GitHub. Runs with no new changes still retry unpublished commits.
- Runs on a timer and before shutdown.
- Sends notifications through Telegram, webhooks, or both.
- Migrates older naming (`backup-config*`, `shutdown-proxmox*`, etc.) to canonical `pcg-*` names.
- Provides `doctor` health checks and a read-only preinstall report.

## Key features

- Canonical `pcg-*` runtime naming for scripts, units, env, and logs.
- Single runtime version source: `/usr/local/bin/pcg-agent-version` generated from repo `VERSION`.
- Guided installer (`install.sh`) with prerequisite checks and confirmation before installation.
- Lifecycle CLI:
  - `pcg install [--resume|--clear-draft]`
  - `pcg doctor [--json]`
  - `pcg preinstall-report [--json]` (alias: `pcg-doctor`)
  - `pcg backup`
  - `pcg notify [message]`
  - `pcg uninstall`
  - `pcg upgrade [--channel stable|edge] [--target <tag>]`
- Snapshots managed files before installation and upgrades, then restores them if validation fails.

## Requirements

Run the installer on the Proxmox host as root. Prepare a GitHub repository and choose how you want to receive notifications.

### 1. Private GitHub repository

Create a **private GitHub repository** for your configuration backups before installing.

- Go to GitHub → Create a new repository → Make it **private**
- Leave it empty. Do not initialize it with a README, .gitignore, or license.
- The installer will set this up as your backup destination
- Example URL: `git@github.com:yourusername/proxmox-config-backup.git`

### 2. GitHub authentication from the Proxmox host

**Run the installer from the Proxmox host shell**, not inside a VM or container. For an SSH remote, add the host's public key to GitHub. HTTPS remotes skip SSH validation but still need credentials that allow unattended Git access.

#### Set up SSH access

1. **Open the Proxmox VE Shell:**
   - In the Proxmox web UI, click on your node name (left sidebar)
   - Click "Shell" to open a terminal to the actual host
   - Check that the shell belongs to the host node.

2. **Generate an SSH Key (if you don't have one):**
   ```bash
   ssh-keygen -t ed25519 -C "proxmox-backup"
   # Press Enter to accept default location (no passphrase needed for automation)
   ```

3. **Copy Your Public Key:**
   ```bash
   cat /root/.ssh/id_ed25519.pub
   ```
   Copy the entire output (starts with `ssh-ed25519`)

4. **Add Key to GitHub:**
   - Go to GitHub → Settings → SSH and GPG keys → New SSH key
   - Title: "Proxmox Backup"
   - Paste the key you copied
   - Click "Add SSH key"

5. **Test the Connection:**

   Run this in the Proxmox host shell:

   ```bash
   ssh -T git@github.com
   # You should see: "Hi username! You've successfully authenticated..."
   ```

For multiple nodes, add each node's own SSH public key to GitHub.

### 3. Notification settings

Choose Telegram, a webhook, or both. You can also choose **Do it later** during installation. That saves placeholder values, which you must replace before using notifications.

#### Option A: Telegram bot

1. **Create a bot with BotFather:**
   - Open Telegram and message [@BotFather](https://t.me/botfather)
   - Send `/newbot` and follow prompts
   - Save the **bot token** (looks like: `123456789:ABCdefGHIjklMNOpqrSTUvwxyz`)

2. **Get Your Chat ID:**
   - Message your new bot once to start it
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Look for `"chat":{"id":12345678`. That number is your **chat ID**.

3. **You'll enter these during installation:**
   - Bot Token: `123456789:ABCdefGHIjklMNOpqrSTUvwxyz`
   - Chat ID: `12345678`

#### Option B: Webhook Endpoint

For a notification system that accepts PCG webhook events, prepare:
- Webhook URL where notifications should be sent
- Bearer token if your webhook requires authentication

### 4. Host dependencies

- Proxmox VE host with root shell access
- `bash`, `curl`, `git`, `ssh`, `ssh-keygen`, `tar`, `find`, `install`, `flock`, `crontab`, `timeout` and `logger`
- Proxmox commands `qm` and `pct` for guest operations
- `systemctl` (required for live install; skipped only in `PCG_TEST_MODE=true`)
- Internet access from your Proxmox node to reach GitHub

---

## Installation

### One-liner bootstrap (guided)

Run this in the Proxmox host shell.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/pve-config-git/main/install.sh)"
```

The guided bootstrap will:

1. Check prerequisites.
2. Detect an existing or legacy installation.
3. Run a read-only simulation report.
4. Ask for confirmation before applying installation changes.
5. Launch guided `pcg install`.

### Local repo install

```bash
git clone https://github.com/ruhanirabin/pve-config-git.git
cd pve-config-git
sudo ./bin/pcg install
```

## Guided install behavior

`pcg install` is interactive and will prompt for:

- Backup repo path (`REPO_DIR`)
- Branch (`REPO_BRANCH`)
- Git remote URL (`GIT_REMOTE_URL`)
- Git commit author full name (`GIT_COMMIT_NAME`)
- Git commit author email (`GIT_COMMIT_EMAIL`)
- Log retention days (`PCG_LOG_RETENTION_DAYS`)
- Notification mode (`telegram`, `webhook`, `both`, or `later`)
- Telegram values (`BOT_TOKEN`, `CHAT_ID`) if selected
- Webhook URL/token if selected

At final confirmation, you can choose:

- `install` (apply and continue)
- `save` (save draft and continue later)
- `exit` (abort without applying)

Draft settings are saved at `/root/.pcg-agent-install-draft.env`.

If an existing installation is detected, you first choose:

- `Reinstall`
- `Uninstall`
- `Exit without making changes`

Use explicit draft controls:

```bash
pcg install --resume
pcg install --clear-draft
pcg uninstall
```

For SSH remotes, the installer checks GitHub authentication and lets you retry after adding the public key. HTTPS remotes skip this SSH check. Guided installation currently accepts GitHub.com repositories only.

### Unattended repository access

Installation and `pcg doctor` check repository read access and run a dry-run push. The push probe uses temporary local Git objects and a temporary branch name, but it does not create a remote branch or change your local commits, index or working files. It works with an empty repository too.

A successful dry run confirms access to the write endpoint. It does not run server hooks or prove that the backup branch's protection rules will accept a real push. The first successful `pcg backup` is still needed to verify publication.

Git network commands cannot ask for a username, password or SSH passphrase. For SSH, use a key available to root without interaction, including any required agent setup for the systemd service. For HTTPS, configure a root credential helper with credentials that can write to the backup repository. Do not put tokens in the remote URL.

Each Git network command has a 60-second timeout, followed by a five-second termination grace period. Set `GIT_TIMEOUT_SECONDS` in the runtime env file to adjust the limit. SSH connection attempts also have a ten-second connection timeout. These limits apply to checks, backup pulls/pushes and Git-based upgrades.

If an access check fails, installation reports the problem and restores its managed files. Doctor returns a failure with the same guidance in plain text or JSON. Errors distinguish SSH authentication, HTTPS credentials, inaccessible repositories, network failures, timeouts and rejected pushes where Git provides enough detail. A private repository can appear as “not found” when credentials lack access, so that message asks you to check both the URL and permissions.

## Console UI

The installer and CLI use colors and icons when the terminal supports them.

- UTF-8 terminal: icons such as `ℹ`, `✔`, `⚠`, `✖`
- Non-UTF-8 terminal: ASCII cues (`[i]`, `[+]`, `[!]`, `[x]`)

Controls:

- `NO_COLOR=1` disables ANSI colors
- `PCG_UI_ASCII=1` forces ASCII icons

## Preflight simulation (`pcg-doctor`)

Run this before installation or an upgrade to inspect the planned changes.

```bash
pcg preinstall-report
pcg preinstall-report --json
# alias
pcg-doctor
```

Report includes:

- Current install state (none/legacy/canonical)
- Installed version and env source
- Planned actions installer will apply
- Blockers (missing deps, missing remote URL)
- Warnings (auth issues, etc.)

## Doctor health checks

```bash
pcg doctor
pcg doctor --json
```

Checks include:

- Required binaries and executable scripts
- Runtime version file presence
- Env file presence
- Canonical systemd unit enable/active state
- Legacy artifact detection status
- GitHub SSH authentication, unattended repository read access and dry-run push access
- Notification config sanity

A nonzero exit status means at least one health check failed. A successful doctor run does not prove that a backup or shutdown has completed successfully.

## Runtime layout

Installed runtime paths:

- Scripts: `/usr/local/bin/pcg-*.sh`
- CLI: `/usr/local/bin/pcg`
- Version: `/usr/local/bin/pcg-agent-version`
- Env: `/root/.pcg-agent.env`
- Units: `/etc/systemd/system/pcg-*.service|timer`
- Rollback snapshots: `/root/pcg-backups/install-<timestamp>/`, `upgrade-<timestamp>/` or `uninstall-<timestamp>/`
- Cached installer sources: `/usr/local/share/pcg/sources/<version>/`

## Configuration

Primary config file: `/root/.pcg-agent.env`

Template source: `env/pcg-agent.env.example`

Important variables:

- `REPO_DIR`, `REPO_BRANCH`, `GIT_REMOTE_URL`
- `GIT_COMMIT_NAME`, `GIT_COMMIT_EMAIL`
- `BACKUP_INCLUDE_EXTRA` (additional absolute paths, separated by commas)
- `BACKUP_LOCK_TIMEOUT_SECONDS` (defaults to 120 seconds)
- `GIT_TIMEOUT_SECONDS` (defaults to 60 seconds per network command; allowed range 1–3600)
- `BOT_TOKEN`, `CHAT_ID`
- `WEBHOOK_ENABLED`, `WEBHOOK_URL`, `WEBHOOK_BEARER_TOKEN`
- `WEBHOOK_EVENTS` (`install,doctor,backup,shutdown` by default)
- `WEBHOOK_TIMEOUT_SECONDS`, `WEBHOOK_MAX_RETRIES`
- `PCG_LOG_RETENTION_DAYS`
- Optional per-log overrides:
  - `BACKUP_LOG_RETENTION_DAYS`
  - `TELEGRAM_LOG_RETENTION_DAYS`
  - `BOOT_NOTIFY_LOG_RETENTION_DAYS`
  - `SHUTDOWN_LOG_RETENTION_DAYS`
- Upgrade controls:
  - `AGENT_UPDATE_CHANNEL=stable|edge`
  - `AGENT_UPDATE_SOURCE=<git-url-or-raw-archive-url>`

### Which scripts are backed up?

By default, PCG collects only its own CLI and managed scripts from `/usr/local/bin`. **Other scripts are not included automatically.** Add each extra script's absolute path to `BACKUP_INCLUDE_EXTRA`, separated by commas. Review its contents for embedded credentials first.

VM and LXC definitions, firewall settings and custom systemd units are refreshed on every backup, including deletions. Earlier Git commits still retain historical content.

## Scheduled backups and shutdown

- `pcg-backup-config.timer` triggers periodic backups via `pcg-backup-config.service`.
- `pcg-shutdown-proxmox.service` runs graceful VM/LXC/host shutdown with pre-shutdown backup.
- Shutdown script invocation supports:
  - systemd service execution
  - explicit SSH/manual trigger with `--execute`
- Duplicate shutdown runs are blocked with a lock file guard.
- Shutdown aborts safely when host uptime is under 5 minutes (boot protection).
- `pcg-boot-notify.service` can send boot notifications.

### Backup results in the journal

Timer, CLI and shutdown backups record their final result under the `pcg-backup` journal tag. A `backup_success` event confirms that the branch push completed. A `backup_failed` event includes the failure phase and exit status. Each event also records the node, branch, commit and entry point.

View all outcomes or failures only:

```bash
journalctl -t pcg-backup --since today --no-pager
journalctl -t pcg-backup -p err --since today --no-pager
```

For the detailed output of systemd backup runs:

```bash
journalctl -u pcg-backup-config.service -n 100 --no-pager
```

The script also keeps its file log at `BACKUP_LOG_FILE`, which defaults to `/var/log/pcg-backup-config.log`. If a push fails, check the journal's `phase` and `branch_push` fields. A tag failure can occur after the branch commit has already reached GitHub.

## Upgrades

```bash
pcg upgrade --channel stable --target v0.7.8
pcg upgrade --channel edge
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
pcg install
```

## Test mode (safe lab runs)

Use `PCG_TEST_MODE=true` to relax `systemctl` and GitHub SSH enforcement for local/container testing.

```bash
PCG_TEST_MODE=true ./bin/pcg preinstall-report
PCG_TEST_MODE=true ./bin/pcg doctor
```

### Automated Test Suite

Run the container test suite with Docker:

```bash
cd tests
./run-tests.sh              # Ubuntu mode (default, Windows compatible)
./run-tests.sh --pve-mode   # Real PVE container (Linux only)
```

The suite checks doctor/preinstall reports, file staging, backup collection and retry behavior, locking, and mocked shutdown behavior. The separate guided smoke test checks installation and Save/Resume.

The PVE container (`ghcr.io/longqt-sea/proxmox-ve`) requires Linux cgroups and does not work on Windows Docker. Use the default Ubuntu mode on Windows. Container and mock tests do not establish that the scripts work on a real Proxmox host.

For full PVE testing on Windows, consider WSL2, a Linux VM, or CI environments.

See [`tests/README.md`](tests/README.md) for detailed usage and platform-specific guidance.

### Quick smoke test (Ubuntu)

Check guided installation, installed reinstall, Save/Resume and doctor in Ubuntu:

```bash
tests/docker-guided-smoke.sh
```

## Troubleshooting

- `GitHub SSH authentication failed`
  - Confirm the exact public key on the current node (`/root/.ssh/id_ed25519.pub`) is added to your GitHub account.
  - Old keys from other nodes/containers do not satisfy this host.
- HTTPS authentication failure
  - Configure credentials for root that work without a prompt. Check repository write permission and any organization authorization requirements.
- Repository not found or not accessible
  - Check `GIT_REMOTE_URL`, confirm that the repository exists, and verify the key or token has access to it.
- Repository write access denied
  - Read access alone is not enough. Grant the key or token write access, then rerun `pcg doctor`.
- Git operation timed out
  - Check DNS, firewall, GitHub availability and credential helpers. Increase `GIT_TIMEOUT_SECONDS` only if the connection is healthy but slow.
- Push rejected
  - Check the backup branch's protection rules and remote changes. Resolve conflicts before retrying.
- Duplicate legacy/canonical units
  - Re-run `pcg install` and then `pcg doctor` to complete migration cleanup.

Installed reinstall and resume use versioned source payloads under `/usr/local/share/pcg/sources/`. Older installations without that cache must run `install.sh` from a checkout once. On a first installation, choosing Save restores the previous files, so resume from the checkout with `sudo ./bin/pcg install --resume`. The cache keeps the managed source files and example template for rollback. It does not contain the private runtime environment.

Logs rotate on the first invocation after the date changes. Retention removes both rotated logs and the complete dated shutdown log family. A long-running process keeps its open log until it finishes.

## Security notes

- Backup requires mounted `/etc/pve/lxc` and `/etc/pve/qemu-server` directories, Git, and `flock` from util-linux. A missing configuration directory fails the run and preserves the previous collection.
- Timer, manual and shutdown backups share a repository lock. `BACKUP_LOCK_TIMEOUT_SECONDS` defaults to 120. A clean collection still retries publishing local commits.
- Existing staged changes or interrupted rebases need operator resolution before another backup can run.
- Webhook bearer tokens are supported for outbound webhook auth.
- Keep `/root/.pcg-agent.env` at mode `600`.

## Development notes

- Source of truth version: `VERSION`
- Runtime version file is generated from `VERSION` during install/upgrade.
- End-user changelog: `docs/CHANGELOG.md`
- Contributor and automation rules: `AGENTS.md`

## License

MIT License. See [LICENSE](LICENSE).
