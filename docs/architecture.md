# Architecture

Windows Into Onarchy is a thin Windows host around an unmodified official
Omarchy installer and its resulting Linux system. It automates the installer
through Omarchy's supported `cidata` contract; it does not automate the screen
with simulated keystrokes or redistribute an already-installed guest.

```text
WPF launcher
  -> guarded PowerShell orchestration
    -> app-local QEMU 11.1.0 + WHPX
      -> private x86-64 virtual machine
        -> official Omarchy 4.0.1 ISO + credential-free cidata
          -> installed system + first-owner setup
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

The tiny FAT12 `cidata` drive is generated deterministically from inspectable
source. Its hash is also locked. It contains the exact minimum inputs accepted
by Omarchy's unattended installer: a 64 GB `/dev/vda` layout and an empty
`defer-provisioning` marker. There are no credentials or remote-access keys.

QEMU's upstream Windows installer is executed only after SHA-512 verification.
It runs silently into `%LOCALAPPDATA%\Windows Into Onarchy\Runtime\qemu`; the
user does not complete a second setup wizard. The runtime is then checked for
the required binaries, firmware, licences and capabilities before launch.

### Guest isolation

The QEMU process receives no physical-drive path, Windows volume, shared-folder
device, USB passthrough, SMB mount, or host filesystem export. Its mutable
storage is one QCOW2 file created beneath `%LOCALAPPDATA%\Windows Into Onarchy\VM`.
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
- Read-only official Omarchy installer ISO and read-only `cidata` drive.
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

The optional `image/` workflow can build a prepared QCOW2 for engineering and
latency experiments. It is not a normal release input: publication remains
blocked behind an explicit guest SBOM, licence/source review, sanitisation
audit, and physical-Windows first-owner boot test.
