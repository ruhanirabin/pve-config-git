## 0.7.5

- improve: beautify installer and CLI user prompts with iconized status output for clearer guidance.
- feat: add startup ASCII banner loading from `assets/installer-banner.txt` in guided installer flow.
- feat: add single-line animated progress UI (progress bar + spinner) for installer phase feedback.

## 0.7.4

- improve: add configurable log retention for all `pa-*` custom logs with global and per-script overrides.
- improve: standardize runtime log cleanup through shared helper logic to keep retention behavior consistent.
- improve: document version-sync rules so `VERSION`, changelog release headers, and runtime version generation stay aligned.
- feat: add guided bootstrap installer (`install.sh`) for curl-pipe installation flow with preflight and source fetch prompts.
- improve: expand `proxmox-agent install` to provide clearer preflight output, prior-install detection, and missing remote guidance.

## 0.7.3

- improve: normalize managed artifact naming to canonical `pa-*` for scripts, units, env, and runtime version files.
- feat: add automatic legacy-node migration during `proxmox-agent install` and `proxmox-agent upgrade`.
- fix: prevent duplicate old/new unit scheduling by stopping and disabling legacy units during migration.
- feat: add rollback-safe migration snapshots for install and upgrade under `/root/proxmox-agent-backups/`.
- improve: add doctor migration visibility with explicit legacy artifact status reporting.
- improve: standardize runtime log naming to `pa-*` paths for easier operations monitoring.

## 0.7.2

- feat: add lifecycle CLI: `proxmox-agent install|doctor|backup|notify|upgrade`.
- feat: add unified runtime version file: `/usr/local/bin/pa-agent-version`.
- feat: add shared library: `pa-agent-lib.sh` for env/version/webhook helpers.
- feat: add generic webhook sender with Bearer auth and retry: `pa-send-webhook.sh`.
- feat: add `doctor --json` machine-readable health checks.
- feat: add upgrade flow with `stable` (tag) and `edge` (raw URL) channels.
- improve: add safe upgrade rollback using backups under `/root/proxmox-agent-backups/<timestamp>/`.
- improve: update backup flow to explicit allowlist and default secret exclusion.
- improve: update shutdown flow to run a pre-shutdown backup and send webhook events.
- improve: update unit files to run scripts from `/usr/local/bin`.
