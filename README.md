# Windows Into Onarchy

**Install one Windows app, then enter a private Omarchy machine.**

Windows Into Onarchy is a one-button QEMU/WHPX virtual machine for Windows 11
x64. The app downloads only checksum-pinned upstream components, installs
Omarchy unattended into a private virtual disk, and then opens Omarchy's normal
first-owner setup. Windows drives, folders, and physical devices stay outside
the guest.

> **v0.2 release candidate:** automated contracts and Windows PowerShell parsing
> pass. The exact setup executable still requires a physical-Windows
> installation and desktop acceptance run before it can be promoted as stable.

[Start with the Windows setup guide](#first-run).

This is an independent pre-1.0 project inspired by
[`themartiano/try-omarchy`](https://github.com/themartiano/try-omarchy). It is
not official and is not affiliated with or endorsed by Omarchy, Basecamp,
Omacom, Microsoft, QEMU, or the original Try Omarchy project.

## What this build contains

- A native WPF start menu with one primary first-run action.
- A pinned Omarchy 4.0.1 ISO contract with its published SHA-256.
- A pinned QEMU 11.1.0 Windows contract with the publisher's SHA-512 and a
  silent app-local installation path.
- Omarchy's official credential-free `cidata` unattended-install flow.
- QEMU acceleration through Windows Hypervisor Platform (WHPX).
- A private 64 GB persistent QCOW2 disk under your Windows profile.
- Disposable sessions that discard their overlay after shutdown.
- Recoverable reset: old machine disks are archived, never silently deleted.
- Diagnostics, guarded paths, single-instance locking, and per-run logs.

The installer deliberately does not repackage the multi-gigabyte Omarchy ISO or
QEMU. On first run it downloads their exact locked upstream versions, verifies
them before execution, installs QEMU into this app's private data directory,
and lets the official Omarchy ISO install itself. No Linux installer questions
are presented and no prepared third-party VM disk is redistributed.

## First run

Requirements:

- Windows 11 x64, build 22000 or newer.
- An Intel or AMD processor with virtualization enabled in UEFI/BIOS.
- At least 16 GB host RAM recommended; 8 GB is the practical minimum.
- About 72 GB free for the download, installer cache, and virtual disk.
- An internet connection for the one-time downloads.

Normal path:

1. Run `Windows-Into-Onarchy-v0.2.0-setup.exe` and launch the app.
2. If prompted, choose **Enable acceleration & continue**, approve Windows,
   and restart once.
3. Choose **Download & enter Omarchy (~6 GB)**. Windows may show one approval
   prompt while the verified QEMU runtime is installed silently. The official
   ISO then downloads, installs unattended, reboots, and opens first-owner
   setup inside the Omarchy window.
4. Pick your keyboard, username and password in Omarchy. Later app launches are
   simply **Enter Omarchy**.

The unattended configuration selects the single private 64 GB virtual disk and
defers all personal details until first boot. It contains no username,
password, SSH key, Tailscale key, or reusable credential. The Windows host disk
is never attached.

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
%LOCALAPPDATA%\Windows Into Onarchy\
├── Downloads\   verified upstream QEMU installer and Omarchy ISO
├── Runtime\     private app-local QEMU runtime and acquisition receipt
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

WHPX accelerates the guest CPU. This v0.2 build uses QEMU's broadly available
VirtIO 2D display path with SDL rather than claiming unverified Windows-host
VirGL support. Omarchy should install and run, but animations and video may be
slower than native Linux. Proving and packaging an accelerated Windows GPU path
is the next runtime milestone.

## Troubleshooting

Run `scripts\Doctor.ps1` from Windows PowerShell, or choose **Diagnostics** in
the launcher.

- **Hypervisor not ready:** enable virtualization in the PC's UEFI/BIOS, then
  use the launcher's enable action and restart Windows.
- **QEMU not found:** choose the app's download action again. It verifies and
  repairs the private runtime under the app data directory. Advanced users can
  still set `TRY_OMARCHY_QEMU_DIR` to a compatible installation.
- **Firmware missing:** reinstall the complete QEMU package with its data files.
- **Digest mismatch:** the launcher quarantines the file. Do not bypass this;
  prepare again from a trusted network.
- **QEMU exits immediately:** open the newest file under `Logs` and attach it
  to a bug report after removing personal information.
- **Install appears slow:** the first run copies several gigabytes from the ISO.
  Leave the Omarchy window open while its installation dashboard runs and
  reboots. Later launches boot the installed system directly.

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

`python image/make_cidata.py` deterministically rebuilds the tiny
credential-free unattended drive. Its SHA-256 is part of the runtime lock.

The Inno Setup recipe under `installer/` can produce an unsigned local setup
executable. Public releases must be Authenticode-signed and must complete the
release checklist before distribution.

## License

Original code in this repository is MIT licensed. Downloaded components retain
their own licenses. Read [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[the distribution compliance plan](docs/distribution-compliance.md).
