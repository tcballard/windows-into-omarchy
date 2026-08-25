#!/usr/bin/env bash
set -euo pipefail

IMAGE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$IMAGE_DIR/.." && pwd)
LOCK="$IMAGE_DIR/image.lock.json"
OUTPUT_DIR="$IMAGE_DIR/output"
CACHE_DIR="$IMAGE_DIR/cache"
ACCEL=kvm
ISO_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: image/build.sh [options]

Options:
  --output-dir DIR   Artifact destination (default: image/output)
  --cache-dir DIR    Verified ISO cache (default: image/cache)
  --iso FILE         Use an already-downloaded ISO; its hash is still checked
  --accel kvm|tcg    QEMU accelerator (release builds require kvm)
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
if [[ $ACCEL == kvm && ! -c /dev/kvm ]]; then
  echo "KVM is required for a release build; /dev/kvm is unavailable" >&2
  exit 1
fi

for command in curl jq python3 qemu-img qemu-system-x86_64 sha256sum split timeout zstd; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done

SOURCE_VERSION=$(jq -er '.source.version' "$LOCK")
SOURCE_URL=$(jq -er '.source.url' "$LOCK")
SOURCE_SHA256=$(jq -er '.source.sha256' "$LOCK")
DISK_GIB=$(jq -er '.guest.virtualDiskGiB' "$LOCK")
MEMORY_MIB=$(jq -er '.guest.memoryMiB' "$LOCK")
CPU_COUNT=$(jq -er '.guest.cpuCount' "$LOCK")
TIMEOUT_SECONDS=$(jq -er '.builder.installTimeoutSeconds' "$LOCK")
ZSTD_LEVEL=$(jq -er '.artifact.zstdLevel' "$LOCK")
CHUNK_MIB=$(jq -er '.artifact.chunkMiB' "$LOCK")
CIDATA_SHA256=$(jq -er '.cidata.sha256' "$LOCK")
CIDATA="$IMAGE_DIR/cidata/cidata.img"

python3 "$IMAGE_DIR/make_cidata.py" --check >/dev/null
echo "$CIDATA_SHA256  $CIDATA" | sha256sum --check --status

QEMU_MAJOR=$(qemu-system-x86_64 --version | sed -nE '1s/.*version ([0-9]+).*/\1/p')
MINIMUM_QEMU_MAJOR=$(jq -er '.builder.minimumQemuMajor' "$LOCK")
[[ $QEMU_MAJOR =~ ^[0-9]+$ && $QEMU_MAJOR -ge $MINIMUM_QEMU_MAJOR ]] || {
  echo "QEMU $MINIMUM_QEMU_MAJOR or newer is required" >&2
  exit 1
}

find_firmware() {
  local selector=$1 candidate
  while IFS= read -r candidate; do
    if [[ -f $candidate && ! -L $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(jq -er "$selector[]" "$LOCK")
  return 1
}

OVMF_CODE=$(find_firmware '.builder.ovmfCodeCandidates') || {
  echo "No supported OVMF code image was found" >&2
  exit 1
}
OVMF_VARS=$(find_firmware '.builder.ovmfVarsCandidates') || {
  echo "No supported OVMF variables template was found" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"
if [[ -n $ISO_OVERRIDE ]]; then
  ISO=$ISO_OVERRIDE
else
  ISO="$CACHE_DIR/omarchy-$SOURCE_VERSION.iso"
  if [[ ! -f $ISO ]]; then
    PARTIAL="$ISO.partial.$$"
    trap 'rm -f -- "${PARTIAL:-}"' EXIT
    curl --fail --location --proto '=https' --tlsv1.2 \
      --retry 5 --retry-all-errors --connect-timeout 30 \
      --output "$PARTIAL" "$SOURCE_URL"
    echo "$SOURCE_SHA256  $PARTIAL" | sha256sum --check --status || {
      echo "Downloaded Omarchy ISO failed SHA-256 verification" >&2
      exit 1
    }
    mv -- "$PARTIAL" "$ISO"
    trap - EXIT
  fi
fi
[[ -f $ISO && ! -L $ISO ]] || { echo "ISO is missing or is a symlink: $ISO" >&2; exit 1; }
echo "$SOURCE_SHA256  $ISO" | sha256sum --check --status || {
  echo "Omarchy ISO does not match the pinned SHA-256" >&2
  exit 1
}

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/windows-into-omarchy-image.XXXXXX")
cleanup() {
  local status=$?
  trap - EXIT
  rm -rf -- "$BUILD_DIR"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

BUILD_DISK="$BUILD_DIR/omarchy.qcow2.building"
COMPACT_DISK="$BUILD_DIR/omarchy.qcow2"
FIRMWARE_VARS="$BUILD_DIR/OVMF_VARS.fd"
SERIAL_LOG="$BUILD_DIR/install-serial.log"
cp -- "$OVMF_VARS" "$FIRMWARE_VARS"
qemu-img create -q -f qcow2 "$BUILD_DISK" "${DISK_GIB}G"

if [[ $ACCEL == kvm ]]; then
  CPU_MODEL=host
else
  CPU_MODEL=max
fi

echo "Installing pinned Omarchy $SOURCE_VERSION into a private ${DISK_GIB} GiB image..."
set +e
timeout --signal=TERM --kill-after=30s "${TIMEOUT_SECONDS}s" \
  qemu-system-x86_64 \
    -name 'Windows Into Onarchy image builder' \
    -machine "q35,accel=$ACCEL" \
    -cpu "$CPU_MODEL" \
    -smp "$CPU_COUNT" \
    -m "$MEMORY_MIB" \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
    -drive "if=pflash,format=raw,file=$FIRMWARE_VARS" \
    -drive "file=$BUILD_DISK,format=qcow2,if=none,id=drive0,cache=writeback,discard=unmap" \
    -device virtio-blk-pci,drive=drive0,bootindex=1 \
    -drive "file=$ISO,media=cdrom,if=none,format=raw,readonly=on,id=cdrom0" \
    -device ide-cd,drive=cdrom0,bootindex=2 \
    -drive "file=$CIDATA,format=raw,if=none,readonly=on,id=cidata" \
    -device qemu-xhci,id=xhci \
    -device usb-storage,drive=cidata,bus=xhci.0 \
    -device virtio-vga \
    -device virtio-rng-pci \
    -nic none \
    -display none \
    -monitor none \
    -serial "file:$SERIAL_LOG" \
    -boot order=cd,menu=off \
    -no-reboot
QEMU_STATUS=$?
set -e

if [[ $QEMU_STATUS -ne 0 ]]; then
  echo "Unattended install did not complete cleanly (QEMU status $QEMU_STATUS)" >&2
  tail -n 100 "$SERIAL_LOG" >&2 || true
  exit 1
fi

# Convert only after the guest's reboot request. A failed or interrupted build
# therefore never receives a release artifact name.
qemu-img check -q "$BUILD_DISK"
qemu-img convert -p -O qcow2 \
  -o compat=1.1,cluster_size=65536,lazy_refcounts=on \
  "$BUILD_DISK" "$COMPACT_DISK"
WIO_REQUIRE_GUESTFISH=${WIO_REQUIRE_GUESTFISH:-0} "$IMAGE_DIR/audit.sh" "$COMPACT_DISK"

ARTIFACT_NAME="windows-into-omarchy-omarchy-${SOURCE_VERSION}-x86_64.qcow2.zst"
COMPRESSED="$BUILD_DIR/$ARTIFACT_NAME"
zstd --threads=0 "-$ZSTD_LEVEL" --long=27 --no-progress "$COMPACT_DISK" -o "$COMPRESSED"
COMPRESSED_SHA256=$(sha256sum "$COMPRESSED" | cut -d' ' -f1)
COMPRESSED_BYTES=$(stat -c '%s' "$COMPRESSED")

shopt -s nullglob
existing=("$OUTPUT_DIR/$ARTIFACT_NAME.part-"*)
if (( ${#existing[@]} > 0 )) || [[ -e $OUTPUT_DIR/build-manifest.json || -e $OUTPUT_DIR/SHA256SUMS ]]; then
  echo "Output destination already contains image artifacts; refusing to overwrite: $OUTPUT_DIR" >&2
  exit 1
fi

split --bytes "${CHUNK_MIB}MiB" --numeric-suffixes=0 --suffix-length=3 \
  "$COMPRESSED" "$OUTPUT_DIR/$ARTIFACT_NAME.part-"
python3 "$IMAGE_DIR/build_manifest.py" \
  --lock "$LOCK" \
  --output-dir "$OUTPUT_DIR" \
  --artifact-name "$ARTIFACT_NAME" \
  --compressed-sha256 "$COMPRESSED_SHA256" \
  --compressed-bytes "$COMPRESSED_BYTES" \
  --ovmf-code "$OVMF_CODE"
(
  cd "$OUTPUT_DIR"
  sha256sum build-manifest.json "$ARTIFACT_NAME".part-* > SHA256SUMS
  sha256sum --check SHA256SUMS
)

echo "Prepared image completed: $OUTPUT_DIR"
