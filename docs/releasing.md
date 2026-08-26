# Release process

Windows Into Omarchy v0.3 is a coordinated release of code, a native Windows
application, a portable runtime, an unowned guest factory and their compliance
evidence. Passing source tests alone does not create a distributable release.

## 1. Freeze identities

1. Select the product version, factory tag and unique `buildId`.
2. Freeze the Omarchy ISO/source commit, package inputs, QEMU commit/build,
   Zstandard version and all transitive build inputs.
3. Update lock/spec files in one reviewed change. No release input may use
   `latest`, a branch head, query-bearing URL or unrecorded local artifact.
4. Run `make test` on a clean tree.

## 2. Build and audit the guest

Use only the protected self-hosted KVM builder defined by the guest workflow.
Pull requests and untrusted forks must never execute on it.

The releaseable guest build must:

- use KVM, not the non-release TCG fallback;
- finish the unattended Omarchy installation offline from pinned inputs;
- preserve deferred first-owner provisioning;
- pass the read-only secret, account, machine-ID, history, key and package audit;
- emit the compressed/split factory, expanded-payload digest, package lock,
  CycloneDX SBOM, licence inventory/text archive, notices and provenance.

Stop if the exact guest cannot be reproduced, any sanitisation check fails, or
the licence inventory contains an unreviewed proprietary/custom term.

## 3. Build and audit the portable runtime

On the hosted Windows release runner:

1. Verify every locked QEMU/Zstandard binary and source input.
2. Extract QEMU without executing its installer.
3. Retain only the intended x86-64 runtime while preserving every required DLL,
   firmware/data file and licence.
4. Add the pinned Zstandard CLI and generate the per-file manifest, capability
   contract, SPDX SBOM, provenance, source archive, source offer and notices.
5. Build twice where practical and compare deterministic output hashes.

The runtime pipeline currently records many linked dependency licence/source
fields as `NOASSERTION`. That is a release blocker, not harmless metadata.
Resolve each shipped dependency or replace the runtime with a fully locked
source-built distribution before broad publication.

## 4. Construct the factory release manifest

After both asset sets are final:

1. Record ordered part names, immutable tag URLs, sizes and SHA-256 values.
2. Record assembled archive size/SHA-256 and extracted payload size/SHA-256.
3. Generate `factory/factory-release.json` with the exact product `buildId`.
4. Validate it against the closed schema and materialisation contracts.
5. Stage the exact parts in a draft release at the manifest's immutable tag.

Do not change an asset in place after generating the manifest. A changed byte
requires a new `buildId` and normally a new release tag/version.

## 5. Publish the native app

On Windows with the .NET 8 SDK:

```powershell
dotnet publish .\windows\WindowsIntoOmarchy\WindowsIntoOmarchy.csproj `
  -c Release -r win-x64 --self-contained true -o .\dist\native-app
```

Verify that the result is a self-contained x64 WPF `WinExe`, carries the
approved original icon and launches without a console. Place
`WindowsIntoOmarchy.exe` at the installed application root beside the embedded
factory manifest and required scripts.

Run Windows PowerShell 5.1 parsing over every packaged helper. Confirm the
installer includes `scripts\experience\**`, runtime materialisation/audit
helpers, factory schema/manifest, current documentation and notices.

## 6. Compliance approval

Before signing, bind the review to the exact runtime and guest hashes. The
approval must cover:

- every shipped binary/file and its licence/notice;
- complete corresponding source or a valid source offer where required;
- proprietary/custom redistribution permission;
- guest sanitisation and ownership state;
- original branding and non-affiliation wording; and
- preservation/hosting commitments for source and notices.

Code signing is not compliance approval. A technically valid installer must
not be signed for public distribution while the binary/source map or guest
licence review is incomplete.

## 7. Build, sign and verify the installer

1. Build the per-user Inno Setup installer on Windows.
2. Confirm Start menu and optional desktop shortcuts target the native EXE.
3. Authenticode-sign and timestamp both the EXE and setup artifact.
4. Verify signatures after copying the artifacts to a clean machine.
5. Generate final SHA-256 files from the signed outputs; signing changes bytes.
6. Confirm uninstall preserves factory/VM data and explains that behaviour.

Unsigned outputs are engineering artifacts only.

## 8. Physical acceptance

Complete [windows-smoke-test.md](windows-smoke-test.md) against the exact signed
artifacts and staged factory assets. At minimum cover Windows 11 Home/Pro,
Intel/AMD, WHPX enable/restart/resume, standard-user elevation, factory
download, owner provisioning, second boot, 2D fallback, any claimed accelerated
display path, isolation, disposable mode and recoverable reset.

The fallback ISO/`cidata` path is tested separately. It cannot be substituted
for a failed or unavailable factory-default run.

## 9. Publish atomically

Only after every preceding gate passes:

1. Publish the immutable factory/runtime parts and their compliance artifacts.
2. Publish the signed installer, signed EXE hash, source archive and checksums.
3. Publish corresponding-source archives/offers for the same retained period as
   the binaries require.
4. Include measured hardware, download/storage figures, graphics evidence,
   limitations, unofficial status and recovery guidance in release notes.
5. Preserve all build logs, approvals, manifests and checklists.

Do not call the release stable if any asset is missing, unsigned, replaced after
review, untested on physical Windows or subject to unresolved compliance
entries.
