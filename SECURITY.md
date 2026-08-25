# Security

## Product boundaries

The launcher never attaches a physical Windows disk, volume, home directory,
or arbitrary host folder to the guest. Omarchy sees only its private QCOW2
disk, the read-only official installer ISO, virtual devices, and user-mode
networking.

Downloads are written to a temporary `.partial` file, cryptographically
verified against `config/runtime.lock.json`, and only then moved into place.
Existing files with the wrong digest are quarantined rather than executed.

Reset is recoverable: the persistent disk is moved into the app's `Backups`
directory. The product does not recursively delete user-selected paths.

## Reporting

Do not include passwords, private keys, tokens, disk images, or personal data
in a public report. Until a private disclosure address is established, keep
security findings private and do not publish exploit details.
