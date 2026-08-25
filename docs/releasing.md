# Release checklist

1. Run `make test` on a clean source tree.
2. Run `tests\Test-Static.ps1` with Windows PowerShell 5.1.
3. Build the archive with `make package` and verify `dist/SHA256SUMS`.
4. Complete `docs/windows-smoke-test.md` on physical Windows hardware.
5. Confirm runtime URLs, versions, hashes, and release notes agree.
6. Audit the QEMU bundle's licenses and corresponding-source obligations if it
   is ever included rather than downloaded separately.
7. Build the Inno Setup package on Windows.
8. Authenticode-sign the setup executable and timestamp the signature.
9. Test the exact signed artifact on a clean Windows account.
10. Publish the archive, its SHA-256, limitations, and test evidence together.

An unsigned package is for local evaluation only. Do not describe it as a
production Windows release.
