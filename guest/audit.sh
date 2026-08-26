#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: guest/audit.sh IMAGE.qcow2 SPEC.json" >&2; exit 2; }
IMAGE=$1
SPEC=$2
[[ -f $IMAGE && ! -L $IMAGE ]] || { echo "factory image is missing or a symlink: $IMAGE" >&2; exit 1; }

for command in guestfish qemu-img python3; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done

INFO=$(qemu-img info --output=json "$IMAGE")
python3 - "$INFO" "$SPEC" <<'PY'
import json, sys
info = json.loads(sys.argv[1])
spec = json.load(open(sys.argv[2], encoding="utf-8"))
if info.get("format") != "qcow2":
    raise SystemExit(f"expected qcow2, got {info.get('format')!r}")
expected = spec["image"]["virtualSizeGiB"] * 1024**3
if info.get("virtual-size") != expected:
    raise SystemExit(f"expected {expected} virtual bytes, got {info.get('virtual-size')!r}")
if info.get("backing-filename"):
    raise SystemExit("factory image must not depend on a backing file")
PY
qemu-img check -q "$IMAGE"

mapfile -t RESULTS < <(guestfish --quiet --ro -a "$IMAGE" <<'EOF'
run
mount-options ro,subvol=@ /dev/sda2 /
mount-ro /dev/sda1 /boot
is-file /etc/os-release
is-file /boot/EFI/limine/limine_x64.efi
is-file /var/lib/omarchy/provisioning/pending
is-file /usr/bin/omarchy-provision-owner
exists /etc/systemd/system/multi-user.target.wants/omarchy-provision-owner.service
exists /root/user_credentials.json
exists /root/authorized_keys
exists /root/tailscale_authkey
exists /root/.ssh/authorized_keys
exists /etc/tailscale/authkey
exists /var/lib/tailscale/tailscaled.state
exists /etc/ssh/ssh_host_ed25519_key
exists /etc/ssh/ssh_host_ecdsa_key
exists /etc/ssh/ssh_host_rsa_key
is-file /etc/machine-id
filesize /etc/machine-id
EOF
)

[[ ${#RESULTS[@]} -eq 16 ]] || {
  printf 'Unexpected guestfish audit response:\n%s\n' "${RESULTS[*]}" >&2
  exit 1
}
for index in 0 1 2 3 4; do
  [[ ${RESULTS[$index]} == true ]] || { echo "factory readiness audit $index failed" >&2; exit 1; }
done
for index in 5 6 7 8 9 10 11 12 13; do
  [[ ${RESULTS[$index]} == false ]] || { echo "factory retains forbidden identity material (audit $index)" >&2; exit 1; }
done
[[ ${RESULTS[14]} == true && ${RESULTS[15]} == 0 ]] || {
  echo "factory /etc/machine-id must exist and be empty" >&2
  exit 1
}

PASSWD=$(guestfish --quiet --ro -a "$IMAGE" <<'EOF'
run
mount-options ro,subvol=@ /dev/sda2 /
cat /etc/passwd
EOF
)
python3 - "$PASSWD" <<'PY'
import sys
for line in sys.argv[1].splitlines():
    fields = line.split(":")
    if len(fields) != 7:
        raise SystemExit("malformed /etc/passwd entry")
    name, uid = fields[0], int(fields[2])
    if uid >= 1000 and uid != 65534:
        raise SystemExit(f"factory image unexpectedly contains owner account {name!r} (uid {uid})")
PY

echo "Factory disk is bootable, deferred, unowned, and free of known access material."
