#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 IMAGE.qcow2" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
IMAGE=$1
[[ -f $IMAGE && ! -L $IMAGE ]] || { echo "Image is missing or is a symlink: $IMAGE" >&2; exit 1; }

command -v qemu-img >/dev/null || { echo "qemu-img is required" >&2; exit 1; }
qemu-img check -q "$IMAGE"

INFO=$(qemu-img info --output=json "$IMAGE")
python3 - "$INFO" <<'PY'
import json
import sys

info = json.loads(sys.argv[1])
if info.get("format") != "qcow2":
    raise SystemExit(f"expected qcow2, got {info.get('format')!r}")
if info.get("virtual-size") != 64 * 1024**3:
    raise SystemExit(f"expected a 64 GiB virtual disk, got {info.get('virtual-size')!r}")
if info.get("backing-filename"):
    raise SystemExit("release image must not depend on a backing file")
PY

if ! command -v guestfish >/dev/null; then
  if [[ ${WIO_REQUIRE_GUESTFISH:-0} == 1 ]]; then
    echo "guestfish is required for the release identity audit" >&2
    exit 1
  fi
  echo "warning: guestfish unavailable; skipped offline guest identity audit" >&2
  exit 0
fi

# Omarchy's supported defer-provisioning mode is intended for imaging rigs.
# Verify that its resulting disk has boot media but no copied credentials,
# remote-access keys, or clone-unsafe machine identity.
mapfile -t RESULTS < <(guestfish --quiet --ro -a "$IMAGE" <<'EOF'
run
mount-options ro,subvol=@ /dev/sda2 /
mount-ro /dev/sda1 /boot
is-file /etc/os-release
is-file /boot/EFI/limine/limine_x64.efi
exists /root/user_credentials.json
exists /root/authorized_keys
exists /root/tailscale_authkey
exists /etc/tailscale/authkey
exists /etc/ssh/ssh_host_ed25519_key
exists /etc/ssh/ssh_host_rsa_key
is-file /etc/machine-id
filesize /etc/machine-id
EOF
)

[[ ${#RESULTS[@]} -eq 10 ]] || {
  printf 'Unexpected guestfish audit response:\n%s\n' "${RESULTS[*]}" >&2
  exit 1
}
[[ ${RESULTS[0]} == true ]] || { echo "installed image lacks /etc/os-release" >&2; exit 1; }
[[ ${RESULTS[1]} == true ]] || { echo "installed image lacks the Limine UEFI loader" >&2; exit 1; }
for index in 2 3 4 5 6 7; do
  [[ ${RESULTS[$index]} == false ]] || { echo "installed image retains forbidden identity material (audit $index)" >&2; exit 1; }
done
[[ ${RESULTS[8]} == true ]] || { echo "installed image lacks /etc/machine-id" >&2; exit 1; }
[[ ${RESULTS[9]} == 0 ]] || { echo "installed image has a clone-unsafe machine-id" >&2; exit 1; }

echo "Image structure and deferred-owner identity audit passed."

