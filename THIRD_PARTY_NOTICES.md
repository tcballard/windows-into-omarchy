# Third-party notices

Windows Into Omarchy downloads and runs third-party components. They retain
their own copyrights and licenses. The repository's MIT license applies only
to this project's original code.

- **Omarchy 4.0.1 project code** is distributed by Basecamp under the MIT
  License. Its installation ISO also contains Arch Linux and many separately
  licensed packages. The launcher downloads the official ISO from
  `iso.omarchy.org` and verifies the SHA-256 published with the v4.0.1 release
  before it can be launched. Installation automation uses Omarchy's documented
  `cidata`/`defer-provisioning` interface and does not modify the ISO.
- **QEMU 11.1.0** is GPL-2.0 and includes components under other compatible
  licenses. The launcher uses the Windows installer linked by QEMU's official
  download page and provided by Stefan Weil. It verifies the publisher's
  SHA-512 file before the installer can be executed silently. The Windows distribution
  site describes these builds as experimental and notes that the signing
  certificate is expired; the pinned cryptographic digest is therefore the
  release identity enforced by this project.
- **EDK II / OVMF firmware** is supplied by the selected QEMU distribution and
  retains its upstream licenses.
- **Windows Hypervisor Platform** is part of Microsoft Windows.

The Omarchy ISO and QEMU installer are not included in this source archive.
Distributors who bundle either component must independently satisfy its
license, notice, source-offer, and trademark obligations.

The optional prepared-image tooling is not permission to redistribute its
output. A completed guest disk contains many independently licensed packages
and remains release-blocked until the compliance gates documented in
`docs/distribution-compliance.md` are satisfied.

This project is independent and is not affiliated with or endorsed by
Basecamp, Omacom, Microsoft, QEMU, Stefan Weil, or the original Try Omarchy
project.
