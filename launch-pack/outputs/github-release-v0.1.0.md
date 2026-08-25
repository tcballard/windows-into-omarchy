# Windows Into Omarchy v0.1.0

An early Windows build for trying the official Omarchy 4 installer without repartitioning, dual boot, or attaching Windows drives to the guest.

This release provides a native WPF readiness launcher around a contained QEMU/WHPX virtual machine. It verifies pinned Omarchy 4.0.1 and QEMU 11.1.0 downloads, creates one private 64 GB virtual disk, and supports persistent sessions, disposable overlays, diagnostics, and recoverable resets.

## Try it

1. Download and extract `Windows-Into-Omarchy-v0.1.0.zip` on Windows 11 x64.
2. Double-click `Start-WindowsIntoOmarchy.cmd`.
3. Follow the four readiness checks to enable WHPX, install the verified QEMU runtime, and download the verified Omarchy ISO.
4. Launch the persistent machine and complete Omarchy's installer onto its single virtual disk.

## Current boundary

This is an early alpha. The source, launcher markup, download contracts, isolation guards, lifecycle behavior, and release archive pass their static test suite, but the first complete physical-Windows installation and desktop acceptance run is still pending. Graphics use QEMU VirtIO 2D/software rendering; this release does not claim Windows-host GPU acceleration.

The QEMU Windows distribution describes its builds as experimental and uses an expired signing certificate. Windows Into Omarchy therefore identifies the locked installer by the publisher's SHA-512 before opening it.

## Integrity

`Windows-Into-Omarchy-v0.1.0.zip`

```text
1f3a6ccaa7c4a830dfebec532be0eca717d7b0c3bfd4fcff53d87a34917edcc4
```

Windows Into Omarchy is independent and is not affiliated with or endorsed by Omarchy, Basecamp, Omacom, Microsoft, QEMU, or the original Try Omarchy project.
