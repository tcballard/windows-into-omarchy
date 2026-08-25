# Omarchy image pipeline

This directory owns two related artifacts:

1. `cidata/cidata.img` is the generated, deterministic FAT12 configuration
   drive used by the normal Windows first run. It invokes Omarchy's supported
   unattended installer and defers keyboard, username, password, and personal
   configuration until first owner boot.
2. `build.sh` is an optional release-gated accelerator. It uses that same
   drive to install the pinned official ISO into a clean QCOW2 disk ahead of
   time, then emits split, checksummed release assets.

The cidata drive contains exactly `user_configuration.json` and an empty
`defer-provisioning` marker. It intentionally contains no password hashes,
disk passphrases, SSH keys, Tailscale keys, Git identity, or network setup.

## Rebuild the cidata drive

Python is the only dependency:

```sh
python3 image/make_cidata.py
python3 image/make_cidata.py --check
python3 image/test_image_contracts.py
```

The generator implements the tiny FAT12 image directly, with fixed metadata
and allocation order. The Windows package build embeds the generated image
without requiring `mkfs.vfat`, `mtools`, or an ISO authoring utility.

## Build a prepared disk locally

The release builder requires Linux x86_64, QEMU 8+, KVM, OVMF without enrolled
Secure Boot keys, `jq`, `curl`, `zstd`, and GNU coreutils. `guestfish` from
libguestfs-tools is required by release CI for the offline identity audit.

```sh
WIO_REQUIRE_GUESTFISH=1 ./image/build.sh
```

The VM receives only four devices relevant to installation: blank QCOW2,
pinned official Omarchy ISO, read-only cidata, and copied OVMF variables. It
has no network adapter, host filesystem share, credentials, or CI token. The
official ISO installs from its bundled package mirror and requests a reboot;
`-no-reboot` makes that request the build completion boundary.

The output is compressed with zstd and split below GitHub's 2 GiB per-release-
asset ceiling. `build-manifest.json` records the complete compressed digest,
ordered part digests, source ISO identity, cidata identity, QEMU version, OVMF
digest, and source revision. `SHA256SUMS` covers the manifest and every part.

The recipe is repeatable and all executable inputs are recorded or pinned.
The installed filesystem is not claimed to be byte-for-byte reproducible:
Omarchy, Arch, Btrfs, and QEMU legitimately generate filesystem UUIDs and
other entropy during installation.

## GitHub workflow

`image-contracts.yml` runs VM-free validation on pull requests and pushes.
`build-image.yml` is manual-only and accepts trusted `main` code only. The
heavy build runs on a dedicated self-hosted runner labelled
`omarchy-image-builder`; pull-request code can never target that runner.

The workflow always uploads a short-lived Actions artifact. Its optional
release stage is separately protected by the `image-release` environment and
creates a **draft** release only. A human must review the manifest, checksums,
first-owner boot on Windows, third-party notices, and distribution obligations
before publishing that draft.
