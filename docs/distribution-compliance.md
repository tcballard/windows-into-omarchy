# Distribution compliance plan

> Engineering compliance record, updated 2026-08-26. This is not legal advice.
> It identifies release evidence and stop conditions; obtain qualified advice
> before commercialisation, store distribution or broad promotion.

## What “legal/compliance” means here

There is no known rule that prevents building a Windows application which runs
Omarchy in QEMU. The issue is **what this project redistributes**.

The MIT licence on Windows Into Onarchy's original code covers only that code.
It does not grant permission for the QEMU executable and DLLs, firmware, Linux
kernel, Arch packages, fonts, applications, artwork or other files inside the
portable runtime and completed guest disk.

For a binary release, compliance therefore means answering, for every shipped
file:

1. who owns it and under which licence it is distributed;
2. whether binary redistribution is permitted and under which conditions;
3. which copyright notices and licence texts must accompany it;
4. whether complete corresponding source, installation information or a source
   offer must accompany or remain available for it;
5. whether proprietary/custom terms, export/geographic limits or branding
   conditions apply; and
6. whether the exact image is sanitised and free of credentials or identities.

Authenticode answers “who signed these bytes?” It does not answer any of those
licensing questions and does not create redistribution rights.

Giving a binary only to testers can still be distribution under applicable
licences. “RC”, “free”, “open source” and “non-commercial” are not automatic
exemptions.

## Product decision

The earlier v0.2 design avoided most redistribution by downloading the official
Omarchy ISO and QEMU installer directly on the user's PC. That route remains a
developer/recovery fallback and has a smaller compliance surface, but it does
not provide the Mac-like first-run experience required for v0.3.

The v0.3 default deliberately distributes two independently versioned assets:

- a portable QEMU/Zstandard Windows runtime; and
- an unowned, preinstalled Omarchy/Arch factory disk.

That is technically the right product shape, but it activates the full runtime
and guest redistribution obligations. The source implementation may be merged
and reviewed while binary publication remains blocked.

## Release components and present position

| Component | v0.3 delivery | Present compliance position |
| --- | --- | --- |
| Windows Into Onarchy code and native app | Signed per-user installer | Original code is MIT; include `LICENSE` and preserve third-party separation. |
| Portable QEMU runtime | Split, pinned ZIP parts downloaded by the app | QEMU/Zstandard inputs, source bundles, SBOM and provenance are pinned. The exact QEMU dependency/data set still contains linked DLL/firmware entries whose licence/source mapping must be completed. |
| Omarchy factory | Split, pinned Zstandard-compressed QCOW2 | Guest pipeline emits package lock, SBOM, licence inventory/text archive, notices, provenance and sanitisation audit. The actual release image must be built on protected KVM and its exact output reviewed before publication. |
| WHPX | Windows host feature | No Microsoft WHPX binary is redistributed. |
| ISO/`cidata` fallback | Direct locked upstream downloads on the user's PC | Not part of the factory-default package; retain upstream digests, unofficial wording and credential-free configuration. |

## Portable runtime obligations

QEMU describes the emulator as GPL-2.0 and notes that bundled firmware consists
of separate programs under separate licences. The selected Windows distribution
also carries many dynamically linked libraries and data/firmware files. The
runtime build currently discovers 114 linked DLLs; generated SBOM entries with
`NOASSERTION` are a list of unresolved work, not a compliance conclusion.

Before distributing that runtime:

1. Bind every shipped binary, DLL, firmware, ROM, font and data file to its
   exact source revision, licence and required notices.
2. Supply complete corresponding source in the required form, or a legally
   valid written offer where the licence permits that route. Keep it available
   for the required period.
3. Include GPL-2.0 and every additional licence/notice in the downloadable
   release and installed product.
4. Confirm that extracting/repackaging the chosen upstream Windows build does
   not omit installer-provided notices or source information.
5. Preserve QEMU and Zstandard as separate command-line programs; do not imply
   endorsement or use their marks as this project's identity.
6. Review the final per-file manifest after every runtime update. A new QEMU
   build is a new compliance transaction.

One robust alternative is a fully locked source build in controlled Windows CI
with its dependency sources captured at build time. Using an upstream binary is
also possible, but only if the exact binary-to-source and notice set can be
proved and redistributed correctly.

Mere aggregation with a separate MIT launcher does not automatically relicense
the launcher's independent code under the GPL. Modifications to QEMU and any
combined/derived work must follow their applicable licences.

## Guest factory obligations

Omarchy's repository code is MIT licensed, but an installed disk is not merely
the Omarchy repository. It contains the kernel, firmware, Arch packages,
Omarchy components, applications, fonts, themes and potentially unowned files
under many licences.

For example, Omarchy package sets have included applications such as Obsidian,
whose Arch metadata uses a custom/proprietary licence reference. That example
does not prove a particular release image is forbidden; it proves that MIT
alone is insufficient. The exact factory package lock and filesystem inventory
must determine the answer. Do not assume that a package's availability in Arch
means it may be mirrored inside a VM image without conditions.

The releasable factory must provide and pass review for:

1. every installed package/version/source and every file not owned by a package;
2. applicable licence texts, copyright notices and redistribution conditions;
3. corresponding source/build information for copyleft components;
4. explicit approval or removal for proprietary/custom-licence components whose
   redistribution position is unclear;
5. generated package lock, CycloneDX SBOM, licence inventory/text archive,
   notices and provenance bound to the expanded QCOW2 digest; and
6. sanitisation evidence covering owner/build accounts, passwords, SSH host and
   user keys, Tailscale/cloud tokens, machine IDs, shell history, logs, caches,
   package-signing state, installer secrets and unowned files.

The first-owner flow is also a security/privacy release gate: the factory must
be unowned and generic, then create personal identity only after it reaches the
user's Windows machine.

## Current technical evidence

The repository now contains mechanisms to produce:

- immutable part/archive/payload SHA-256 identities;
- a protected KVM-only guest release workflow;
- guest package lock, SBOM, licence inventory/texts, notices and provenance;
- guest credential, account and machine-identity audits;
- portable runtime per-file hashes, SPDX SBOM, provenance and source bundles;
- QEMU/Zstandard source manifests and a source-offer template; and
- fail-closed host capability evidence.

Those mechanisms are valuable but are not self-certifying. In this workspace,
the multi-gigabyte KVM guest was not built and the exact final runtime dependency
licence/source set has not been cleared. No public binary release is approved by
this document.

## Names and marks

Omacom has announced that it holds the Omarchy trademarks; no public policy
authorising this product name was identified during the engineering review.
Continue to:

- state prominently that Windows Into Onarchy is independent and unofficial;
- use the project's original icon and artwork, not Omarchy, Arch, QEMU,
  Microsoft or Try Omarchy logos;
- use third-party names only to describe compatibility/components; and
- obtain written confirmation from the relevant trademark holder before broad
  promotion, store submission or commercial use of **Windows Into Onarchy**.

A non-affiliation statement reduces confusion but is not trademark permission.

## Release stop/go gate

Public binary distribution is blocked until every row is evidenced for the
exact final hashes:

| Gate | Required evidence |
| --- | --- |
| Runtime inventory complete | Per-file manifest and SBOM contain every shipped file. |
| Runtime licence/source map complete | No unresolved shipped dependency or `NOASSERTION`; required source/notices are packaged and retained. |
| Guest inventory complete | Exact KVM-built QCOW2 package/file inventory, SBOM and package lock. |
| Guest licence review complete | Every proprietary/custom term reviewed and permitted or component removed. |
| Guest source/notices complete | Corresponding source/offers, licence texts and notices match the guest digest. |
| Guest sanitised | Audit proves deferred ownership and absence of reusable identity/secrets. |
| Branding reviewed | Original assets, unofficial wording and trademark decision recorded. |
| Technical identity locked | Part, archive, payload, manifest, EXE and installer hashes agree. |
| Physical acceptance passed | Exact signed release completes the Windows checklist on required hardware. |

If any shipped byte changes after review, rerun the affected gates. If these
answers cannot be obtained for the factory distribution, the legally simpler
fallback is to return the consumer release to direct official ISO/QEMU
downloads—even though that sacrifices the desired first-run speed.

## Upstream references

- [Omarchy unattended installs](https://github.com/basecamp/omarchy/blob/quattro/manual/51-unattended-installs.md)
- [Omarchy v4.0.1 release](https://github.com/basecamp/omarchy/releases/tag/v4.0.1)
- [Omarchy MIT licence](https://github.com/basecamp/omarchy/blob/quattro/LICENSE)
- [Arch Obsidian licence metadata](https://archlinux.org/packages/extra/x86_64/obsidian/)
- [QEMU licensing](https://www.qemu.org/docs/master/about/license.html)
- [QEMU Windows builds](https://qemu.weilnetz.de/w64/)
- [Omacom Foundation announcement](https://omarchy.org/news/2026/08/omacom-foundation-launches-with-8-million/)
