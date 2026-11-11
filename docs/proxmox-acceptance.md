# Local Proxmox acceptance VM

Use this disposable VM for PCG acceptance before publishing a release. It is
separate from the production Proxmox nodes.

| Item | Value |
| --- | --- |
| Setup thread | [Local Proxmox VM](codex://threads/01a1c843-ff3f-7660-beab-9e04dfe436b1) |
| Libvirt connection | `qemu:///system` |
| Domain | `pcg-proxmox-test` |
| Clean snapshot | `clean-pve-9.2` |
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
