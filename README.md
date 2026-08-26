# Windows Into Onarchy

**Install one Windows app. Click once. Enter your own Omarchy machine.**

Windows Into Onarchy is an independent Windows 11 host for Omarchy. The v0.3
design uses a native WPF application, a portable QEMU/WHPX runtime and an
unowned Omarchy factory disk to reach Omarchy's normal first-owner setup
without showing a Linux installer, terminal, QEMU setup wizard or ISO chooser.

> **Development release candidate—not stable:** the v0.3 source, factory
> pipeline and automated contracts exist, but the exact portable runtime and
> multi-gigabyte guest release still require hosted builds, licence/source
> review, Authenticode signing and physical-Windows acceptance. Do not publish
> or describe an unsigned artifact as a finished public release.

This project is inspired by
[`themartiano/try-omarchy`](https://github.com/themartiano/try-omarchy). It is
not official and is not affiliated with or endorsed by Omarchy, Basecamp,
Omacom, Microsoft, QEMU or the original Try Omarchy project.

## Intended first run

The public v0.3 journey is deliberately short:

1. Install and open **Windows Into Onarchy**.
2. Select **Set up and enter Omarchy**.
3. If Windows Hypervisor Platform is disabled, approve that Windows feature
   change. If Windows requires a restart, the app reopens once after sign-in
   and resumes automatically.
4. Keep using the single progress window while the app downloads, assembles,
   verifies and expands its immutable factory release.
5. Omarchy opens at first-owner provisioning. Choose your keyboard, username
   and password inside Omarchy.

Later launches are simply **Enter Omarchy**. The app selects conservative CPU
and memory values for the PC; ordinary users do not need to configure QEMU.

The factory has no owner account, password, SSH key, Tailscale key, reusable
token or machine identity. Personal details are deliberately created by
Omarchy on first boot. Windows disks, folders and physical devices are never
attached to the guest.

## What v0.3 changes

The factory-default path removes the two largest sources of first-run friction:

- QEMU is supplied as a checksum-pinned portable runtime, so there is no QEMU
  installer or runtime UAC prompt.
- Omarchy is supplied as an audited, unowned factory disk, so there is no ISO
  download followed by a Linux installation wait.

Large assets are split into immutable release parts. Every part, assembled
archive and extracted payload is checked against the embedded
`factory/factory-release.json` trust root. Invalid or interrupted artifacts are
quarantined and are never executed or booted.

The official ISO plus credential-free `cidata` flow remains a developer and
recovery fallback. It is excluded from the normal v0.3 UI and is not evidence
that the factory release is ready. A source build without a generated factory
manifest reports that it is using this fallback rather than silently
pretending to provide the public experience.

## Requirements

- Windows 11 x64, build 22000 or newer.
- An Intel or AMD CPU with virtualisation enabled in UEFI/BIOS.
- 16 GB host RAM recommended; 8 GB is the minimum contract.
- At least 80 GB free while evaluating the current factory build. The final
  compressed download and peak-disk figures must be measured from the exact
  release assets before publication.
- Internet access for the first factory download.

Windows Into Onarchy does not support Windows on Arm or 32-bit Windows in this
release.

## Runtime and graphics

WHPX accelerates the guest CPU. At factory materialisation time, the app probes
the exact QEMU runtime on that Windows host and records
`host-capabilities.json`.

- The conservative supported path is SDL with VirtIO 2D graphics.
- VirGL/OpenGL is enabled only when QEMU advertises it, the required ANGLE
  libraries are present, and an on-host display smoke test survives.
- Absence or failure of that evidence fails closed to 2D.

This is not a blanket claim of Windows GPU acceleration. A public release may
describe the accelerated path only for hardware on which the exact signed
artifact was measured and recorded.

## Controls and recovery

- Press **Left Shift + Left Ctrl + Left Alt + G** to release captured input.
- Shut down from Omarchy whenever possible; closing the QEMU window ends the
  VM.
- **Disposable session** creates a child overlay and discards only that child
  after shutdown.
- **Archive & reset** moves the writable machine overlay into `Backups`; it
  does not delete the immutable factory or an unrecognised path.
- **Open logs** and **Machine files** expose local evidence without opening a
  terminal.

The per-user VM mutex prevents concurrent processes from opening the same
writable disk.

## Data layout

All mutable state stays below:

```text
%LOCALAPPDATA%\Windows Into Onarchy\
├── Factory\<buildId>\
│   ├── runtime\qemu\
│   ├── tools\zstd.exe
│   ├── guest\omarchy-factory.qcow2   read-only factory
│   ├── host-capabilities.json
│   └── receipt.json
├── VM\<buildId>\omarchy.qcow2       private writable overlay
├── Downloads\<buildId>\             verified release parts
├── Experience\                      atomic progress/resume state
├── Temp\                            disposable overlays
├── Backups\                         recoverable archives
├── Quarantine\                      rejected artifacts
└── Logs\                            experience and QEMU diagnostics
```

Uninstalling the application intentionally does not destroy VM data. Remove it
separately only after confirming that no backup is required.

## Troubleshooting

- **Virtualisation disabled:** enable Intel VT-x or AMD-V in UEFI/BIOS. The app
  distinguishes this from a disabled Windows feature and will not claim it can
  repair firmware itself.
- **Restart requested:** use the app's restart action. A bounded per-user
  `RunOnce` entry reopens it once and is cleared at the next verified boundary.
- **Download or digest failure:** retry from the same window. Verified parts
  are reused; invalid data is quarantined.
- **Factory rejected:** open the logs. The app requires matching manifest,
  activation, runtime, capability and guest receipts before launch.
- **Machine needs recovery:** use **Archive & reset**. The previous overlay is
  preserved before a fresh one is created against the same factory.
- **QEMU exits:** attach the newest redacted log to a bug report. Never publish
  passwords, tokens, private keys or disk images.

See [the physical Windows checklist](docs/windows-smoke-test.md) for the actual
release-acceptance test.

## Development

Static and deterministic contracts:

```bash
make test
```

Native Windows application:

```powershell
dotnet publish .\windows\WindowsIntoOnarchy\WindowsIntoOnarchy.csproj `
  -c Release -r win-x64 --self-contained true -o .\dist\native-app
```

Release engineering also builds the portable runtime on hosted Windows and the
guest factory on the protected KVM builder. The ISO/`cidata` flow under
`image/` remains useful for development, recovery and reproducibility checks;
it is not the standard v0.3 release input.

## Legal and release status

The repository's original code is MIT licensed. That does **not** grant the
right to redistribute every binary inside QEMU or every package inside a
completed Omarchy disk. The factory-default experience therefore carries a
substantially larger compliance burden than the v0.2 direct-download design.

In practical terms, “legal/compliance” means producing and reviewing the exact
binary-to-source mapping, licence texts, notices, source offers, proprietary
licence permissions, guest sanitisation evidence and trademark position for
the precise assets being published. Code signing proves publisher identity; it
does not supply redistribution permission.

The current pipeline generates much of that evidence, but the release remains
blocked until the exact outputs are reviewed and all `NOASSERTION` dependency
entries are resolved. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and
[the distribution compliance plan](docs/distribution-compliance.md).

## License

Original Windows Into Onarchy code is available under the [MIT License](LICENSE).
Third-party components retain their own copyrights, licences and marks.
