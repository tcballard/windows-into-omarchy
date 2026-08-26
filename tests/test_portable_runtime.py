from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "runtime" / "portable-runtime.lock.json"
LOCK = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
BUILD = (ROOT / "scripts" / "Build-PortableRuntime.ps1").read_text(encoding="utf-8")
INSTALL = (ROOT / "scripts" / "Install-PortableRuntime.ps1").read_text(encoding="utf-8")
CAPABILITIES = (ROOT / "scripts" / "Test-PortableRuntimeCapabilities.ps1").read_text(encoding="utf-8")


class PortableRuntimeContractTests(unittest.TestCase):
    def test_all_remote_inputs_are_immutable_and_digest_pinned(self) -> None:
        self.assertEqual(LOCK["schemaVersion"], 1)
        self.assertEqual(LOCK["target"], "windows-x86_64")
        for artifact, algorithm, length in (
            (LOCK["qemu"]["installer"], "sha512", 128),
            (LOCK["qemu"]["source"], "sha256", 64),
            (LOCK["zstd"]["binary"], "sha256", 64),
            (LOCK["zstd"]["source"], "sha256", 64),
        ):
            self.assertRegex(artifact[algorithm], rf"^[0-9a-f]{{{length}}}$")
            self.assertTrue(artifact["url"].startswith("https://"))
            self.assertNotIn("/latest/", artifact["url"])

    def test_qemu_installer_is_extracted_not_executed(self) -> None:
        self.assertIn("Invoke-SevenZip @('x', $qemuInstaller", BUILD)
        self.assertNotIn("Start-Process -FilePath $qemuInstaller", BUILD)
        self.assertIn("needs no elevation", BUILD)
        self.assertIn("qemu-system-x86_64.exe", BUILD)
        self.assertIn("qemu-img.exe", BUILD)

    def test_zstd_is_embedded_at_factory_contract_path(self) -> None:
        self.assertIn("Join-Path $toolsPayload 'zstd.exe'", BUILD)
        self.assertIn("tools\\zstd.exe", INSTALL)
        self.assertEqual(LOCK["zstd"]["version"], "1.5.7")

    def test_gpu_claim_is_fail_closed(self) -> None:
        self.assertIn("virtio-vga-gl", CAPABILITIES)
        self.assertIn("libvirglrenderer-1.dll", CAPABILITIES)
        self.assertIn("libEGL.dll", CAPABILITIES)
        self.assertIn("virglDisplaySmokeTested", CAPABILITIES)
        assignment = re.search(r"gpuAccelerationReady\s*=\s*\[bool\]\((.*?)\)", CAPABILITIES)
        self.assertIsNotNone(assignment)
        assert assignment is not None
        self.assertIn("virglAdvertised", assignment.group(1))
        self.assertIn("anglePresent", assignment.group(1))
        self.assertIn("virglDisplaySmokeTested", assignment.group(1))
        self.assertIn("sdl2dReady", CAPABILITIES)
        self.assertIn("qemuSystemSha256", CAPABILITIES)
        self.assertIn("runtimeManifestSha256", CAPABILITIES)
        self.assertIn("RequireRuntimeManifest", CAPABILITIES)
        self.assertIn("finally", CAPABILITIES)
        self.assertIn("Stop-Process", CAPABILITIES)

    def test_release_set_contains_binary_source_sbom_and_provenance(self) -> None:
        for required in (
            "payload-manifest.json",
            "runtime.spdx.json",
            "provenance.json",
            "corresponding-source-manifest.json",
            "license-manifest.json",
            "SOURCE-OFFER.txt",
            "SHA256SUMS",
            ".part{1:d3}",
        ):
            self.assertIn(required, BUILD)
        self.assertEqual(
            LOCK["payload"]["archiveName"],
            "windows-into-onarchy-qemu-x86_64.zip",
        )

    def test_materializer_rehashes_every_file_and_rejects_traversal(self) -> None:
        self.assertIn("foreach ($record in @($manifest.files))", INSTALL)
        self.assertIn("Get-FileHash -LiteralPath $path -Algorithm SHA256", INSTALL)
        self.assertIn("Unsafe payload path", INSTALL)
        self.assertIn("ReparsePoint", INSTALL)
        self.assertIn("Refusing to overwrite", INSTALL)
        self.assertIn("runtime\\qemu\\_compliance\\payload-manifest.json", INSTALL)
        self.assertIn("Embedded payload manifest does not match", INSTALL)

    def test_compliance_records_are_present_and_valid_json(self) -> None:
        for name in ("license-manifest.json", "corresponding-source-manifest.json"):
            value = json.loads((ROOT / "runtime" / "compliance" / name).read_text(encoding="utf-8"))
            self.assertEqual(value["schemaVersion"], 1)
        offer = (ROOT / "runtime" / "compliance" / "SOURCE-OFFER.txt").read_text(encoding="utf-8")
        self.assertIn("three years", offer)
        self.assertIn(LOCK["payload"]["sourceArchiveName"], offer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
