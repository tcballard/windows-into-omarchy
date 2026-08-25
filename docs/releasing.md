# Release checklist

1. Run `make test` on a clean source tree.
2. Run `tests\Test-Static.ps1` with Windows PowerShell 5.1.
3. Build the archive with `make package` and verify `dist/SHA256SUMS`.
4. Complete `docs/windows-smoke-test.md` on physical Windows hardware.
5. Confirm runtime URLs, versions, hashes, and release notes agree.
6. Run `python image/make_cidata.py --check` and prove the published package
   contains no credentials, SSH keys, Tailscale keys, or disk passphrases.
7. Confirm the normal setup contains neither the Omarchy ISO nor QEMU payload;
   both must be downloaded directly from their locked upstream locations.
8. Audit QEMU's corresponding-source and notice obligations if bundle mode is
   ever requested. Bundle mode must remain closed without its approval manifest.
9. Build the Inno Setup package on Windows with `scripts\Build-Installer.ps1`.
10. Authenticode-sign the setup executable and timestamp the signature.
11. Test the exact signed artifact on a clean Windows account, including the
    unattended install, automatic reboot, first-owner setup, and second launch.
12. Publish the setup, source archive, SHA-256 values, limitations, and test
    evidence together.

An unsigned package is for local evaluation only. Do not describe it as a
production Windows release.
