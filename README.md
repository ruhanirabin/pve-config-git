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
  - `pcg preinstall-report [--json]` (alias: `pcg pcg-doctor`)
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

## Preinstall simulation

Run this before installation or an upgrade to inspect the planned changes.

```bash
pcg preinstall-report
pcg preinstall-report --json
# subcommand alias
pcg pcg-doctor
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

Timer, CLI and shutdown backups record their final result under the `pcg-backup` journal tag. A `backup_success` event confirms that the branch push completed. A `backup_failed` event includes the failure phase and exit status.

Run these as root on the Proxmox host. The commands show today's outcomes, filter failures, and follow new events as they arrive.

```bash
journalctl -t pcg-backup --since today --no-pager
journalctl -t pcg-backup -p err --since today --no-pager
journalctl -t pcg-backup -f
```

For detailed output from the backup service, including Git errors and systemd failures:

```bash
journalctl -u pcg-backup-config.service -n 100 --no-pager
systemctl status pcg-backup-config.service
```

Each outcome is a JSON message with these fields.

| Field | How to read it |
| --- | --- |
| `event` | `backup_success` or `backup_failed` for the whole run |
| `run_id` | Identifies one run when messages from several entry points overlap |
| `entrypoint` | `systemd`, `cli`, `shutdown`, or `manual` for direct script execution |
| `node`, `branch`, `commit` | The node, target branch and local commit involved |
| `branch_push` | `confirmed` after a successful branch push, otherwise `not_confirmed` |
| `outcome` | `changed` or `unchanged` for the collected files, or `unknown` before that check |
| `phase` | The current step, such as `collect`, `synchronize`, `push_branch`, `push_tag`, or `complete` |
| `exit_status` | `0` for success, otherwise the process exit status |

An `unchanged` run can still publish a commit left behind by an earlier failed push. A failed run with `branch_push=confirmed` and `phase=push_tag` means the branch push completed before the tag step failed. Check the local and remote tags before retrying an individual tag push. An unchanged backup retries the branch push, while tag recovery may need operator action.

Exit status `143` means the run received SIGTERM. This can happen when shutdown stops a scheduled backup. Check for a later successful `shutdown` backup before treating it as an unresolved GitHub failure. A timeout normally reports exit status `124` and network guidance.

If the tag query is empty, inspect the unit journal. Systemd can reject a missing environment file or executable before the script starts. The script also keeps its file log at `BACKUP_LOG_FILE`, which defaults to `/var/log/pcg-backup-config.log`.

Journald controls journal retention. `PCG_LOG_RETENTION_DAYS` and its overrides control PCG's file logs. Previous-boot journal history depends on the host's journald storage settings.

## Upgrades

Updates run when an operator starts them. The timer schedules configuration backups.

Run update commands as root on each Proxmox host. Keep the existing backup repository URL and local backup directory when reviewing the prompts. That repository retains its configuration history across updates.

### Guided update with the single-line installer

Use the bootstrap installer for a first update from older PCG, `pa-*`, or `proxmox-agent` installations. It runs the newly downloaded installer, including the current migration and rollback fixes.

```bash
PA_INSTALL_MODE=remote bash -c "$(curl -fsSL https://raw.githubusercontent.com/ruhanirabin/pve-config-git/main/install.sh)"
```

`PA_INSTALL_MODE=remote` forces a fresh source download even when the current directory contains an older PCG checkout. The default bootstrap can reuse a checkout containing `bin/pcg` and `VERSION`.

1. Confirm the installation request after reviewing the preinstall report.
2. If PCG is detected, choose **Reinstall** and confirm it.
3. Review the existing repository, author, retention and notification settings. Legacy settings are migrated before defaults are installed. Reconfirm the notification mode you want to use.
4. Choose **Install** at the final prompt.
5. Run the verification commands below.

The bootstrap fetches the current `main` branch. Changes become available through this command after they are merged. Tagged upgrades provide a specific version to install.

### Versioned stable upgrades

Set the following in `/root/.pcg-agent.env` once the host has the current installer and CLI:

```bash
AGENT_UPDATE_CHANNEL=stable
AGENT_UPDATE_SOURCE=https://github.com/ruhanirabin/pve-config-git.git
```

These settings refer to the PCG application source. Your configuration backup destination remains in `GIT_REMOTE_URL`.

| Setting | Purpose |
| --- | --- |
| `AGENT_UPDATE_SOURCE` | Downloads PCG code for upgrades |
| `GIT_REMOTE_URL` | Receives this host's configuration backups |
| `REPO_DIR` | Local working directory for configuration backups |

Upgrade to the highest version-sorted Git tag, or select an existing tag explicitly:

```bash
pcg upgrade --channel stable
pcg upgrade --channel stable --target v0.8.1
```

Choose one command for the update. The explicit target example requires a published `v0.8.1` tag. If the source has no tags, the stable command cannot resolve a target. Use the guided update while a tagged release is being prepared.

Stable selection uses a version-sorted tag list, which can include prerelease tags. Use `--target` to select an approved version.

### Automatic version tags

When `VERSION` changes on `main`, the **Validate and tag VERSION** GitHub Actions workflow validates the version, checks the matching changelog entry and runs the regression tests. It then creates `v<VERSION>` at that exact commit. Wait for the workflow to succeed before requesting the new tag through `pcg upgrade`.

For each release, choose the next version in `VERSION` and add its matching first entry in `docs/CHANGELOG.md`. The repository caps are `MAJOR<=30`, `MINOR<=20` and `PATCH<=30`. For example, `0.7.30` rolls over to `0.8.0`.

Pull requests run validation with read access. Tag publication runs on `main` with the built-in `GITHUB_TOKEN` and `contents: write`. A GitHub Release page can be added separately. The stable upgrader consumes the Git tag directly.

Existing tags remain fixed. A rerun succeeds if the remote tag already points to the same commit, and fails if it points elsewhere. If publication fails, inspect the workflow logs and rerun the failed job after resolving the problem. The Actions page also offers **Run workflow** for `main` to recover a missing tag at the current commit.

Documentation-only pushes with an unchanged `VERSION` do not trigger automatic tagging. If a tag already exists at an earlier commit, a manual run for a later commit with the same version fails instead of moving that tag.

### What happens during an update

The installer or upgrader snapshots managed scripts, units, the runtime version, environment files and unit enablement. It then applies the source files, reloads systemd and validates the installed runtime with doctor.

An apply or post-update doctor failure restores the managed snapshot. Install snapshots are saved under `/root/pcg-backups/install-<timestamp>/`, and upgrade snapshots under `/root/pcg-backups/upgrade-<timestamp>/`. Git history and the configuration backup working tree are separate from these snapshots.

Existing settings remain available to the installer as prompt defaults. Review them before confirming. An upgrade preserves the existing environment file, so compare it with `env/pcg-agent.env.example` when you need a newly added option.

### Verify publication after updating

```bash
pcg doctor --json
pcg backup
journalctl -t pcg-backup --since today --no-pager
systemctl status pcg-backup-config.timer
```

Doctor checks the installed files, services, authentication, repository read access and dry-run push access. A real backup verifies that the backup branch accepts publication. Look for `backup_success`, `branch_push=confirmed` and the expected commit in the journal.

### Save, resume and recovery

Choosing **Save** writes a private draft at `/root/.pcg-agent-install-draft.env` and restores the previous managed installation. Choosing **Exit** also restores the previous managed files. After a first installation is paused, the draft can remain while the CLI has been removed by restoration.

On an installation with matching cached sources, resume through the installed CLI:

```bash
pcg install --resume
```

For a transition from older versions, use a current source checkout for the resume step. From that checkout, run:

```bash
./bin/pcg install --resume
```

The bootstrap does not forward command-line options to `pcg install`. Rerunning the bootstrap offers to load an existing draft, which is another way to continue.

If an update fails, read the reported snapshot path and run doctor again. Upgrade metadata is written to `/var/log/pcg-upgrade.log`. PCG has no public `rollback` command. Automatic restoration handles failed application or validation. For a deliberate return to an older tagged version, select that tag with `pcg upgrade --channel stable --target <previous-tag>`, then verify it again.

### Update quirks

- `pcg install` uses its checkout or matching local source cache. To download newer code, use the remote bootstrap or `pcg upgrade`.
- Older installations may have no cache under `/usr/local/share/pcg/sources/`. Use the current bootstrap or a current checkout for their first migration.
- If the selected source's `VERSION` matches the installed version, `pcg upgrade` reports that it is up to date. Use guided reinstallation if you need to repair files for the same version.
- Run one install or upgrade session at a time on a node. The bootstrap shares `/tmp/pcg-install`, and maintenance sessions change the same installed files.
- Git network operations run without credential prompts. A key that works only in your interactive SSH agent may be unavailable to the backup service. Configure access for root's systemd environment and verify the service itself.
- APT may report subscription errors for Proxmox enterprise feeds. During VM testing, Git still installed from the available Debian indexes. Review package-manager errors if a required command remains missing.
- Default script backups now collect the managed PCG files. Add other scripts explicitly through `BACKUP_INCLUDE_EXTRA`, after checking them for credentials. Older Git commits can retain files collected by earlier versions.
- Choosing **Do it later** saves notification placeholders. Replace those values before expecting Telegram or webhook delivery.

### Edge source archives

The edge channel expects an archive URL in `AGENT_UPDATE_SOURCE`. Set an archive source in the runtime environment file before an edge update:

```bash
AGENT_UPDATE_CHANNEL=edge
AGENT_UPDATE_SOURCE=https://github.com/ruhanirabin/pve-config-git/archive/refs/heads/main.tar.gz
```

Then run:

```bash
pcg upgrade --channel edge
```

Changing `--channel` alone does not convert a stable Git URL into an archive URL. A `.tar.gz` source uses the required `tar` command. A `.zip` source also needs `unzip`. Restore the stable channel and Git source settings when returning to tagged updates.

## Legacy migration

During migration, the installer preserves legacy settings and disables the older timers and services. It removes the legacy scripts and units after validation succeeds.

For an older node's first migration, use the guided remote update above. After it completes, verify `pcg doctor --json` and a real backup on that node.

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

Installed reinstall and resume use versioned source payloads under `/usr/local/share/pcg/sources/`. The cache contains managed source files and the example template. See the upgrade recovery instructions for older installations and saved drafts.

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
