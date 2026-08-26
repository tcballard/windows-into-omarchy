# QEMU runtime staging

## Frictionless bundled runtime

`scripts/Build-PortableRuntime.ps1` now constructs the installer-ready runtime
release set. It never executes QEMU's NSIS installer: it verifies and extracts
the locked Windows build, retains the x86-64 emulator plus its complete DLL and
data dependency set, adds a locked `tools\zstd.exe`, and creates:

- `windows-into-onarchy-qemu-x86_64.zip` and deterministic split parts;
- a manifest containing the SHA-256 and length of every payload file;
- SPDX 2.3 SBOM and provenance records;
- QEMU and Zstandard source releases, source offer and licence manifests; and
- a fail-closed graphics capability receipt.

Build it on a Windows release worker with 7-Zip:

```powershell
.\scripts\Build-PortableRuntime.ps1 -RunDisplaySmoke
```

The archive has factory-relative paths. Extracting it under
`%LOCALAPPDATA%\Windows Into Onarchy\Factory\<buildId>` produces
`runtime\qemu` and `tools\zstd.exe` without executing an installer or asking
for elevation. `scripts/Install-PortableRuntime.ps1` verifies every extracted
file against `payload-manifest.json`, rejects reparse points and traversal, and
emits the paths consumed by the factory materializer.

The authoritative external manifest is `dist\runtime\payload-manifest.json`.
An identical copy is embedded at
`runtime\qemu\_compliance\payload-manifest.json`; the materializer compares
their SHA-256 values before accepting the factory payload.

The QEMU build advertises VirGL and carries virglrenderer plus ANGLE. The
receipt nevertheless reports `gpuAccelerationReady: true` only if a real SDL
OpenGL display process survives the release-worker smoke. Consumers must use
the proven SDL 2D path whenever that value is false.

The same fail-closed probe can be rerun against the actual user's graphics
stack without elevation:

```powershell
.\scripts\Test-PortableRuntimeCapabilities.ps1 `
  -RuntimeRoot '<Factory>\<buildId>\runtime\qemu' `
  -OutputPath '<Factory>\<buildId>\host-capabilities.json' `
  -RunDisplaySmoke
```

This permits VirGL only after it has survived on that Windows host, rather
than assuming the release worker's graphics result applies everywhere.

The normal Windows Into Onarchy installer does **not** redistribute QEMU.
On first preparation, `scripts/Build-Runtime.ps1` downloads the exact upstream
Windows installer pinned in `config/runtime.lock.json`, verifies its SHA-512,
and silently installs it under:

```text
%LOCALAPPDATA%\Windows Into Onarchy\Runtime\qemu
```

This keeps QEMU out of the Windows Into Onarchy setup binary while removing the
separate interactive QEMU installer from the user journey.

## Optional bundled build

Maintainers may create `runtime/qemu` for an installer that intentionally
redistributes QEMU:

```powershell
.\scripts\Build-Runtime.ps1 -Mode Bundle `
  -ComplianceManifestPath '.\runtime\compliance\qemu-bundle-approval.json'
```

Bundle mode requires 7-Zip, verifies the pinned installer before extraction,
requires QEMU's `COPYING` and `COPYING.LIB`, checks the runtime capabilities,
and writes `.redistribution-reviewed.json`. It is deliberately blocked unless
the approval manifest matches the exact locked binary and supplies verified
corresponding source, SBOM, and license-manifest artifacts. Redistributing the
extracted binary set creates license-notice and corresponding-source
responsibilities beyond merely sending a user to the upstream installer.

The generated `runtime/qemu` directory is ignored by source packaging and
must not be committed.
