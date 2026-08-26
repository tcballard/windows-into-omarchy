# Launch handoff

- Product: Windows Into Omarchy
- Release: Windows Into Omarchy v0.1.0
- Version: 0.1.0
- Build: `1f3a6ccaa7c4a830dfebec532be0eca717d7b0c3bfd4fcff53d87a34917edcc4`
- Pack status: ready for source publication and draft release
- Publication authority: source, tag, and draft release authorised; public release not yet authorised
- Exact next action: commit source, tag v0.1.0, create and verify the draft release

## Included deliverables

| Channel | Output | Status | Claim IDs | Notes |
| --- | --- | --- | --- | --- |
| Repository | `README.md` and source tree | Ready | C01-C06 | Early-alpha boundary visible |
| GitHub release | v0.1.0 draft, ZIP and SHA256SUMS | Ready | C01-C06 | Do not publish before Windows acceptance decision |

## Omitted or not-applicable deliverables

- Website, social copy, demo video, store listing, marketplace, press package, and generated runtime screenshots.

## Claims

- Verified: C01, C02, C03, C06.
- Qualified: C04, C05.
- Blocked or removed: C07 is removed until a physical Windows installation reaches the desktop.

## Validation performed

- 15 contract tests passed.
- Embedded WPF XAML is well formed.
- Release archive opened without error and contains the canonical renamed entry points.
- Release SHA-256 matches `dist/SHA256SUMS`.
- Publisher Omarchy SHA-256 and QEMU SHA-512 were independently checked.

## Remaining decisions and blockers

- Run `docs/windows-smoke-test.md` on Windows 11 x64.
- Decide whether to publish v0.1.0 after the resulting evidence is recorded.
