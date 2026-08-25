# Claims ledger

| ID | Claim | Importance | Evidence | Status | Qualification | Channels | Owner |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C01 | Windows Into Onarchy prepares a guided QEMU/WHPX VM for Windows 11 x64. | Required | `launcher/`, `scripts/`, runtime lock | Verified | Product implementation, not a completed physical run | README, release | Tom |
| C02 | Omarchy 4.0.1 and QEMU 11.1.0 downloads are version- and digest-pinned. | Required | `config/runtime.lock.json`; publisher release/hash pages | Verified | The third-party binaries are downloaded at preparation time | README, release | Tom |
| C03 | The VM command attaches no physical Windows disk, host folder, or USB host device. | Required | `scripts/Run-VM.ps1`; passing isolation contract | Verified | Applies to the shipped command contract | README, release | Tom |
| C04 | WHPX accelerates guest CPU execution while display uses VirtIO 2D. | Required | runtime command; QEMU documentation | Qualified | No Windows-host GPU acceleration claim | README, release | Tom |
| C05 | Persistent, disposable, and recoverable-reset flows are implemented. | Important | lifecycle scripts; passing contracts | Qualified | Physical Windows behavior remains to be accepted | README, release | Tom |
| C06 | The v0.1.0 source ZIP passes 15 contracts and ZIP integrity verification. | Required | `make package`; `dist/SHA256SUMS` | Verified | Static/package evidence only | README, release | Tom |
| C07 | Omarchy installs and reaches its desktop on Windows. | Required | `docs/windows-smoke-test.md` | Removed | First physical Windows run pending | Excluded from this launch | Tom |
