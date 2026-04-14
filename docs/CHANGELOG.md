## 0.7.18

- improve: replace final validation action input with numbered menu choices (Install, Save, Exit) while keeping text aliases supported.

## 0.7.17

- fix: prevent prompt text leakage into captured values by sending generic choice prompts to stderr.
- improve: replace notification mode input with numbered menu (Telegram, Webhook, Both, Do it later with placeholders).
- improve: support placeholder notification mode so guided install can continue with explicit placeholder values.

## 0.7.16

- improve: enforce SSH key display logic in guided setup: show existing public key, or generate keypair then show key paths and public key content.
- improve: always print private/public key file locations alongside displayed public key for GitHub copy/paste.

## 0.7.15

- fix: display (or generate then display) node OpenSSH public key during GitHub guidance, before remote URL prompt.
- improve: clarify that HTTPS can continue even if SSH key generation is skipped.

## 0.7.14

- improve: move GitHub remote selection and SSH auth/key validation earlier in guided install, before local repo directory/branch prompts.
- fix: remove duplicate late-stage SSH auth check now that validation is completed upfront during guided setup.

## 0.7.13

- improve: always display the node OpenSSH public key during guided GitHub SSH setup, generating it first if missing.
- improve: add explicit GitHub copy/paste instructions in installer output for SSH key onboarding.

## 0.7.12

- fix: validate guided `GIT_REMOTE_URL` as a proper GitHub owner/repo URL for both SSH and HTTPS formats.
- improve: remove duplicate install confirmations by using reinstall confirmation only when an existing install is detected.
- improve: show explicit local git workspace initialization/remote-configuration status near install completion.

## 0.7.11

- fix: prefer repo-local `pa-agent-lib.sh` during source-based runs so guided preinstall/install use matching library functions.
- fix: prevent `pa_ui_init: command not found` when hosts have older installed library versions and bootstrap runs newer fetched CLI code.

## 0.7.10

- feat: add resumable guided install drafts with explicit `install --resume` and `install --clear-draft` controls.
- improve: enforce final guided-install validation checklist with install/save/exit confirmation before applying settings.
- improve: allow HTTPS or SSH repository remotes while enforcing GitHub SSH checks only for SSH remotes.
- improve: add dependency auto-install prompts with package-manager-specific commands in bootstrap and CLI installers.
- improve: standardize CLI visual cues through shared color/icon UI with UTF-8 and ASCII fallback controls.

## 0.7.9

- fix: prevent duplicate boot notifications across service retries by using per-boot dedupe locks.
- fix: allow boot notification retry when Telegram send fails by writing dedupe lock only after a successful send.
- improve: harden shutdown execution path by requiring explicit systemd invocation guard and execution flag.
- improve: align shutdown service and script flow for final notification timing before host halt.

## 0.7.8

- feat: add read-only preinstall simulation command (`proxmox-agent preinstall-report` / `pa-doctor`) showing current state, planned changes, blockers, and warnings.
- improve: show simulation report in bootstrap installer flow before final confirmation.
- improve: include JSON output option for preinstall simulation report to support automation.

## 0.7.7

- feat: add guided notification setup in installer (`none`, `telegram`, `webhook`, `both`) with required value prompts.
- improve: enforce webhook URL validation and required Telegram fields during guided install.
- feat: add Docker-based non-live smoke test script for WSL2/local validation of installer flow.

## 0.7.6

- fix: prevent installer source-path corruption by isolating UI/spinner output from command-substitution output.
- improve: add mandatory confirmation gate before mutation in both bootstrap installer and `proxmox-agent install`.
- feat: add beginner-friendly install wizard for backup repo path, branch, remote URL, and log retention setup.
- improve: add guided GitHub SSH retry loop during install to help users complete authentication without manual debugging.

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
