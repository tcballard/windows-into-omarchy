# Third-party notices

Windows Into Onarchy's MIT licence applies only to this project's original
code. QEMU, firmware, Zstandard, Omarchy, Arch Linux and every package/file in
the guest retain their own copyrights, licences and marks.

This repository file is a high-level notice, **not the complete notice set for
a binary factory release**. A distributable v0.3 release must also carry the
generated, hash-bound runtime and guest licence texts, notices, SBOMs,
binary-to-source manifests and corresponding-source/source-offer materials.
Publication is blocked while any shipped dependency remains unresolved.

## Factory-default components

- **QEMU 11.1.0** is licensed as described by QEMU, including GPL-2.0 for the
  emulator as a whole and separate licences for firmware and other programs.
  The portable Windows runtime additionally contains linked libraries and data
  files under their own terms. Repackaging an upstream Windows build requires
  review of every file actually shipped, not only QEMU's top-level licence.
- **Zstandard 1.5.7** is delivered as a separate CLI used to expand the pinned
  factory disk. Its licence, exact source and notices must accompany the
  selected binary.
- **EDK II/OVMF and other firmware/data** come from the portable QEMU payload
  and retain their upstream licences.
- **Omarchy 4.0.1 project code** is published by Basecamp under the MIT
  License. The factory filesystem also contains Arch Linux and many separately
  licensed packages. Omarchy's MIT licence is not a licence for the entire
  installed disk.
- **Windows Hypervisor Platform** is part of Microsoft Windows and is enabled
  on the host; this project does not redistribute the WHPX implementation.

The factory build pipeline generates the precise package lock, file/package
inventory, licence text archive, notices, SBOM and provenance required for the
guest. The portable-runtime pipeline generates the equivalent per-file
evidence and source bundle for its payload. Those exact generated outputs—not
this summary—must be reviewed and published with the matching binaries.

## Developer/recovery fallback

The fallback downloads the official locked Omarchy ISO and identified QEMU
Windows installer directly on the user's machine and verifies their published
digests. It does not modify the ISO. Automation uses Omarchy's documented
credential-free `cidata`/`defer-provisioning` contract.

This fallback has a different redistribution position because those large
upstream binaries are not embedded in this project's installer. It remains
subject to accurate attribution, upstream terms and supply-chain verification,
and it is not the v0.3 public product experience.

## Marks and independence

Windows Into Onarchy uses original artwork. It is independent and is not
affiliated with or endorsed by Basecamp, Omacom, Arch Linux, Microsoft, QEMU,
Zstandard, Stefan Weil or the original Try Omarchy project. Third-party names
are used only to identify compatibility or components.

See [docs/distribution-compliance.md](docs/distribution-compliance.md) for the
release stop/go criteria and upstream references.
