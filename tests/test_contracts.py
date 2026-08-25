#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "config/runtime.lock.json").read_text(encoding="utf-8"))


class RuntimeLockTests(unittest.TestCase):
    def test_lock_has_exact_top_level_schema(self) -> None:
        self.assertEqual(
            set(LOCK), {"schemaVersion", "product", "host", "omarchy", "qemu", "machine"}
        )
        self.assertEqual(LOCK["schemaVersion"], 1)
        self.assertEqual(LOCK["product"]["name"], "Windows Into Omarchy")
        self.assertEqual(LOCK["product"]["dataDirectoryName"], "Windows Into Omarchy")
        self.assertEqual(LOCK["host"]["operatingSystem"], "Windows 11")
        self.assertEqual(LOCK["host"]["architecture"], "x86_64")
        self.assertGreaterEqual(LOCK["host"]["minimumHostMemoryMiB"], 8192)

    def test_all_downloads_are_immutable_https_inputs(self) -> None:
        omarchy = LOCK["omarchy"]
        qemu = LOCK["qemu"]
        self.assertTrue(omarchy["downloadUrl"].startswith("https://"))
        self.assertIn(omarchy["version"], omarchy["downloadUrl"])
        self.assertEqual(omarchy["fileName"], Path(omarchy["downloadUrl"]).name)
        self.assertRegex(omarchy["sha256"], r"^[0-9a-f]{64}$")
        self.assertTrue(qemu["installerUrl"].startswith("https://"))
        self.assertIn(qemu["build"], qemu["installerUrl"])
        self.assertEqual(qemu["installerFileName"], Path(qemu["installerUrl"]).name)
        self.assertRegex(qemu["sha512"], r"^[0-9a-f]{128}$")

    def test_machine_limits_are_bounded(self) -> None:
        machine = LOCK["machine"]
        self.assertGreaterEqual(machine["diskSizeGiB"], 40)
        self.assertGreaterEqual(machine["minimumMemoryMiB"], 4096)
        self.assertGreaterEqual(machine["recommendedMemoryMiB"], machine["minimumMemoryMiB"])
        self.assertEqual(machine["minimumCpuCount"], 4)
        self.assertLessEqual(machine["maximumCpuCount"], 8)
        self.assertTrue(machine["firmwareCodeCandidates"])


class PowerShellContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.scripts = {
            path.relative_to(ROOT).as_posix(): path.read_text(encoding="utf-8-sig")
            for path in sorted(ROOT.rglob("*.ps1"))
        }

    def test_scripts_use_strict_failure_semantics(self) -> None:
        exemptions = {"tests/Test-Static.ps1"}
        for name, content in self.scripts.items():
            if name in exemptions:
                continue
            with self.subTest(name=name):
                self.assertIn("Set-StrictMode -Version Latest", content)
                self.assertIn("$ErrorActionPreference = 'Stop'", content)

    def test_runtime_has_no_physical_disk_or_host_share_passthrough(self) -> None:
        runtime = self.scripts["scripts/Run-VM.ps1"]
        forbidden = [
            r"PhysicalDrive",
            r"\\\.\\",
            r"virtio-9p",
            r"virtiofs",
            r"-virtfs",
            r"usb-host",
            r"file=\\\\",
        ]
        for pattern in forbidden:
            self.assertNotRegex(runtime, pattern)
        for required in (
            "'whpx'",
            "'virtio-blk-pci,drive=drive0,bootindex=1'",
            "'user,id=net0'",
            "'virtio-vga'",
            "'dsound,id=audio0'",
            "'Local\\WindowsIntoOmarchy-VM-v1'",
        ):
            self.assertIn(required, runtime)
        self.assertNotIn("'-cpu', 'max'", runtime)
        self.assertIn("leave Windows less than 2048 MiB", runtime)

    def test_disposable_cleanup_is_guarded(self) -> None:
        runtime = self.scripts["scripts/Run-VM.ps1"]
        cleanup = runtime[runtime.index("finally {") :]
        self.assertIn("Assert-WindowsIntoOmarchyChildPath -Path $ephemeralDisk", cleanup)
        self.assertIn("Remove-Item -LiteralPath $ephemeralDisk -Force", cleanup)
        self.assertNotIn("-Recurse", cleanup)
        self.assertNotIn("'-no-shutdown'", runtime)

    def test_reset_archives_instead_of_deleting(self) -> None:
        reset = self.scripts["scripts/Reset.ps1"]
        self.assertIn("Move-Item -LiteralPath $disk", reset)
        self.assertIn("Backups", reset)
        self.assertIn("Local\\WindowsIntoOmarchy-VM-v1", reset)
        self.assertNotIn("Remove-Item", reset)

    def test_download_code_enforces_hash_before_final_name(self) -> None:
        prepare = self.scripts["scripts/Prepare.ps1"]
        verify_at = prepare.index("Test-PinnedFile -Path $partial")
        publish_at = prepare.index("Move-Item -LiteralPath $partial -Destination $Destination")
        self.assertLess(verify_at, publish_at)
        self.assertIn("Quarantine", prepare)

    def test_network_inputs_are_only_read_from_lock(self) -> None:
        for name, content in self.scripts.items():
            with self.subTest(name=name):
                runtime_text = "\n".join(
                    line for line in content.splitlines() if "xmlns" not in line
                )
                self.assertNotRegex(runtime_text, r"https?://")


class InterfaceContractTests(unittest.TestCase):
    def test_embedded_launcher_xaml_is_well_formed(self) -> None:
        launcher = (ROOT / "launcher/WindowsIntoOmarchy.ps1").read_text(encoding="utf-8")
        match = re.search(r"\[xml\]\$xaml = @'\n(.*?)\n'@", launcher, re.DOTALL)
        self.assertIsNotNone(match, "embedded XAML block not found")
        ET.fromstring(match.group(1))

    def test_launcher_exposes_complete_states_and_recovery(self) -> None:
        launcher = (ROOT / "launcher/WindowsIntoOmarchy.ps1").read_text(encoding="utf-8")
        self.assertIn('Title="Windows Into Omarchy"', launcher)
        for control in (
            "HostDot",
            "HypervisorDot",
            "RuntimeDot",
            "MediaDot",
            "PrepareButton",
            "EnableButton",
            "LaunchButton",
            "DisposableButton",
            "DoctorButton",
            "ResetButton",
        ):
            self.assertIn(f'x:Name="{control}"', launcher)
        self.assertIn("IsKeyboardFocused", launcher)
        self.assertIn("Windows drives, folders, and physical devices are never attached", launcher)
        self.assertIn("downloads only pinned, verified files", launcher)


class DocumentationTests(unittest.TestCase):
    def test_required_documents_exist(self) -> None:
        for relative in (
            "README.md",
            "LICENSE",
            "SECURITY.md",
            "THIRD_PARTY_NOTICES.md",
            "docs/architecture.md",
            "docs/windows-smoke-test.md",
            "docs/releasing.md",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)

    def test_readme_is_honest_about_graphics_and_validation(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("WHPX accelerates the guest CPU", readme)
        self.assertRegex(readme, r"rather than claiming unverified Windows-host\s+VirGL")
        self.assertIn("physical-hardware acceptance", readme)


class PackagingTests(unittest.TestCase):
    def test_packager_filters_generated_python_cache(self) -> None:
        packager = (ROOT / "scripts/package.py").read_text(encoding="utf-8")
        self.assertIn('"__pycache__" not in path.parts', packager)
        self.assertIn('path.suffix != ".pyc"', packager)

    def test_package_uses_canonical_product_name(self) -> None:
        packager = (ROOT / "scripts/package.py").read_text(encoding="utf-8")
        self.assertIn('NAME = f"Windows-Into-Omarchy-v{VERSION}"', packager)
        self.assertTrue((ROOT / "Start-WindowsIntoOmarchy.cmd").is_file())


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
