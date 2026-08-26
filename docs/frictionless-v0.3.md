# Frictionless v0.3 architecture

## Product acceptance contract

The standard Windows experience is complete only when a new Windows 11 x64
user can:

1. download and install one Windows application;
2. open **Windows Into Onarchy** without installing QEMU or finding an ISO;
3. approve the Windows hypervisor change once if the host needs it;
4. restart Windows and have the same application resume automatically;
5. watch one progress surface prepare the verified factory machine; and
6. enter Omarchy's first-owner provisioning without seeing a Linux installer.

Later launches must open the existing machine directly. A terminal, package
manager, QEMU installer, ISO chooser, firmware configuration screen, or manual
boot menu on this path is a product failure.

## Release shape

The release consists of three independently verifiable pieces:

- a small Authenticode-signed Windows installer and WPF application;
- a portable QEMU/WHPX runtime archive, including all required DLLs, firmware,
  notices, corresponding-source references, and an SBOM; and
- an unprovisioned x86_64 Arch Linux factory disk containing the pinned Omarchy
  source plus its package lock, provenance, notices, and SBOM.

The application embeds the generated `factory-release.json` trust root. It
downloads no mutable `latest` metadata. Large release assets may be split, but
each part and the assembled archive are SHA-256 pinned.

```text
signed Windows app
  -> embedded immutable release manifest
     -> portable QEMU/WHPX runtime
     -> unprovisioned Omarchy factory disk
        -> private writable QCOW2 overlay
```

The guest disk has no owner account, password, SSH key, machine identity,
history, cloud token, Tailscale key, or reusable signing secret. Upstream
first-owner provisioning runs inside the guest on its first boot.

## Host state

All mutable application state remains below:

```text
%LOCALAPPDATA%\Windows Into Onarchy\
├── Factory\<buildId>\
│   ├── runtime\qemu\
│   ├── guest\omarchy-factory.qcow2
│   └── receipt.json
├── VM\<buildId>\omarchy.qcow2
├── Downloads\<buildId>\
├── Backups\
├── Quarantine\
├── Experience\
└── Logs\
```

The factory disk is immutable. The normal machine is a QCOW2 overlay backed by
that exact build. Its receipt records both identities. A new factory build gets
a new directory and overlay; the launcher never pairs saved state with a
different base disk.

No Windows volume, physical disk, host directory, USB device, clipboard, SSH
agent, or credential store is attached to the guest.

## First-run state machine

| State | Automatic action | User-visible result |
| --- | --- | --- |
| Host unsupported | None | One specific requirement and a diagnostic link |
| Virtualisation disabled in firmware | None | Exact UEFI/BIOS instruction; no unsafe fallback claim |
| WHPX feature disabled | Register bounded per-user resume, request elevation, enable feature | One Windows approval and restart action |
| Restart pending | Preserve state and exit | “Restart to continue”; app reopens once after sign-in |
| Assets missing | Download, resume, verify, assemble, extract and audit | One determinate progress surface |
| Assets invalid | Quarantine; never execute or boot | Retry plus a precise diagnostic reference |
| Overlay missing | Create against the exact factory build | “Preparing your machine” |
| Ready | Start QEMU without a console window | Omarchy owner provisioning or existing desktop |
| Factory changed | Preserve old workspace; require explicit migration/reset choice | No silent data loss |

The transition journal is written atomically under `Experience`. Operations are
idempotent: reopening the app after a crash, lost network, cancellation, or
restart continues at the last verified boundary.

## Recovery path

The current official ISO/cidata flow remains available to developers and as a
documented recovery route. It is excluded from the default UI and is not a
substitute for a factory release. Recoverable reset archives the writable
overlay; it never deletes an unrecognised path or follows a reparse point.

## Release gates

- Reproducible guest build and complete package/source inventory.
- Guest secret, identity, history, cache, and unowned-file audit.
- Portable runtime capability test on Windows 11 Home and Pro.
- Corresponding source and licence evidence for the distributed runtime and
  every guest package/file.
- Installer and executable Authenticode signatures.
- Clean Windows 11 physical-machine run through enable, restart, resume,
  download, first boot, owner provisioning, shutdown, and second launch.
- Graphics claims limited to the exact path proved by the runtime smoke test.
