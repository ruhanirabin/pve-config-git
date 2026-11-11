# Reliability review fixes

Work branch: `fix/backup-lifecycle-reliability`. Prepared version: 0.7.30.
All 19 supplied findings have implementation changes. This is not a target-host
release acceptance record.

| Finding | Change | Verification |
| --- | --- | --- |
| Executable CLI | Track bin/pcg as executable | Ubuntu bootstrap uses local checkout |
| Missing VM definitions | Collect qemu-server configs | Real Git fixture backup |
| Unpublished commits | Pull/push even without collection changes | Reject push, rerun unchanged, compare remote HEAD |
| Wrong lifecycle unit names | Canonical pcg-* and legacy pa-* lists | Snapshot/restore files and enabled state |
| Env changes errexit | Restore caller's mode | Test both modes; guided Save/Resume |
| Copy failures hidden | Validate payload and return individual failures | Missing source and failed install command; doctor rollback |
| Legacy env overwritten | Migrate before template | Preserve legacy repository setting |
| Deleted files retained | Refresh owned collection families | Delete LXC, firewall and unit fixtures |
| Broad script collection | Explicit PCG allowlist | Unrelated script excluded |
| Concurrent backups | Repository flock with bounded wait | Competing lock blocks collection |
| Installed source resolution | Versioned local payload cache | Installed CLI reinstall and resume in Ubuntu |
| Nonzero stopping state | Inspect captured output independently | Mock systemctl stopping with nonzero exit |
| Forced guest aborts sequence | Handle wait failure in each loop | Force two VMs and one LXC, reach host mock |
| Ineffective retention | Rotate previous-day active logs; match dated family | Expire both log types |
| Menu stdout contamination | Warnings go to stderr | Invalid then valid for all four menus |
| Backup Telegram stalls/fails silently | Reuse bounded shared sender, log warning | Mock rejected API response; require timeout; backup succeeds |
| Tests omitted from archive | Include tests in container payload | Archive command inspected; standalone Ubuntu suite passes |
| Backup test false success | Run isolated behavior tests; propagate failure | Missing scripts/runtime errors fail the wrapper |
| Obsolete guided smoke | Current flag, prompts and valid rewritten GitHub URL | Ubuntu install, doctor, Save/Resume and shutdown mocks |

## Dependencies and failure paths

- Preflight, preinstall reporting and doctor now include util-linux/flock,
  tar and crontab. Installation also checks find and install.
- Ubuntu Compose used nonexistent ssh-client/ssh-keygen package names. It now
  installs openssh-client/openssh-server, cron, util-linux and Python for tests.
  It starts init with exec and checks SSH readiness rather than requiring an
  entirely non-degraded systemd state.
- Missing PVE configuration directories, failed collection copies, staged Git
  changes and interrupted rebases fail visibly. A failed collection preserves
  the previous snapshot. Backups stage only the current node directory.
- Installed sources contain only the managed binaries, units, VERSION and env
  example. They do not include the private runtime environment.
- Extra scripts now require explicit operator selection. Git history can still
  contain older files; removing a file from a new snapshot does not erase history.

## Unattended Git access follow-up

- Install and doctor now check read access and a dry-run push, including empty
  repositories. Temporary local objects are discarded and no remote branch is
  created. The check retains repository-local transport and credential settings.
- Git network commands use non-interactive credential settings, batch SSH,
  closed standard input and an overall timeout. `GIT_TIMEOUT_SECONDS` defaults
  to 60 seconds, with a five-second termination grace period.
- Errors are classified without forwarding raw credential-bearing output.
  GitHub's private-repository “not found” response stays explicitly ambiguous.
- Tests cover simulated read-only credentials, missing keys, HTTPS prompts,
  network errors, host-key errors, timeout termination, untouched local/remote
  state and GitHub's successful SSH greeting with exit status 1.
- Dry-run checks do not run receive hooks or prove backup-branch rules will
  accept a real push. Live GitHub permissions remain unverified. GitLab support
  is deferred.

## Validation boundary

Local isolated tests use real Git and local bare remotes, synthetic PVE files,
mock notifications and mock guest/systemctl commands. The Ubuntu smoke uses
PCG_TEST_MODE, so it does not establish real systemd or Proxmox acceptance.

Before release, follow [the local Proxmox acceptance runbook](proxmox-acceptance.md)
to run install, doctor, backup and upgrade/rollback on the disposable VM. Verify guest lifecycle behavior there. No host activation,
remote push, tag or release is part of this branch preparation.
