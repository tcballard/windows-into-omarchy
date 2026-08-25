# QEMU runtime staging

The normal Windows Into Omarchy installer does **not** redistribute QEMU.
On first preparation, `scripts/Build-Runtime.ps1` downloads the exact upstream
Windows installer pinned in `config/runtime.lock.json`, verifies its SHA-512,
and silently installs it under:

```text
%LOCALAPPDATA%\Windows Into Omarchy\Runtime\qemu
```

This keeps QEMU out of the Windows Into Omarchy setup binary while removing the
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
