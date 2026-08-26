# Factory release contract

The frictionless release path is a small Windows application plus two immutable
release assets: a portable QEMU runtime and an unprovisioned x86_64 Omarchy
factory disk. The user sees one progress flow; the implementation keeps the
runtime and guest independently auditable.

`factory-release.json` is generated during a release from the exact built
artifacts. It is embedded in the Windows application and is therefore the
download trust root. It contains only versioned HTTPS URLs, ordered split-part
sizes and SHA-256 digests, final archive digests, output paths, and upstream
commit identities. Runtime code must never discover a `latest` release or
accept an unsigned replacement manifest from the network.

Materialised assets live under:

```text
%LOCALAPPDATA%\Windows Into Omarchy\Factory\<buildId>\
├── runtime\qemu\
├── guest\omarchy-factory.qcow2
└── receipt.json
```

The persistent machine is a QCOW2 overlay below `VM\<buildId>` backed by that
immutable factory disk. Updating to a new factory build creates a new versioned
workspace; it never boots an old overlay against a different base image.

The normal public asset size limit is handled with ordered parts. Each part is
verified before publication into the download cache, then the concatenated
archive is verified again before extraction. Partial or invalid data belongs in
`Quarantine`, never at its final path.

The ISO/cidata installer remains a development and recovery path. It is not the
normal factory-release experience.

## Release assembly

The manual `factory-release-v0.3.0` workflow is the only automated path that
joins the portable runtime and factory guest. It runs the two builders in
parallel, then `scripts/Assemble-FactoryRelease.ps1` independently verifies and
stages their exact output.

The assembly gate does not trust component `SHA256SUMS` files alone. It also:

- reconstructs the runtime ZIP from its ordered parts and checks every ZIP
  member against the runtime payload manifest;
- proves runtime provenance is bound to `portable-runtime.lock.json`;
- reconstructs the guest zstd stream from its ordered parts, expands it using
  the verified runtime's pinned `zstd.exe`, and hashes the resulting QCOW2;
- requires the guest source and lifecycle records to equal `guest/spec.json`;
- calls `factory/build_release_manifest.py` so sizes and digests in the embedded
  `factory-release.json` come from local bytes and exact repository/tag asset
  URLs;
- builds the native installer only after that manifest exists, then creates a
  fresh checksum set covering every staged release asset.

The last job is protected by the `factory-v0.3.0-draft` environment and can
only create a new draft. It refuses an existing tag or release and never
publishes, replaces, or updates one. Signing, physical Windows acceptance, and
distribution review remain later human gates.

`prepare-v0.3.0-rc.1-bootstrap-release` is the promotion path for the verified
candidate. It rehashes every split part and concatenated archive, retargets the
manifest to `v0.3.0-rc.1`, and builds an online bootstrap without the external
sidecar directive. The resulting draft still contains the supporting parts,
but a tester downloads only the installer after an owner publishes the
prerelease. Automation deliberately stops at a fully verified draft.
