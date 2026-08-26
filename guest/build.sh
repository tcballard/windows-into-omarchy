#!/usr/bin/env bash
set -euo pipefail

GUEST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$GUEST_DIR/.." && pwd)
SPEC="$GUEST_DIR/spec.json"
OUTPUT_DIR="$ROOT/dist/guest"
CACHE_DIR="$GUEST_DIR/.cache"
ISO_OVERRIDE=""
ACCEL=kvm

usage() {
  cat <<'EOF'
Usage: guest/build.sh [options]

  --output-dir DIR  Release-candidate output (default: dist/guest)
  --cache-dir DIR   Verified ISO cache (default: guest/.cache)
  --iso FILE        Use a local ISO; its pinned SHA-256 is still required
  --accel kvm|tcg   KVM for releasable builds; TCG for non-release smoke only
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR=${2:?missing output directory}; shift 2 ;;
    --cache-dir) CACHE_DIR=${2:?missing cache directory}; shift 2 ;;
    --iso) ISO_OVERRIDE=${2:?missing ISO path}; shift 2 ;;
    --accel) ACCEL=${2:?missing accelerator}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ $ACCEL == kvm || $ACCEL == tcg ]] || { echo "--accel must be kvm or tcg" >&2; exit 2; }
if [[ ${WIO_FACTORY_REQUIRE_KVM:-0} == 1 && $ACCEL != kvm ]]; then
  echo "release builds require --accel kvm" >&2
  exit 1
fi
if [[ $ACCEL == kvm && ! -c /dev/kvm ]]; then
  echo "/dev/kvm is required for a KVM factory build" >&2
  exit 1
fi
for command in curl guestfish jq python3 qemu-img qemu-system-x86_64 sha256sum split stat tar timeout zstd; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || {
  echo "factory builds require Linux x86_64" >&2
  exit 1
}

ISO_URL=$(jq -er '.source.isoUrl' "$SPEC")
ISO_SHA=$(jq -er '.source.isoSha256' "$SPEC")
ISO_VERSION=$(jq -er '.source.version' "$SPEC")
DISK_GIB=$(jq -er '.image.virtualSizeGiB' "$SPEC")
CLUSTER_SIZE=$(jq -er '.image.clusterSize' "$SPEC")
COMPRESSED_NAME=$(jq -er '.image.compressedFilename' "$SPEC")
PART_MIB=$(jq -er '.image.partSizeMiB' "$SPEC")
ZSTD_LEVEL=$(jq -er '.image.compressionLevel' "$SPEC")
MEMORY_MIB=$(jq -er '.runtime.memoryMiB' "$SPEC")
CPU_COUNT=$(jq -er '.runtime.cpuCount' "$SPEC")
TIMEOUT_SECONDS=$(jq -er '.builder.installTimeoutSeconds' "$SPEC")
CIDATA="$ROOT/$(jq -er '.cidata.path' "$SPEC")"
CIDATA_SHA=$(jq -er '.cidata.sha256' "$SPEC")

python3 "$ROOT/image/make_cidata.py" --check >/dev/null
echo "$CIDATA_SHA  $CIDATA" | sha256sum --check --status || {
  echo "cidata does not match the factory spec" >&2
  exit 1
}

find_firmware() {
  local selector=$1 candidate
  while IFS= read -r candidate; do
    [[ -f $candidate && ! -L $candidate ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done < <(jq -er "$selector[]" "$SPEC")
  return 1
}
OVMF_CODE=$(find_firmware '.builder.ovmfCodeCandidates') || { echo "OVMF code image not found" >&2; exit 1; }
OVMF_VARS=$(find_firmware '.builder.ovmfVarsCandidates') || { echo "OVMF variables template not found" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"
if find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo "output directory must be empty: $OUTPUT_DIR" >&2
  exit 1
fi
if [[ -n $ISO_OVERRIDE ]]; then
  ISO=$ISO_OVERRIDE
else
  ISO="$CACHE_DIR/omarchy-$ISO_VERSION.iso"
  if [[ ! -f $ISO ]]; then
    PARTIAL="$ISO.partial.$$"
    trap 'rm -f -- "${PARTIAL:-}"' EXIT
    curl --fail --location --proto '=https' --tlsv1.2 --retry 5 --retry-all-errors \
      --connect-timeout 30 --output "$PARTIAL" "$ISO_URL"
    echo "$ISO_SHA  $PARTIAL" | sha256sum --check --status || {
      echo "downloaded Omarchy ISO failed verification" >&2
      exit 1
    }
    mv -- "$PARTIAL" "$ISO"
    trap - EXIT
  fi
fi
[[ -f $ISO && ! -L $ISO ]] || { echo "ISO is missing or a symlink: $ISO" >&2; exit 1; }
echo "$ISO_SHA  $ISO" | sha256sum --check --status || { echo "ISO failed pinned SHA-256" >&2; exit 1; }

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/onarchy-factory.XXXXXX")
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$BUILD_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BUILD_DISK="$BUILD_DIR/factory.building.qcow2"
FACTORY_DISK="$BUILD_DIR/omarchy-factory.qcow2"
COMPRESSED="$BUILD_DIR/$COMPRESSED_NAME"
FIRMWARE_VARS="$BUILD_DIR/OVMF_VARS.fd"
SERIAL_LOG="$BUILD_DIR/install-serial.log"
cp -- "$OVMF_VARS" "$FIRMWARE_VARS"
qemu-img create -q -f qcow2 -o "compat=1.1,cluster_size=$CLUSTER_SIZE,lazy_refcounts=on" "$BUILD_DISK" "${DISK_GIB}G"
CPU_MODEL=max
[[ $ACCEL == kvm ]] && CPU_MODEL=host

echo "Installing pinned Omarchy $ISO_VERSION into an offline factory disk ($ACCEL)..."
set +e
timeout --signal=TERM --kill-after=30s "${TIMEOUT_SECONDS}s" \
  qemu-system-x86_64 \
    -name 'Windows Into Onarchy factory builder' \
    -machine "q35,accel=$ACCEL" -cpu "$CPU_MODEL" -smp "$CPU_COUNT" -m "$MEMORY_MIB" \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$FIRMWARE_VARS" \
    -drive "file=$BUILD_DISK,format=qcow2,if=none,id=factory,cache=writeback,discard=unmap" \
    -device virtio-blk-pci,drive=factory,bootindex=1 \
    -drive "file=$ISO,format=raw,media=cdrom,if=none,readonly=on,id=installer" \
    -device ide-cd,drive=installer,bootindex=2 \
    -drive "file=$CIDATA,format=raw,if=none,readonly=on,id=cidata" \
    -device qemu-xhci,id=xhci -device usb-storage,drive=cidata,bus=xhci.0 \
    -device virtio-vga -device virtio-rng-pci \
    -nic none -display none -monitor none -serial "file:$SERIAL_LOG" \
    -boot order=cd,menu=off -no-reboot
QEMU_STATUS=$?
set -e
if [[ $QEMU_STATUS -ne 0 ]]; then
  echo "factory install failed or timed out (QEMU status $QEMU_STATUS)" >&2
  tail -n 100 "$SERIAL_LOG" >&2 || true
  exit 1
fi

qemu-img check -q "$BUILD_DISK"
qemu-img convert -p -O qcow2 -o "compat=1.1,cluster_size=$CLUSTER_SIZE,lazy_refcounts=on" \
  "$BUILD_DISK" "$FACTORY_DISK"
rm -f -- "$BUILD_DISK"
bash "$GUEST_DIR/audit.sh" "$FACTORY_DISK" "$SPEC"
bash "$GUEST_DIR/extract-metadata.sh" "$FACTORY_DISK" "$SPEC" "$OUTPUT_DIR" "$BUILD_DIR"
rm -rf -- "$BUILD_DIR/metadata"
python3 "$GUEST_DIR/scripts/write_provenance.py" \
  --spec "$SPEC" --iso "$ISO" --cidata "$CIDATA" \
  --ovmf-code "$OVMF_CODE" --ovmf-vars "$OVMF_VARS" \
  --factory-image "$FACTORY_DISK" \
  --output "$OUTPUT_DIR/provenance.json"

if [[ ${WIO_FACTORY_EPHEMERAL_CACHE:-0} == 1 && -z $ISO_OVERRIDE ]]; then
  rm -f -- "$ISO"
fi

zstd -q -T0 "-$ZSTD_LEVEL" --long=27 "$FACTORY_DISK" -o "$COMPRESSED"
split --bytes "${PART_MIB}MiB" --numeric-suffixes=0 --suffix-length=3 \
  "$COMPRESSED" "$OUTPUT_DIR/$COMPRESSED_NAME.part"
python3 "$GUEST_DIR/scripts/write_manifest.py" \
  --spec "$SPEC" --output-dir "$OUTPUT_DIR" \
  --factory-image "$FACTORY_DISK" --compressed-image "$COMPRESSED"
rm -f -- "$FACTORY_DISK" "$COMPRESSED"
(
  cd "$OUTPUT_DIR"
  sha256sum manifest.json provenance.json sbom.cdx.json packages.lock.tsv licenses.json \
    license-texts.tar.zst THIRD_PARTY_NOTICES.md "$COMPRESSED_NAME".part* > SHA256SUMS
  sha256sum --check SHA256SUMS
)
python3 "$GUEST_DIR/scripts/verify_release.py" --verify-expanded "$OUTPUT_DIR"
echo "Factory guest candidate complete: $OUTPUT_DIR"
