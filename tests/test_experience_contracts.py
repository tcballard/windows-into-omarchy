from __future__ import annotations

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NATIVE = ROOT / "windows/WindowsIntoOnarchy"


class NativeExperienceTests(unittest.TestCase):
    def test_native_app_is_a_non_console_net8_wpf_executable(self) -> None:
        project = (NATIVE / "WindowsIntoOnarchy.csproj").read_text(encoding="utf-8")
        self.assertIn("<OutputType>WinExe</OutputType>", project)
        self.assertIn("<TargetFramework>net8.0-windows</TargetFramework>", project)
        self.assertIn("<UseWPF>true</UseWPF>", project)
        self.assertIn("<SelfContained>true</SelfContained>", project)
        self.assertIn("<PublishSingleFile>true</PublishSingleFile>", project)
        self.assertIn("<RuntimeIdentifier>win-x64</RuntimeIdentifier>", project)
        self.assertIn("WindowsIntoOnarchy.ico", project)
        self.assertTrue((ROOT / "assets/WindowsIntoOnarchy.ico").is_file())

    def test_native_xaml_is_well_formed_and_single_surface(self) -> None:
        xaml = (NATIVE / "MainWindow.xaml").read_text(encoding="utf-8")
        ET.fromstring(xaml)
        self.assertIn('Title="Windows Into Onarchy"', xaml)
        self.assertIn('x:Name="Progress"', xaml)
        self.assertIn('x:Name="Primary"', xaml)
        self.assertIn("Recovery and advanced options", xaml)
        self.assertNotIn("ComboBox", xaml)
        self.assertNotIn("install QEMU", xaml)

    def test_native_processes_never_open_a_console(self) -> None:
        controller = (NATIVE / "ExperienceController.cs").read_text(encoding="utf-8")
        self.assertIn("ProcessWindowStyle.Hidden", controller)
        self.assertIn("CreateNoWindow = !elevated", controller)
        self.assertIn('Verb = elevated ? "runas"', controller)
        self.assertNotIn("cmd.exe", controller.lower())
        self.assertNotIn("-LaunchAfter", controller)

    def test_native_controller_declares_windows_build_namespaces(self) -> None:
        controller = (NATIVE / "ExperienceController.cs").read_text(encoding="utf-8")
        self.assertIn("using System.IO;", controller)
        self.assertIn("using System.Collections.Generic;", controller)

    def test_resume_is_bounded_to_one_run(self) -> None:
        common = (ROOT / "scripts/experience/Experience.Common.ps1").read_text(encoding="utf-8")
        app = (NATIVE / "App.xaml.cs").read_text(encoding="utf-8")
        self.assertIn("WindowsIntoOnarchyResume", common)
        self.assertIn("CurrentVersion\\RunOnce", common)
        self.assertNotIn("CurrentVersion\\Run'", common)
        self.assertIn('"--resume"', app)
        self.assertIn("Clear-OnarchyPostRestartResume", (ROOT / "scripts/experience/Experience.ps1").read_text(encoding="utf-8"))
        native = (NATIVE / "MainWindow.xaml.cs").read_text(encoding="utf-8")
        self.assertIn('next.Action == "Continue"', native)
        self.assertIn("controller.PrepareAndLaunch()", native)
        controller = (NATIVE / "ExperienceController.cs").read_text(encoding="utf-8")
        register_at = controller.index('"-Mode", "Register"')
        elevation_at = controller.index('elevated: true', register_at)
        self.assertLess(register_at, elevation_at)
        self.assertIn("controller.ClearResume()", native)

    def test_factory_machine_is_an_atomic_private_overlay(self) -> None:
        experience = (ROOT / "scripts/experience/Experience.ps1").read_text(encoding="utf-8")
        self.assertIn("-f qcow2 -F qcow2 -b $Factory.Guest $partial", experience)
        self.assertIn("qemuImg check $partial", experience)
        self.assertIn("Assert-WindowsIntoOmarchyChildPath -Path ($machineDisk + '.partial')", experience)
        self.assertLess(experience.index("qemuImg check $partial"), experience.index("Move-Item -LiteralPath $partial -Destination $machineDisk"))
        for forbidden in ("PhysicalDrive", r"\\.\\", "virtiofs", "usb-host"):
            self.assertNotIn(forbidden, experience)

    def test_recovery_archives_only_the_active_private_overlay(self) -> None:
        recovery = (ROOT / "scripts/experience/Archive-ActiveMachine.ps1").read_text(encoding="utf-8")
        self.assertIn("Assert-WindowsIntoOmarchyChildPath", recovery)
        self.assertIn("Move-Item -LiteralPath $disk", recovery)
        self.assertIn("Backups", recovery)
        self.assertIn("ReparsePoint", recovery)
        self.assertNotIn("Remove-Item", recovery)

    def test_launcher_prefers_native_executable(self) -> None:
        launcher = (ROOT / "launcher/WindowsIntoOmarchy.ps1").read_text(encoding="utf-8")
        native = launcher.index("Test-Path -LiteralPath $native")
        compatibility = launcher.index("[xml]$xaml")
        self.assertLess(native, compatibility)


class ExperienceStateTests(unittest.TestCase):
    def test_progress_journal_is_atomic_and_closed(self) -> None:
        common = (ROOT / "scripts/experience/Experience.Common.ps1").read_text(encoding="utf-8")
        self.assertIn("progress.json", common)
        self.assertIn("[IO.File]::Replace($temporary, $paths.State, $null, $true)", common)
        self.assertIn("[IO.File]::Move($temporary, $paths.State)", common)
        phase_set = re.search(r"ValidateSet\((.*?)\)\]\[string\]\$Phase", common, re.DOTALL)
        self.assertIsNotNone(phase_set)
        for phase in ("AwaitingRestart", "Preparing", "CreatingMachine", "Running", "Failed"):
            self.assertIn(f"'{phase}'", phase_set.group(1))

    def test_factory_contract_has_no_floating_network_discovery(self) -> None:
        scripts = "\n".join(
            path.read_text(encoding="utf-8-sig")
            for path in sorted((ROOT / "scripts/experience").glob("*.ps1"))
        )
        self.assertIn("factory\\factory-release.json", scripts)
        self.assertNotRegex(scripts, r"https?://")
        self.assertNotIn("/latest", scripts)
        self.assertIn("factoryManifestSha256", scripts)
        self.assertIn("receiptRecord.complete", scripts)
        self.assertIn("host-capabilities.json", scripts)
        self.assertIn("tools\\zstd.exe", scripts)
        self.assertIn(".IsReadOnly", scripts)


if __name__ == "__main__":
    unittest.main()
