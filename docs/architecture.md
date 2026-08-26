# Architecture

## Default v0.3 path

Windows Into Onarchy is a native Windows shell around a version-bound,
host-contained Omarchy virtual machine. The public design boots an unowned
factory disk rather than running a Linux installer on every new Windows PC.

```text
signed .NET 8 WPF WinExe
  -> hidden, bounded PowerShell orchestration
    -> embedded factory-release.json trust root
      -> verified portable QEMU/WHPX runtime + zstd
      -> verified read-only Omarchy factory QCOW2
        -> version-bound private writable overlay
          -> Omarchy first-owner provisioning
```

The WPF application renders one atomic progress journal. It does not contain
network-discovery logic; `scripts/Materialize-Factory.ps1` accepts only the
embedded manifest and immutable, versioned GitHub release URLs from that
manifest.

The official ISO/`cidata` implementation remains a separate developer and
recovery fallback. It is not attached on a factory launch and does not appear
in the standard v0.3 UI.

## Release identities

`factory/factory-release.json` binds one product version and `buildId` to
exactly two assets:

- a portable Windows runtime ZIP containing QEMU, its dependency/data set,
  firmware, compliance material and the pinned Zstandard CLI;
- a Zstandard-compressed, unowned x86-64 Omarchy factory QCOW2.

Each ordered release part has a size and SHA-256. The assembled archive has a
second size and SHA-256; the extracted payload has a third. Materialisation
rehashes all three boundaries, rejects unsafe ZIP paths, links, reparse entries,
alternate data stream paths and expansion bombs, and activates the build only
after receipts are complete.

The active factory is accepted only when all of these agree:

- the current embedded manifest digest;
- `Factory\active.json`;
- the complete factory receipt;
- the portable runtime per-file manifest;
- the read-only guest payload;
- `tools\zstd.exe`; and
- the current host capability receipt.

A new factory `buildId` receives a new factory directory and VM overlay. Old
state is never silently paired with a different backing disk.

## Windows lifecycle

The native app invokes a single experience orchestrator with hidden child
processes. Normal state transitions are:

```text
Checking -> NeedsAcceleration -> EnablingAcceleration -> AwaitingRestart
         -> Preparing -> CreatingMachine -> Launching -> Running -> Ready
```

Failures transition to `Blocked` or `Failed`, with a stable recovery code. The
journal under `Experience\progress.json` is replaced atomically. Downloads and
materialisation are idempotent at verified boundaries.

Before requesting elevation, the non-elevated app registers a bounded
per-user `RunOnce` continuation. This matters when a standard user supplies a
different administrator credential at UAC: resume belongs to the original
interactive user, not the elevated account. The continuation is cleared when
preparation resumes or when elevation is cancelled/fails.

## Factory and persistence

The expanded factory disk is read-only at:

```text
Factory\<buildId>\guest\omarchy-factory.qcow2
```

First run creates an almost-instant QCOW2 overlay at:

```text
VM\<buildId>\omarchy.qcow2
```

The overlay receipt records the exact absolute backing file. Before launch,
`qemu-img` verifies the overlay and the complete backing chain. QEMU attaches
only the overlay as writable; it never attaches the factory directly writable.

Disposable mode adds one temporary overlay above the persistent overlay.
Archive/reset moves the persistent overlay and receipt into a timestamped
`Backups` directory. Both cleanup and archive operations are limited to paths
beneath the product's local application-data root and reject reparse points.

## Host isolation

The guest receives no physical-drive path, Windows volume, shared-folder
device, USB passthrough, SMB mount, clipboard bridge, SSH agent, credential
store or arbitrary host filesystem export. Networking uses QEMU's unprivileged
user-mode backend.

This is a deliberately narrow host interface, not a claim that QEMU or an
arbitrary guest can contain no vulnerabilities. Release security depends on
timely pinned rebuilds and review of the exact runtime and guest.

## Machine contract

- Windows 11 x64 host with firmware virtualisation and WHPX.
- `q35` machine and UEFI firmware from the version-bound runtime.
- Four to eight vCPUs; memory selected conservatively from host capacity.
- 64 GiB VirtIO block factory/overlay chain.
- VirtIO user-mode networking and random-number device.
- DirectSound with HDA duplex audio.
- Virtual USB keyboard and absolute tablet pointer.
- SDL/VirtIO 2D as the fail-closed display path.

The runtime's on-host probe may select `virtio-vga-gl` only when VirGL is
advertised, ANGLE libraries are present and the exact SDL OpenGL display smoke
survives. Otherwise it selects `virtio-vga` with GL disabled. WHPX evidence is
CPU acceleration evidence; it is not GPU acceleration evidence.

## Fallback architecture

The v0.2-style fallback downloads the locked official Omarchy ISO and upstream
QEMU installer, verifies them, creates a private blank disk, and supplies the
credential-free `cidata` drive. It may require a QEMU installation UAC prompt
and waits for the official installer to complete.

Fallback remains valuable for factory production, recovery and development,
but a release that falls back on a clean consumer machine has failed the v0.3
product acceptance contract.

## Release boundaries

Three independent boundaries remain before stable publication:

1. **Engineering:** build and verify the exact runtime, guest, native app and
   installer on their required Windows/KVM hosts.
2. **Compliance:** review the exact guest/runtime inventories, notices,
   proprietary terms and corresponding-source delivery; remove every unresolved
   shipped dependency.
3. **Acceptance:** sign the executable and installer, then complete clean
   physical Windows runs on the release artifacts.

Automated source contracts are necessary evidence, but cannot substitute for
those boundaries.
