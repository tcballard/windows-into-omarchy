# Windows Into Omarchy

**Try the official Omarchy 4 installer from Windows, without repartitioning your PC.**

Windows Into Omarchy is a guided QEMU/WHPX virtual machine for Windows 11 x64.
It prepares a private virtual disk, verifies its pinned downloads, and keeps
Windows drives, folders, and physical devices outside the guest.

> **Early alpha:** static contracts and package integrity pass; the first
> physical-Windows installation and desktop acceptance run is still pending.

[Start with the Windows setup guide](#first-run).

This is an independent pre-1.0 project inspired by
[`themartiano/try-omarchy`](https://github.com/themartiano/try-omarchy). It is
not official and is not affiliated with or endorsed by Omarchy, Basecamp,
Omacom, Microsoft, QEMU, or the original Try Omarchy project.

## What this build contains

- A native WPF start menu with an explicit four-stage readiness rail.
- A pinned Omarchy 4.0.1 ISO contract with its published SHA-256.
- A pinned QEMU 11.1.0 Windows contract with the publisher's SHA-512.
- QEMU acceleration through Windows Hypervisor Platform (WHPX).
- A private 64 GB persistent QCOW2 disk under your Windows profile.
- Disposable sessions that discard their overlay after shutdown.
- Recoverable reset: old machine disks are archived, never silently deleted.
- Diagnostics, guarded paths, single-instance locking, and per-run logs.

The archive deliberately does not contain the multi-gigabyte Omarchy ISO or
QEMU. The launcher downloads their exact locked versions when you ask it to
prepare the machine and verifies each file before it can be used.

## First run

Requirements:

- Windows 11 x64, build 22000 or newer.
- An Intel or AMD processor with virtualization enabled in UEFI/BIOS.
- At least 16 GB host RAM recommended; 8 GB is the practical minimum.
- About 72 GB free for the download, installer cache, and virtual disk.
- An internet connection for the one-time downloads.

Steps:

1. Extract the ZIP to a normal local folder.
2. Double-click `Start-WindowsIntoOmarchy.cmd`.
3. Choose **Enable Windows hypervisor** if the second boot-rail check is not
   ready. Approve the Windows prompt and restart if requested.
4. Choose **Prepare missing components**. This downloads the locked QEMU
   installer (about 200 MB), opens its normal installer, then downloads the
   official Omarchy ISO (under 6 GB). Accept QEMU's default install folder.
5. Return to the launcher and choose **Refresh readiness**.
6. Choose **Launch persistent machine**.

On the first launch, Omarchy's official installer appears. Complete its normal
setup and select the single 64 GB virtual disk. That is the only writable disk
the guest can see. The Windows host disk is not attached.

The virtual disk is first in the boot order. While it is empty, firmware falls
through to the read-only installer ISO. Once Omarchy is installed, later
launches boot the installed system automatically.

## Important controls

- QEMU captures keyboard and pointer input when you click its desktop.
- Press **Left Shift + Left Ctrl + Left Alt + G** to release captured input.
- Closing the QEMU window ends the VM.
- **Open disposable session** starts from the persistent disk and removes only
  the temporary child overlay after shutdown.
- **Archive & reset** moves the persistent disk to `Backups` and starts fresh.

Do not end `qemu-system-x86_64.exe` while Omarchy is writing data. Shut down
from Omarchy whenever possible.

## Where data lives

All mutable data is contained beneath:

```text
%LOCALAPPDATA%\Windows Into Omarchy\
├── Downloads\   verified QEMU installer and Omarchy ISO
├── VM\          persistent disk and UEFI variables
├── Temp\        disposable overlays
├── Backups\     archived resets
├── Quarantine\  downloads that failed verification
└── Logs\        launcher and QEMU diagnostics
```

Uninstalling the source folder does not remove this machine data. This is
intentional. Archive or remove the data separately after confirming you no
longer need it.

## Current graphics status

WHPX accelerates the guest CPU. This v0.1 build uses QEMU's broadly available
VirtIO 2D display path with SDL rather than claiming unverified Windows-host
VirGL support. Omarchy should install and run, but animations and video may be
slower than native Linux. Proving and packaging an accelerated Windows GPU path
is the next runtime milestone.

## Troubleshooting

Run `scripts\Doctor.ps1` from Windows PowerShell, or choose **Diagnostics** in
the launcher.

- **Hypervisor not ready:** enable virtualization in the PC's UEFI/BIOS, then
  use the launcher's enable action and restart Windows.
- **QEMU not found:** install the verified download into
  `C:\Program Files\qemu`, or set `TRY_OMARCHY_QEMU_DIR` to its folder.
- **Firmware missing:** reinstall the complete QEMU package with its data files.
- **Digest mismatch:** the launcher quarantines the file. Do not bypass this;
  prepare again from a trusted network.
- **QEMU exits immediately:** open the newest file under `Logs` and attach it
  to a bug report after removing personal information.
- **Black or stalled installer:** wait several minutes on first boot, then
  close QEMU cleanly and try again. Do not reset the disk unless diagnostics
  show it is necessary.

See [docs/windows-smoke-test.md](docs/windows-smoke-test.md) for the complete
physical-hardware acceptance pass.

## Development

On Linux or macOS:

```bash
make test
make package
```

On Windows PowerShell:

```powershell
powershell -NoProfile -File tests\Test-Static.ps1
python tests\test_contracts.py
```

The Inno Setup recipe under `installer/` can produce an unsigned local setup
executable. Public releases must be Authenticode-signed and must complete the
release checklist before distribution.

## License

Original code in this repository is MIT licensed. Downloaded components retain
their own licenses. Read [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
