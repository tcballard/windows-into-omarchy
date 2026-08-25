from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "config/runtime.lock.json").read_text(encoding="utf-8"))
SCRIPT = (ROOT / "scripts/Build-Runtime.ps1").read_text(encoding="utf-8")
INSTALLER = (ROOT / "installer/WindowsIntoOmarchy.iss").read_text(encoding="utf-8")


class RuntimeAcquisitionTests(unittest.TestCase):
    def test_upstream_installer_is_pinned_before_execution(self) -> None:
        self.assertRegex(LOCK["qemu"]["sha512"], r"^[0-9a-f]{128}$")
        verify_at = SCRIPT.index("Get-VerifiedQemuInstaller")
        execute_at = SCRIPT.index("Start-Process -FilePath $verifiedInstaller")
        self.assertLess(verify_at, execute_at)
        self.assertIn("Test-PinnedFile -Path $partial -Algorithm SHA512", SCRIPT)
        self.assertIn("Move-Item -LiteralPath $partial -Destination $bad", SCRIPT)

    def test_default_runtime_is_app_local_and_silent(self) -> None:
        self.assertEqual(LOCK["qemu"]["installation"]["relativeDirectory"], "Runtime\\qemu")
        self.assertIn("$defaultInstallDestination = Join-Path $dataRoot $runtimeRelativeDirectory", SCRIPT)
        self.assertIn('$argumentLine = "/S /D=$target"', SCRIPT)
        self.assertIn("-Verb RunAs -PassThru -Wait", SCRIPT)

    def test_runtime_is_capability_and_license_checked(self) -> None:
        for requirement in (
            "qemu-system-x86_64.exe",
            "qemu-img.exe",
            "COPYING",
            "COPYING.LIB",
            "whpx",
            "sdl",
            "dsound",
            "virtio-vga",
            "virtio-blk-pci",
            "hda-duplex",
        ):
            self.assertIn(requirement, SCRIPT)

    def test_redistribution_mode_is_explicitly_gated(self) -> None:
        self.assertIn("$ComplianceManifestPath", SCRIPT)
        self.assertIn("redistributionApproved", SCRIPT)
        for role in ("corresponding-source", "sbom", "license-manifest"):
            self.assertIn(role, SCRIPT)
        self.assertIn(".redistribution-reviewed.json", SCRIPT)
        wrapper = (ROOT / "installer/WindowsIntoOmarchy-BundledRuntime.iss").read_text(
            encoding="utf-8"
        )
        self.assertIn("#define BundleQemuRuntime", wrapper)
        self.assertIn("#ifdef BundleQemuRuntime", INSTALLER)

    def test_normal_installer_does_not_unconditionally_redistribute_qemu(self) -> None:
        qemu_source = 'Source: "..\\runtime\\qemu\\*"'
        qemu_at = INSTALLER.index(qemu_source)
        guard_at = INSTALLER.rfind("#ifdef BundleQemuRuntime", 0, qemu_at)
        end_at = INSTALLER.index("#endif", qemu_at)
        self.assertGreaterEqual(guard_at, 0)
        self.assertGreater(end_at, qemu_at)


if __name__ == "__main__":
    unittest.main(verbosity=2)
