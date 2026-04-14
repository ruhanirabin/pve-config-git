# AGENTS.md - Proxmox Agent Contributor & Automation Guide

This file defines operating rules for humans and automation (agents/bots) working on this repository.

## Project Snapshot

- Product: Proxmox Agent (shell + systemd lifecycle automation)
- Goal: safe config backup lifecycle with install/doctor/upgrade operations
- Runtime target: Proxmox host (Linux, systemd, root-managed scripts)

## Core Goals

- Keep changes safe, reviewable, and reversible.
- Preserve node stability during backup/shutdown/upgrade flows.
- Ensure releases are predictable with clear changelog and commit hygiene.
- Avoid silent failures in backup, webhook, and notification paths.

## Canonical Interfaces

- CLI entrypoint: `proxmox-agent`
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
  - `/usr/local/bin/pa-agent-version`
  - exports `AGENT_VERSION`.
- Scripts must read `AGENT_VERSION`; do not maintain separate per-script semantic versions.
- Version sync policy for meaningful releases (feature/fix/improve/removed):
  - Update `VERSION` first.
  - Add a matching top entry in `docs/CHANGELOG.md` (newest-first).
  - Ensure runtime writer in `bin/proxmox-agent` (`write_runtime_version`) is unchanged and still emits the new version into `/usr/local/bin/pa-agent-version`.
  - Script headers should remain agnostic (`runtime sourced from pa-agent-version`) and must not hardcode static version numbers.

## Naming Standard

- Canonical managed artifacts must use `pa-*` naming.
- Scripts in `/usr/local/bin`: `pa-*.sh` plus `proxmox-agent`.
- Systemd units in `/etc/systemd/system`: `pa-*.service|timer`.
- Runtime env: `/root/.pa-agent.env`.
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
  - global: `PA_LOG_RETENTION_DAYS`
  - per script override: `*_LOG_RETENTION_DAYS`
- Keep unit files minimal and consistent with script paths in `/usr/local/bin`.
- `doctor` must remain non-destructive and report actionable failures.
- `upgrade` must support rollback on failed apply or failed post-upgrade doctor.

## Security & Secrets

- Never commit real credentials.
- Keep `/root/.pa-agent.env` private (`chmod 600`).
- Exclude SSH private keys and token files from backup by default.
- Webhook auth uses Bearer token when enabled.

## Upgrade & Release Rules

- `stable` channel should prefer tagged releases.
- `edge` channel is opt-in and may track latest raw artifact.
- Install/upgrade must auto-migrate legacy artifact names on existing nodes.
- Operator migration note for existing nodes:
  - Run `proxmox-agent install` once per legacy node to establish canonical `pa-*` baseline.
  - After baseline migration, use normal `proxmox-agent upgrade` flow.
- Every release should include:
  - updated `VERSION`
  - updated `docs/CHANGELOG.md` entry at top
  - reviewed `install.sh` bootstrap flow for first-time users
  - verification that `proxmox-agent doctor` passes on target host

## Definition of Done (Per Release)

- CLI commands function on target Proxmox host.
- Install path validates GitHub SSH auth and git remote reachability.
- Backup path commits only when changes exist.
- Shutdown path preserves graceful VM/LXC flow and pre-shutdown backup behavior.
- Webhook and Telegram failures are non-blocking but logged.
- Upgrade supports rollback and logs upgrade metadata.
