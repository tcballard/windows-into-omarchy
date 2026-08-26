#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: guest/sanitize.sh IMAGE.qcow2" >&2; exit 2; }
IMAGE=$1
[[ -f $IMAGE && ! -L $IMAGE ]] || { echo "factory image is missing or a symlink: $IMAGE" >&2; exit 1; }
command -v guestfish >/dev/null || { echo "guestfish is required" >&2; exit 1; }

# Remove only machine-specific state. Owner-account content is never rewritten:
# if an owner exists, the following read-only audit must reject the image.
guestfish -a "$IMAGE" <<'EOF'
run
mount-options rw,subvol=@ /dev/sda2 /
truncate /etc/machine-id
rm-f /var/lib/dbus/machine-id
rm-f /root/user_credentials.json
rm-f /root/authorized_keys
rm-f /root/tailscale_authkey
rm-f /root/.ssh/authorized_keys
rm-f /etc/tailscale/authkey
rm-rf /var/lib/tailscale
rm-f /etc/ssh/ssh_host_ed25519_key
rm-f /etc/ssh/ssh_host_ed25519_key.pub
rm-f /etc/ssh/ssh_host_ecdsa_key
rm-f /etc/ssh/ssh_host_ecdsa_key.pub
rm-f /etc/ssh/ssh_host_rsa_key
rm-f /etc/ssh/ssh_host_rsa_key.pub
sync
EOF

echo "Removed transient machine and access identity from the offline factory disk."
