# Local Proxmox acceptance VM

Use this disposable VM for PCG acceptance before publishing a release. It is
separate from the production Proxmox nodes.

| Item | Value |
| --- | --- |
| Setup thread | [Local Proxmox VM](codex://threads/01a1c843-ff3f-7660-beab-9e04dfe436b1) |
| Libvirt connection | `qemu:///system` |
| Domain | `pcg-proxmox-test` |
| Clean snapshot | `clean-pve-9.2` |
| Snapshot preserving the GitHub SSH setup | `pcg-github-ready` |
| Proxmox version | 9.2.2, recorded by the setup session |
| Network | Libvirt default NAT |
| SSH endpoint | `root@192.168.122.21`, recorded by the setup session |
| VM storage and host-key file | `/home/rabin/git-projects/proxmox-test/` |

On 2026-11-11, libvirt reported the VM shut off and the clean snapshot present.
That check did not boot the guest or test PCG. Root credentials remain in the
local VM setup directory, outside this repository.

## Inspect and start

```bash
virsh -c qemu:///system domstate pcg-proxmox-test
virsh -c qemu:///system snapshot-list pcg-proxmox-test
virsh -c qemu:///system start pcg-proxmox-test
virsh -c qemu:///system domifaddr pcg-proxmox-test --source lease
ssh -o UserKnownHostsFile=/home/rabin/git-projects/proxmox-test/known_hosts root@192.168.122.21
```

Check the current DHCP lease before connecting. The recorded IP may change.
Use the existing root authentication setup from the VM preparation session.

## Restore the clean slate

Restoring the snapshot discards guest changes made after it was taken. Save
any test evidence outside the VM first. Shut down the guest and confirm that
`domstate` reports it shut off before resetting.

```bash
virsh -c qemu:///system shutdown pcg-proxmox-test
virsh -c qemu:///system domstate pcg-proxmox-test
```

Once the VM is off:

```bash
virsh -c qemu:///system snapshot-revert pcg-proxmox-test clean-pve-9.2
virsh -c qemu:///system start pcg-proxmox-test
```

## Verified branch acceptance on 2026-11-11

The candidate was copied from `fix/backup-lifecycle-reliability` with `git archive`.
GitHub backups used `git@github.com:ruhanirabin/pcg-vm-test.git`, with configuration
commits pushed to that test repository's `main` branch.

The initial candidate was 0.7.30. A real host reboot exposed an error in the
shutdown guard. Systemd invokes the service while the host is already stopping,
so the guard prevented its backup. Commit `b3f61e0` allows that invocation and
returns control to systemd after guest shutdown, preserving the requested host
action. Version 0.8.0 followed the repository's patch rollover rule.

Commit `e713b1e` added explicit journal outcomes and service output for 0.8.1.
Installed backup and shutdown scripts matched the branch files by SHA-256.

| Check | Observed result |
| --- | --- |
| Missing Git on first install | Installer prompted and installed Git through APT |
| GitHub authentication and doctor | Root SSH authenticated and doctor JSON passed |
| Logger dependency | Proxmox package ownership identifies `bsdutils` as the provider, and the APT mapping uses that package |
| Actual backup publication | Branch commits and backup tags reached the private test repository |
| VM and LXC collection | Real QEMU and Alpine LXC definitions were collected |
| Deletions | Removed VM, LXC, firewall, custom unit and extra-script files disappeared from the new snapshot |
| Default script selection | An unrelated script was excluded, then collected through explicit selection |
| Unchanged collection | No new local commit was created |
| Failed push and retry | A blocked push retained its local commit, then an unchanged run published it |
| Systemd backup service | Ran with the installed environment and returned success |
| Missing SSH identity | Live GitHub authentication failed with actionable doctor JSON |
| Lock contention | A competing repository lock blocked the backup within its configured wait |
| Stalled SSH transport | A local endpoint that withheld its handshake hit the configured two-second timeout |
| Installed Save/Resume | Save restored existing settings, and Resume completed installation |
| Legacy migration | Preserved the repository setting and removed legacy env, binary and enabled timer artifacts |
| Upgrade rollback | A failed doctor and an incomplete payload each restored installed files, version and unit enablement |
| Successful upgrades | Local tagged branch payloads upgraded the VM to 0.8.0 and 0.8.1 |
| Unresponsive guest | PCG forced a QEMU VM without a guest OS to stop, continued to the Alpine LXC, and shut it down gracefully |
| Systemd shutdown and reboot | The stopping-state backup completed, the shutdown unit succeeded and the host rebooted |
| Journal outcomes | Success, failed push, unchanged retry, CLI and shutdown events were recorded under `pcg-backup` |
| Uninstall and final install | Canonical enabled units and files were removed, then 0.8.1 installed and passed doctor and backup again |

The guest fixtures were removed after testing. The VM retains the tested PCG
installation, its logs and the downloaded Alpine template. Both reset snapshots
are available.

### Reading the journal evidence

The deliberate failed push produced `backup_failed`, `phase=push_branch`,
`branch_push=not_confirmed` and exit status 128. Its retry produced
`backup_success` for the same commit with `branch_push=confirmed`.

A scheduled backup interrupted by reboot also recorded exit status 143. The
shutdown backup then completed and recorded `entrypoint=shutdown` before the
host rebooted.

```bash
journalctl -t pcg-backup --since today --no-pager
journalctl -t pcg-backup -p err --since today --no-pager
journalctl -u pcg-backup-config.service -n 100 --no-pager
```

Detailed workstation evidence is under `/tmp/pcg-vm-acceptance/`. It is temporary
local output and is excluded from the repository. This record summarizes the
verified results for later sessions.

### Remaining validation limits

- Upgrade transport used local tagged payloads containing the branch source.
  Published GitHub release artifacts remain a release-stage check.
- Successful Telegram and webhook delivery require operator-provided endpoints
  and credentials. Failed placeholder notifications were logged and backup work
  continued.
- Read-only credential denial is covered by deterministic transport tests.
  The live GitHub key used here has write access.
- The privileged Docker Compose runner remains separate from the passing Ubuntu
  Podman smoke test and this real Proxmox VM acceptance.

ShellCheck 0.9.0 ran in an Ubuntu container. Two reviewed warnings remain in the
shared library. SC2034 concerns a UI variable read by the CLI, and SC1090 concerns
the selected runtime environment file. Syntax and whitespace checks pass.

## Acceptance scope

Start from the clean snapshot. Stage the exact PCG branch commit and test:

- Guided installation, doctor JSON and a real backup to a dedicated test repository.
- Missing credentials, denied write access and unavailable network, with bounded
  failure and useful diagnostics.
- Timer execution under systemd, including credentials available to root's service.
- Upgrade failure and rollback, followed by another doctor run and backup.
- Guest shutdown and forced-stop behavior using disposable guest resources.

A local Git server can exercise transport failures. Live GitHub authentication,
write permissions and repository rules need a dedicated GitHub test repository.
Record those results separately from local mocks and Ubuntu container tests.
