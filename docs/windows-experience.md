# Native Windows experience

The v0.3 default is `WindowsIntoOmarchy.exe`, a .NET 8 WPF `WinExe`. It owns
one progress surface from host inspection through Omarchy launch. PowerShell is
an implementation detail behind that surface: helpers always start hidden and
only the Windows elevation prompt and the Omarchy VM may appear separately.

## Normal journey

1. Open **Windows Into Omarchy**.
2. Select **Set up and enter Omarchy** once.
3. If WHPX is disabled, approve the Windows feature change. A bounded per-user
   `RunOnce` entry reopens the native app with `--resume` after the required
   restart, then removes itself at the next verified boundary.
4. The experience orchestrator materialises the immutable release identified
   by the embedded `factory/factory-release.json`, creates a private QCOW2
   overlay, selects conservative memory/CPU values for the host, and launches.
5. Omarchy opens directly at first-owner provisioning. Later app launches use
   **Enter Omarchy** and the same overlay.

The compatibility PowerShell launcher first delegates to the native executable
when it is installed. It exists for source/developer packages and is not the
v0.3 public entry point.

## State and recovery

`%LOCALAPPDATA%\Windows Into Omarchy\Experience\progress.json` is the versioned,
atomically replaced UI journal. The native app only renders this local state;
it never discovers network versions or consumes a remote manifest. Failures
remain on the same surface with a stable recovery code, **Try again**, and links
to logs and machine files.

Setup state is idempotent. Reopening after lost power, network interruption or
restart resumes only from verified material. Invalid artifacts are never
executed or booted. Reset delegates to the recoverable archive operation.

## Integration contract

The packaged app must place `WindowsIntoOmarchy.exe` beside `scripts/` and
include `scripts/experience/`. When an active factory is absent,
`Experience.ps1` calls the release materialiser at
`scripts/Materialize-Factory.ps1 -ManifestPath <embedded manifest>`. That
materialiser owns resumable part download, verification, archive extraction,
receipts and `Factory\active.json`; it must not prompt or open a console.

The VM runner must consume the active build's portable runtime and
`VM\<buildId>\omarchy.qcow2`. The immutable guest factory stays beneath
`Factory\<buildId>` and is never attached writable. No host volume, directory,
physical disk, USB device or credential store is exposed to the guest.
