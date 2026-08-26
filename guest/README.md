# x86_64 factory guest

This subtree builds the prepared, unowned Omarchy disk used by the
frictionless Windows path. It takes the checksum-pinned official Omarchy ISO,
installs it without a network adapter using Omarchy's documented
`defer-provisioning` mode, and stops at the guest's reboot request. The next
boot is therefore the real Omarchy first-owner flow: there is no username,
password, SSH key, Tailscale key, or personal configuration in the factory
disk.

The Mac project has to assemble an ARM64 Arch filesystem because Basecamp does
not publish an ARM64 Omarchy install image. Copying that pacstrap approach to
Windows would add a second, subtly different x86 distribution. Here the safer
x86_64 equivalent is to boot the pinned official ISO and exercise its own
offline unattended installer. The build still borrows the important release
ideas—unowned factory state, complete package inventory, licence capture,
provenance, deterministic metadata, and a content-addressed runtime contract—
without replacing Omarchy's supported installation path.

Unlike the older `image/` proof, this is a distribution-shaped pipeline. A
successful build emits:

- a zstd-compressed QCOW2 factory disk, split into ordered parts below GitHub's
  2 GiB per-asset limit;
- `manifest.json`, a stable launcher contract and complete part list;
- a CycloneDX 1.6 package SBOM and a human-readable package inventory;
- installed package license expressions and the guest's packaged license-text
  tree;
- build provenance, source/firmware/tool hashes, and `SHA256SUMS`;
- a read-only disk audit proving the deferred-owner and no-identity boundary.

Windows assembles `omarchy-factory-x86_64.qcow2.zst`, verifies it, expands it
to the manifest-pinned `omarchy-factory.qcow2`, verifies that second digest,
and keeps it at `Factory/<buildId>/guest/omarchy-factory.qcow2`. It then
creates the persistent owner disk at `VM/<buildId>/omarchy.qcow2` as a QCOW2
overlay:

```powershell
qemu-img create -f qcow2 -F qcow2 -b <absolute-factory.qcow2> omarchy.qcow2
```

That operation is instant and keeps reset safe: delete only the owner overlay,
never the verified base. The base must remain at the same absolute path while
an overlay refers to it.

## Build

The heavy build requires Linux x86_64, `/dev/kvm`, QEMU 8+, OVMF, guestfish,
GNU tar, zstd, curl, jq, and Python 3:

```sh
WIO_FACTORY_REQUIRE_KVM=1 ./guest/build.sh --output-dir /tmp/omarchy-factory
```

The ISO download is HTTPS-only and verified before execution. The VM receives
no NIC, host share, CI credential, or physical disk. Build tools and firmware
are measured into `provenance.json`; guest inputs are immutable in `spec.json`.
The recipe is reproducible, but the filesystem image is not claimed to be
byte-for-byte reproducible because Arch, Btrfs, QEMU, and the installer create
UUIDs and other legitimate entropy.

Run VM-free contracts anywhere:

```sh
python3 guest/tests/test_factory_contracts.py
bash -n guest/build.sh guest/audit.sh guest/extract-metadata.sh
```

## Release boundary

Automation can create only a draft candidate. Publication additionally needs:

1. verification of every checksum and the assembled image digest;
2. first-owner boot and reset tests on a physical Windows WHPX machine;
3. review of the SBOM, installed license expressions, archived license texts,
   and corresponding-source obligations;
4. confirmation that no user or machine identity is present.

The SBOM and license material make review possible; they are not by themselves
legal approval to redistribute the complete Arch/Omarchy filesystem.
