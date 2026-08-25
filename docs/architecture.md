# Architecture

Windows Into Omarchy is a thin Windows host around an unmodified official
Omarchy installer and its resulting Linux system.

```text
WPF launcher
  -> guarded PowerShell orchestration
    -> QEMU 11.1.0 + WHPX
      -> private x86-64 virtual machine
        -> official Omarchy 4.0.1 installer / installed system
```

## Trust boundaries

### Project source

The launcher and orchestration scripts are inspectable source. They select
fixed external identities from `config/runtime.lock.json`; runtime code does
not select a floating "latest" version.

### Downloads

Downloads land as `.partial` files under the app's private data directory.
They are moved to their final names only after hash verification. A conflicting
or invalid existing download is moved into `Quarantine`.

The Omarchy digest is copied from the official v4.0.1 release. The QEMU digest
is copied from the `.sha512` published beside the Windows installer linked by
QEMU's official download page.

### Guest isolation

The QEMU process receives no physical-drive path, Windows volume, shared-folder
device, USB passthrough, SMB mount, or host filesystem export. Its mutable
storage is one QCOW2 file created beneath `%LOCALAPPDATA%\Windows Into Omarchy\VM`.
Networking uses QEMU's unprivileged user-mode backend.

This is isolation, not a claim that an arbitrary guest or hypervisor contains
no vulnerabilities. Keep Windows, QEMU, and Omarchy updated through reviewed
lock changes.

### Persistence

Persistent mode writes directly to `VM\omarchy.qcow2`. Disposable mode creates
a uniquely named QCOW2 overlay beneath `Temp`, uses the persistent disk as a
read-only backing image, and removes only that verified child path after the
QEMU process exits.

Reset moves the persistent disk and UEFI variable store into a timestamped
directory beneath `Backups`. No recursive deletion or user-selected target is
involved.

### Concurrency

A per-user named mutex permits one VM process. This prevents two QEMU instances
from opening the same persistent disk or racing a disposable overlay.

## Machine contract

- `q35` machine with WHPX acceleration.
- QEMU's conservative default WHPX CPU model; the maximal emulated model is
  avoided because it has failed on some Windows/AMD hosts
  ([QEMU issue #1043](https://gitlab.com/qemu-project/qemu/-/issues/1043)).
- Four to eight virtual CPUs and 4-32 GB RAM, with 8 GB recommended.
- UEFI through QEMU's EDK II firmware.
- 64 GB QCOW2 VirtIO block disk.
- Read-only official Omarchy installer ISO.
- VirtIO display through SDL, without unverified host GL acceleration.
- VirtIO user-mode networking.
- DirectSound duplex HDA audio.
- Virtual USB keyboard and absolute tablet pointer.
- VirtIO random-number device.

Before launch, diagnostics require the selected QEMU installation to advertise
WHPX, SDL, DirectSound, VirtIO display and storage, HDA duplex audio, and usable
firmware.

## Update discipline

A version update is one reviewed transaction:

1. Change the source URL, version, and digest together.
2. Re-run static and contract tests.
3. Build a clean archive.
4. Complete the physical Windows smoke test.
5. Review third-party notices and corresponding-source obligations.
6. Sign the final Windows package before public distribution.
