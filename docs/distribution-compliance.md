# Distribution compliance plan

> Engineering compliance note, last reviewed 2026-08-25. This is not legal
> advice. Recheck the locked versions and obtain qualified advice before a
> commercial or broadly promoted release.

## Decision

Windows Into Omarchy should make first run automatic by installing from the
official, checksum-verified Omarchy ISO on the user's machine. It should not
publish a preinstalled Omarchy disk image.

Omarchy Quattro officially supports this flow. When the installer sees a
second drive labelled `cidata`, it can skip the installer wizard and reboot
into the installed system. Its `defer-provisioning` mode avoids carrying a
person's credentials in that drive and defers owner setup until first boot.

This preserves the desired download-to-desktop experience while avoiding a
new redistribution of the complete Arch/Omarchy guest filesystem.

Authoritative upstream references:

- [Omarchy unattended installs](https://github.com/basecamp/omarchy/blob/quattro/manual/51-unattended-installs.md)
- [Omarchy v4.0.1 release and ISO digest](https://github.com/basecamp/omarchy/releases/tag/v4.0.1)
- [Omarchy MIT license](https://github.com/basecamp/omarchy/blob/quattro/LICENSE)
- [Omarchy 4.0.1 base package manifest](https://github.com/basecamp/omarchy/blob/v4.0.1/install/omarchy-base.packages)
- [Arch Obsidian package license metadata](https://archlinux.org/packages/extra/x86_64/obsidian/)
- [Arch NVIDIA utilities license metadata](https://archlinux.org/packages/extra/x86_64/nvidia-utils/)
- [QEMU licensing](https://www.qemu.org/docs/master/about/license.html)
- [QEMU 11.1.0 release](https://www.qemu.org/2026/08/11/qemu-11-1-0/)
- [QEMU Windows builds](https://qemu.weilnetz.de/w64/)
- [Omacom Foundation trademark announcement](https://omarchy.org/news/2026/08/omacom-foundation-launches-with-8-million/)

## Release architecture

| Component | Delivery | Compliance position |
| --- | --- | --- |
| Windows Into Omarchy code | Our signed installer | MIT; include this project's `LICENSE`. |
| Omarchy | Download the official locked ISO directly to the user's machine, then verify its published SHA-256 | Do not mirror, modify, repackage, or embed it in our release. Retain the non-affiliation notice. |
| Guest installation | Build a tiny local `cidata` drive and let the official ISO install to a new local QCOW2 disk | The resulting disk is made for that user and is not redistributed by this project. Prefer `defer-provisioning`; never put reusable credentials, SSH keys, or Tailscale keys in a published image. |
| QEMU | For the first public one-click build, download the locked upstream Windows installer directly and automate an app-local installation only if its installer supports that safely | Avoid mirroring or embedding the binary until the source/notice bundle described below exists. Verify SHA-512 before execution. |
| WHPX | Use the Windows feature already present on the host | No Microsoft binary is redistributed. |

Downloading directly from an upstream publisher is not a substitute for
technical supply-chain controls. Every executable and ISO must remain pinned
by a cryptographic digest, and changes to a URL, version, digest, or publisher
must pass release review.

## Why a prepared QCOW2 is not the first release path

The Omarchy repository code is MIT licensed, and its copyright and permission
notice can be carried straightforwardly. A completed disk, however, also
contains the Linux kernel, firmware, Arch packages, Omarchy packages, fonts,
artwork, and applications under many different licenses.

The Omarchy 4.0.1 base package manifest includes, among many open-source
packages, `obsidian`; Arch identifies that package as
`LicenseRef-Obsidian`. Hardware-dependent installation can also add packages
such as NVIDIA utilities, which Arch identifies as
`LicenseRef-NVIDIA-Driver-License-Agreement`. Those examples do not prove
redistribution is forbidden, but they do prove that the Omarchy repository's
MIT license alone cannot authorize redistribution of a completed disk.

Publishing a preinstalled disk is therefore blocked until all of the
following evidence exists:

1. A machine-readable inventory of every installed package and every file not
   owned by a package, generated from the exact release image.
2. The applicable license text and required copyright notices for each item.
3. A review of every proprietary or custom license for binary redistribution,
   including any geographic or branding restrictions.
4. Complete corresponding source, build instructions, and any required source
   offer for all copyleft binaries, retained for the required period.
5. An image-sanitisation attestation covering credentials, machine IDs, shell
   history, SSH host keys, logs, caches, package signing state, and installer
   secrets.
6. Written trademark/branding approval where the final presentation could
   reasonably look official.

The official unattended installer makes this work unnecessary for the
intended release, so a prepared QCOW2 should be treated as a later optional
distribution project rather than a v0.2 dependency.

## If QEMU is bundled later

QEMU states that the emulator as a whole is GPL-2.0 and that the firmware
distributed with it consists of separate programs under separate licenses.
QEMU also identifies `QEMU` as a trademark of Fabrice Bellard. The Windows
download page identifies Stefan Weil's packages as experimental builds, links
their build sources, and currently says newer installers are signed with an
expired certificate.

Bundling a portable QEMU runtime is manageable, but the release must not rely
only on a link to a moving branch. Before bundling it:

1. Build from an immutable source commit under our own reproducible Windows CI,
   or obtain the exact immutable source revision and dependency inputs that
   correspond to the selected upstream binary.
2. Publish or accompany the binary with complete corresponding source in a
   GPL-2.0-compliant form. Preserve it for every binary release; do not assume
   that an upstream branch or package mirror will retain the required version.
3. Include GPL-2.0 plus every license and notice belonging to the DLLs,
   firmware, ROMs, fonts, and other files actually shipped.
4. Generate an SBOM and a binary-to-source manifest, then gate packaging on
   their completeness.
5. Keep QEMU as a separate program invoked through its command line. Do not
   claim QEMU endorsement, and do not use its logo as this project's identity.
6. Authenticode-sign our installer and binaries we build. Do not present the
   expired signature on the current third-party installer as a current trust
   signal; the pinned digest is the release identity currently enforced.

Bundling QEMU does not by itself require this project's independent launcher
code to change from MIT merely because the two programs are distributed
together. Changes made to QEMU itself must, of course, be shipped under its
applicable license with corresponding source.

## Names and marks

The Omacom Foundation announced that it will hold the Omarchy trademarks. No
public trademark-use policy was found during this review. Continue to:

- describe the project prominently as independent and unofficial;
- use original Windows Into Omarchy artwork rather than the Omarchy, Arch,
  QEMU, or Microsoft logos;
- use third-party names only to explain compatibility or the components being
  run; and
- seek written permission or confirmation from the Omarchy trademark holder
  before broad promotion, store distribution, or commercialisation of the
  name **Windows Into Omarchy**.

The existing non-affiliation statement is useful but is not permission to use
a trademark.

## Release gate

The automatic-install release may ship when all answers in the left column are
yes:

| Gate | Evidence |
| --- | --- |
| Official ISO is downloaded, not redistributed | Package inventory and network-contract test |
| ISO URL and SHA-256 match the locked upstream release | Lock-file test and release evidence |
| `cidata` is generated locally and contains no published credentials | Fixture inspection and secret scan |
| QEMU is downloaded from its identified upstream location | Network-contract test |
| QEMU SHA-512 is verified before any installer or executable starts | Negative digest test |
| Our installer contains the MIT license and current third-party notices | Package-content test |
| Product and installer clearly say independent/unofficial | Rendered installer review |
| No third-party logo is used as product identity | Asset inventory review |

If either the Omarchy ISO or QEMU becomes embedded in our downloadable
artifact, this release gate is no longer sufficient: stop the release and run
the full redistribution audit above.
