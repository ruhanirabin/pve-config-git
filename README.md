# Proxmox (PVE) Config Git
[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Q5Q2100Q59)

> **Quick Links:** [Changelog](docs/CHANGELOG.md) • [License](LICENSE)

PCG (Proxmox Config Git) is a lightweight Bash + systemd toolkit that **backs up your Proxmox host configuration files to GitHub** — giving you a complete history of every change made to your node setup.

## ⚠️ Important: What This Tool Does (And Doesn't Do)

**This tool backs up CONFIGURATION FILES, not your virtual machines.**

| This Tool DOES | This Tool DOES NOT |
|----------------|-------------------|
| ✅ Backup Proxmox config files (`/etc/pve/`, `/etc/network/interfaces`, etc.) | ❌ Backup VM/LXC disk images or container files |
| ✅ Track changes to your node setup over time in Git | ❌ Create full system images for disaster recovery |
| ✅ Let you see WHO changed WHAT and WHEN | ❌ Replace traditional VM backup solutions |
| ✅ Help you rollback configuration mistakes | ❌ Backup your actual VMs or their data |

**Why this matters:** If you accidentally break your network config or delete a storage pool, this tool lets you see exactly what changed and restore the working config. But if your VM's hard drive corrupts, you'll need a proper VM backup solution (like Proxmox Backup Server or `vzdump`).

**The original idea:** I made this so I can go back in time and see what was changed on my Proxmox configuration using Git. Think of it as "version control for your server setup."

---

## What it helps with

- Tracks Proxmox host config changes over time in Git.
- Automatically commits and pushes only when changes exist.
- Runs on both periodic timer and shutdown trigger.
- Sends notifications to Telegram and/or webhook endpoints.
- Migrates older legacy naming (`backup-config*`, `shutdown-proxmox*`, etc.) to canonical `pcg-*` names.
- Provides `doctor` and preinstall simulation reporting for safer operations.

## Key features

- Canonical `pcg-*` runtime naming for scripts, units, env, and logs.
- Single runtime version source: `/usr/local/bin/pcg-agent-version` generated from repo `VERSION`.
- Guided installer flow (`install.sh`) with preflight checks and confirmation gate.
- Lifecycle CLI:
  - `pcg install [--resume|--clear-draft]`
  - `pcg doctor [--json]`
  - `pcg preinstall-report [--json]` (alias: `pcg-doctor`)
  - `pcg backup`
  - `pcg notify [message]`
  - `pcg uninstall`
  - `pcg upgrade [--channel stable|edge] [--target <tag>]`
- Automatic backup/rollback safety during install and upgrade.

## Requirements (Read This Before Installing)

Before you run the installer, make sure you have ALL of the following ready:

### 1. GitHub Repository (Empty Repo Ready)

You need a **private GitHub repository** created and waiting. This is where your Proxmox config will be stored.

- Go to GitHub → Create a new repository → Make it **private**
- **Do NOT initialize it with a README, .gitignore, or license** — leave it completely empty
- The installer will set this up as your backup destination
- Example URL: `git@github.com:yourusername/proxmox-config-backup.git`

### 2. SSH Key Authentication (Proxmox VE Shell)

**You must run the installer from the Proxmox VE shell** (not from inside a VM or container). This is the actual host node's command line.

#### Step-by-step SSH Setup for Beginners:

1. **Open the Proxmox VE Shell:**
   - In the Proxmox web UI, click on your node name (left sidebar)
   - Click "Shell" to open a terminal to the actual host
   - **Important:** You cannot SSH into a VM and run this — it must be the Proxmox host itself

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
   ```bash
   ssh -T git@github.com
   # You should see: "Hi username! You've successfully authenticated..."
   ```

**Note:** Each Proxmox node needs its own SSH key added to GitHub if you're backing up multiple nodes.

### 3. Notification Method Ready (Required)

You MUST have at least one notification method configured. The installer will ask for this.

#### Option A: Telegram Bot (Easiest for Most Users)

1. **Create a bot with BotFather:**
   - Open Telegram and message [@BotFather](https://t.me/botfather)
   - Send `/newbot` and follow prompts
   - Save the **bot token** (looks like: `123456789:ABCdefGHIjklMNOpqrSTUvwxyz`)

2. **Get Your Chat ID:**
   - Message your new bot once to start it
   - Visit: `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
   - Look for `"chat":{"id":12345678` — that number is your **chat ID**

3. **You'll enter these during installation:**
   - Bot Token: `123456789:ABCdefGHIjklMNOpqrSTUvwxyz`
   - Chat ID: `12345678`

#### Option B: Webhook Endpoint

If you have your own notification system (Discord, Slack, n8n, etc.), prepare:
- Webhook URL where notifications should be sent
- Bearer token if your webhook requires authentication

### 4. Basic System Requirements

- Proxmox VE host with root shell access
- `bash`, `curl`, `git`, `ssh`, `ssh-keygen`, `tar` (usually pre-installed)
- `systemctl` (required for live install; skipped only in `PCG_TEST_MODE=true`)
- Internet access from your Proxmox node to reach GitHub

---

## Installation

### One-liner bootstrap (guided)

**Remember:** Run this in the Proxmox VE shell, not inside a VM/LXC.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/pve-config-git/main/install.sh)"
```

The guided bootstrap will:

1. Run dependency preflight.
2. Detect existing/legacy install.
3. Run a read-only simulation report.
4. Ask for explicit confirmation before mutating the host.
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
- Notification mode (`telegram`, `webhook`, `both`) - at least one is required
- Telegram values (`BOT_TOKEN`, `CHAT_ID`) if selected
- Webhook URL/token if selected

At final confirmation, you can choose:

- `install` (apply and continue)
- `save` (save draft and continue later)
- `exit` (abort without applying)

Draft settings are saved at `/root/.pcg-agent-install-draft.env`.

If an existing install is detected, installer shows an early action menu:

- `Reinstall`
- `Uninstall`
- `Exit without making changes`

Use explicit draft controls:

```bash
pcg install --resume
pcg install --clear-draft
pcg uninstall
```

It also validates GitHub SSH auth and helps users retry after adding public keys.
SSH auth checks are enforced only when `GIT_REMOTE_URL` is SSH; HTTPS remotes are allowed and skip SSH validation.

## Console UI

Installer and CLI status messages use a shared color/icon system with automatic fallback.

- UTF-8 terminal: icon cues (for example `ℹ`, `✔`, `⚠`, `✖`)
- Non-UTF-8 terminal: ASCII cues (`[i]`, `[+]`, `[!]`, `[x]`)

Controls:

- `NO_COLOR=1` disables ANSI colors
- `PCG_UI_ASCII=1` forces ASCII icons

## Preflight simulation (`pcg-doctor`)

Use this before installing/upgrading to see what will change.

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
- GitHub SSH auth + Git remote reachability
- Notification config sanity

Non-zero exit means hard failure.

## Runtime layout

Installed runtime paths:

- Scripts: `/usr/local/bin/pcg-*.sh`
- CLI: `/usr/local/bin/pcg`
- Version: `/usr/local/bin/pcg-agent-version`
- Env: `/root/.pcg-agent.env`
- Units: `/etc/systemd/system/pcg-*.service|timer`
- Backups (rollback snapshots): `/root/pcg-agent-backups/<timestamp>/`

## Configuration

Primary config file: `/root/.pcg-agent.env`

Template source: `env/pcg-agent.env.example`

Important variables:

- `REPO_DIR`, `REPO_BRANCH`, `GIT_REMOTE_URL`
- `GIT_COMMIT_NAME`, `GIT_COMMIT_EMAIL`
- `BACKUP_INCLUDE_EXTRA`
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

## Scheduled + shutdown behavior

- `pcg-backup-config.timer` triggers periodic backups via `pcg-backup-config.service`.
- `pcg-shutdown-proxmox.service` runs graceful VM/LXC/host shutdown with pre-shutdown backup.
- Shutdown script invocation supports:
  - systemd service execution
  - explicit SSH/manual trigger with `--execute`
- Duplicate shutdown runs are blocked with a lock file guard.
- Shutdown aborts safely when host uptime is under 5 minutes (boot protection).
- `pcg-boot-notify.service` can send boot notifications.

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

For comprehensive testing with Docker:

```bash
cd tests
./run-tests.sh              # Ubuntu mode (default, Windows compatible)
./run-tests.sh --pve-mode   # Real PVE container (Linux only)
```

**What it tests**: Doctor/preinstall-report, installation flow, backup script execution, 
and shutdown script hardening (flock, shutdown-state detection).

**Windows Compatibility**: The PVE container (`ghcr.io/longqt-sea/proxmox-ve`) requires Linux 
cgroups and does NOT work on Windows Docker. Use the default Ubuntu mode for Windows, which 
tests script syntax, structure, and hardening without requiring real PVE.

For full PVE testing on Windows, consider WSL2, a Linux VM, or CI environments.

See [`tests/README.md`](tests/README.md) for detailed usage and platform-specific guidance.

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
  - Re-run `pcg install` and then `pcg doctor` to complete migration cleanup.

## Security notes

- Secret files are excluded by default from backup collection.
- Webhook bearer tokens are supported for outbound webhook auth.
- Keep `/root/.pcg-agent.env` at mode `600`.

## Development notes

- Source of truth version: `VERSION`
- Runtime version file is generated from `VERSION` during install/upgrade.
- End-user changelog: `docs/CHANGELOG.md`
- Contributor and automation rules: `AGENTS.md`

## License

MIT License. See [LICENSE](LICENSE).
