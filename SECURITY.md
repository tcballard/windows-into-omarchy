# Security

## Product boundaries

The factory-default VM receives a version-bound private QCOW2 overlay, virtual
devices and QEMU user-mode networking. It receives no physical Windows disk,
volume, home directory, arbitrary host folder, clipboard, SSH agent, credential
store or physical USB passthrough. The immutable factory backing disk is marked
read-only and is never attached writable.

The developer/recovery fallback additionally attaches the read-only official
installer ISO and credential-free `cidata` drive. Those devices are absent from
a factory launch.

Release downloads are selected only by the embedded immutable factory manifest.
Parts are written below product app data, verified at part/archive/payload
boundaries, and activated only after runtime, capability, guest and factory
receipts agree. Invalid or conflicting data is quarantined rather than executed
or booted.

Machine overlays are checked for reparse points, integrity and exact backing
chain before launch. Reset is recoverable: it archives the recognised writable
overlay and receipt beneath `Backups`; it does not recursively delete a
user-selected path.

These boundaries reduce host exposure. They are not a guarantee that QEMU, its
dependencies or an arbitrary guest contain no vulnerabilities. Keep Windows
and release assets updated through reviewed, pinned rebuilds.

## Reporting

Do not include passwords, private keys, tokens, personal data, factory/VM disk
images or unredacted local paths in a public report. Until a private disclosure
address is established, keep exploit details private and contact the repository
owner through a non-public channel.
