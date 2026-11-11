# AGENTS.md - PCG (Proxmox Config Git) Contributor & Automation Guide

This file defines operating rules for humans and automation (agents/bots) working on this repository.

## Project Snapshot

- Product: PCG — Proxmox (PVE) Config Git (shell + systemd lifecycle automation)
- Goal: safe config backup lifecycle with install/doctor/upgrade operations
- Runtime target: Proxmox host (Linux, systemd, root-managed scripts)

## Core Goals

- Keep changes safe, reviewable, and reversible.
- Preserve node stability during backup/shutdown/upgrade flows.
- Ensure releases are predictable with clear changelog and commit hygiene.
- Avoid silent failures in backup, webhook, and notification paths.

## Canonical Interfaces

- CLI entrypoint: `pcg`
- Guided bootstrap installer entrypoint: `install.sh`
- Supported commands:
  - `install`
  - `doctor [--json]`
  - `preinstall-report [--json]` (read-only simulation)
  - `backup`
  - `notify [message]`
  - `upgrade [--channel stable|edge] [--target <tag>]`

## Versioning Rules (Authoritative)

- Single source of truth version file in repo root: `VERSION`.
- Runtime version file generated at install/upgrade:
  - `/usr/local/bin/pcg-agent-version`
  - exports `AGENT_VERSION`.
- Scripts must read `AGENT_VERSION`; do not maintain separate per-script semantic versions.
- Version format is fixed: `MAJOR.MINOR.PATCH`.
- Version rollover caps (authoritative):
  - `PATCH` max: `30`
  - `MINOR` max: `20`
  - `MAJOR` max: `30`
- Rollover behavior:
  - If next `PATCH` would exceed `30`, set `PATCH=0` and increment `MINOR`.
  - If next `MINOR` would exceed `20`, set `MINOR=0`, set `PATCH=0`, and increment `MAJOR`.
  - If `MAJOR` would exceed `30`, treat as out-of-range and stop for manual version policy decision.
- Examples:
  - `0.7.30` -> `0.8.0`
  - `0.20.30` -> `1.0.0`
- Version sync policy for meaningful releases (feature/fix/improve/removed):
  - Update `VERSION` first.
  - Add a matching top entry in `docs/CHANGELOG.md` (newest-first).
  - Ensure runtime writer in `bin/pcg` (`write_runtime_version`) is unchanged and still emits the new version into `/usr/local/bin/pcg-agent-version`.
  - Script headers should remain agnostic (`runtime sourced from pcg-agent-version`) and must not hardcode static version numbers.

## SilverBullet Project Record

After meaningful workstation maintenance, build, recovery, bootloader, desktop
configuration, or project-documentation milestones, follow the canonical
[`silverbullet-project-docs` skill](/home/rabin/.agents/skills/silverbullet-project-docs/SKILL.md).
Its MCP workflow is the primary access method; local paths below do not override
that priority.

Use the configured SilverBullet MCP connection to the live Homelab space first.
Read the space's `AGENTS.md` and relevant notes through MCP, then update:

- `Projects/PVE Config Git`
- `Journal/Daily/YYYY-MM-DD`

Follow the skill's revision-safe preview/write/read-back procedure. Preserve
frontmatter and `[[Wiki Links]]`, and verify both the project page and dated
backlink after editing. Follow its generated-content protections, writing style,
evidence requirements, and page structure.

Only if MCP is unavailable or fails, report the access failure and use the
authorized local-folder fallback under `/home/rabin/remote-sync/silverbullet/`.
Read its `AGENTS.md` before editing the corresponding `.md` files. If an MCP
write has an uncertain outcome, establish what was saved before applying a
local fallback; do not blindly overwrite or duplicate updates. Preserve
unrelated changes and establish how live and local copies relate before mixing
access methods. The local space is synchronized storage, not a Git checkout.
Report local save/read-back separately from live MCP verification and remote
synchronization; never infer that a local save has reached the live space.

## Naming Standard

- Canonical managed artifacts must use `pcg-*` naming.
- Scripts in `/usr/local/bin`: `pcg-*.sh` plus `pcg`.
- Systemd units in `/etc/systemd/system`: `pcg-*.service|timer`.
- Runtime env: `/root/.pcg-agent.env`.
- Legacy names are migration-only and must not be used for new implementation.

## Repo Layout

- `bin/` - executable scripts and CLI
- `systemd/` - unit files
- `env/` - environment examples/templates
- `docs/` - project docs and changelog
- `docs-imported/` - imported reference requirements

## Changelog Rules

Canonical file: `docs/CHANGELOG.md`

- Order: newest version at top.
- Audience: end users / operators.
- One-line entries under these prefixes:
  - `feat:`
  - `fix:`
  - `perf:`
  - `improve:`
  - `removed:`
- Write outcomes, not implementation internals.
- Do not include internal-only CI/build/tooling churn.
- Explicitly call out breaking changes.

Companion rules file: `docs/rules/changelog_rule.md`

## Commit Message Rules

Allowed prefixes:

- `feat:`
- `fix:`
- `perf:`
- `improve:`
- `internal:`
- `doc:`
- `removed:`
- `test:`
- `ci:`
- `build:`

Rules:

- Subject line only, target <= 72 chars.
- One logical change per commit when possible.
- Avoid ambiguous messages (`WIP`, `temp`, `misc`, `stuff`).
- Formatting-only commits use `internal:`.

Companion rules file: `docs/rules/commit_git_message_rule.md`

## Engineering Rules (Shell/Systemd)

- Use `#!/bin/bash` + `set -euo pipefail` for production scripts.
- Keep scripts idempotent where practical.
- Prefer explicit allowlists for backup sources; avoid broad secret-copy patterns.
- Never print secrets/tokens/private keys to logs.
- Use predictable log locations under `/var/log/`.
- Log retention must be operator-configurable through env:
  - global: `PCG_LOG_RETENTION_DAYS`
  - per script override: `*_LOG_RETENTION_DAYS`
- Keep unit files minimal and consistent with script paths in `/usr/local/bin`.
- `doctor` must remain non-destructive and report actionable failures.
- `upgrade` must support rollback on failed apply or failed post-upgrade doctor.

## Security & Secrets

- Never commit real credentials.
- Keep `/root/.pcg-agent.env` private (`chmod 600`).
- Exclude SSH private keys and token files from backup by default.
- Webhook auth uses Bearer token when enabled.

## Upgrade & Release Rules

- `stable` channel should prefer tagged releases.
- `edge` channel is opt-in and may track latest raw artifact.
- Install/upgrade must auto-migrate legacy artifact names on existing nodes.
- Operator migration note for existing nodes:
  - Run `pcg install` once per legacy node to establish canonical `pcg-*` baseline.
  - After baseline migration, use normal `pcg upgrade` flow.
- Every release should include:
  - updated `VERSION`
  - updated `docs/CHANGELOG.md` entry at top
  - reviewed `install.sh` bootstrap flow for first-time users
  - verification that `pcg doctor` passes on target host

## Definition of Done (Per Release)

- CLI commands function on target Proxmox host.
- Install path validates GitHub SSH auth and git remote reachability.
- Backup path commits only when changes exist.
- Shutdown path preserves graceful VM/LXC flow and pre-shutdown backup behavior.
- Webhook and Telegram failures are non-blocking but logged.
- Upgrade supports rollback and logs upgrade metadata.
