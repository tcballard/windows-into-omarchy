from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MATERIALIZE = (ROOT / "scripts/Materialize-Factory.ps1").read_text(encoding="utf-8-sig")
RUN = (ROOT / "scripts/Run-VM.ps1").read_text(encoding="utf-8-sig")
COMMON = (ROOT / "scripts/experience/Experience.Common.ps1").read_text(encoding="utf-8-sig")


class MaterializationContractTests(unittest.TestCase):
    def test_download_contract_is_immutable_and_verifies_every_boundary(self) -> None:
        self.assertIn("$uri.Host -ne 'github.com'", MATERIALIZE)
        self.assertIn("'/releases/download/'", MATERIALIZE)
        self.assertIn("Test-PinnedFile -Path $partial -Algorithm SHA256", MATERIALIZE)
        self.assertIn("Test-PinnedFile -Path $archive -Algorithm SHA256", MATERIALIZE)
        self.assertIn("Test-PinnedFile -Path $guestPartial -Algorithm SHA256", MATERIALIZE)
        self.assertNotIn("/latest", MATERIALIZE)

    def test_archive_extraction_rejects_traversal_links_ads_and_bombs(self) -> None:
        self.assertIn("StartsWith($root", MATERIALIZE)
        self.assertIn("$relative.Contains(':')", MATERIALIZE)
        self.assertIn("0xA000", MATERIALIZE)
        self.assertIn("0x400", MATERIALIZE)
        self.assertIn("8GB", MATERIALIZE)
        self.assertIn("FileMode]::CreateNew", MATERIALIZE)

    def test_factory_is_sparse_read_only_and_activated_last(self) -> None:
        self.assertIn("--sparse", MATERIALIZE)
        self.assertIn(".IsReadOnly = $true", MATERIALIZE)
        receipt_at = MATERIALIZE.index("$receipt = [ordered]@{")
        active_at = MATERIALIZE.index("$active = [ordered]@{")
        guest_verify_at = MATERIALIZE.index("Test-FactoryPayload -Asset $guest")
        self.assertLess(guest_verify_at, receipt_at)
        self.assertLess(receipt_at, active_at)
        self.assertIn("active.json.partial", MATERIALIZE)

    def test_materializer_uses_runtime_auditor_and_host_gpu_smoke(self) -> None:
        self.assertIn("Install-PortableRuntime.ps1", MATERIALIZE)
        self.assertIn("Test-PortableRuntimeCapabilities.ps1", MATERIALIZE)
        self.assertIn("-RunDisplaySmoke", MATERIALIZE)
        self.assertIn("-RequireRuntimeManifest", MATERIALIZE)
        self.assertIn("runtime\\qemu\\_compliance\\payload-manifest.json", MATERIALIZE)
        self.assertIn("hostCapabilities.sdl2dReady", MATERIALIZE)
        manifest_verify_at = MATERIALIZE.index("Test-PinnedFile -Path $runtimePayloadManifest")
        runtime_install_at = MATERIALIZE.index("& $runtimeInstaller")
        self.assertLess(manifest_verify_at, runtime_install_at)

    def test_factory_roles_are_bound_to_fixed_output_paths(self) -> None:
        for value in (
            "runtime/qemu",
            "runtime/qemu/_compliance/payload-manifest.json",
            "guest/omarchy-factory.qcow2",
        ):
            self.assertIn(value, MATERIALIZE)

    def test_download_failure_message_is_valid_in_windows_powershell(self) -> None:
        # A colon immediately after an unbraced variable is parsed as a scope
        # qualifier by Windows PowerShell 5.1 (for example, ``$env:Path``).
        self.assertIn("${downloadName}: $description", MATERIALIZE)
        self.assertNotIn("$downloadName: $description", MATERIALIZE)


class FactoryLaunchContractTests(unittest.TestCase):
    def test_factory_launch_is_bound_to_exact_overlay_chain(self) -> None:
        self.assertIn("Get-OnarchyActiveFactory", RUN)
        self.assertIn("VM\\' + [string]$factory.BuildId", RUN)
        self.assertIn("info --backing-chain --output=json", RUN)
        self.assertIn("$chain[1].filename", RUN)
        self.assertIn("machineReceipt.backingFile", RUN)

    def test_factory_path_does_not_attach_installer_media(self) -> None:
        factory_branch = RUN[RUN.index("if ($null -ne $factory) {") :]
        self.assertIn("menu=off,order=c", factory_branch)
        self.assertIn("if ($null -ne $factory)", RUN)
        self.assertIn("} else {", RUN)
        self.assertIn("$status.IsoPath", RUN)  # fallback remains available
        self.assertIn("$status.CidataPath", RUN)
        self.assertNotIn("file=$($factory.Guest)", RUN)

    def test_gpu_path_is_enabled_only_from_on_host_receipt(self) -> None:
        self.assertIn("gpuAccelerationReady", RUN)
        self.assertIn("factory.Capabilities.virglAdvertised", RUN)
        self.assertIn("factory.Capabilities.anglePresent", RUN)
        self.assertIn("factory.Capabilities.virglDisplaySmokeTested", RUN)
        self.assertIn("virtio-vga-gl", RUN)
        self.assertIn("sdl,gl=on", RUN)
        self.assertIn("sdl,gl=off", RUN)

    def test_active_factory_rehashes_critical_runtime_and_binds_gpu_receipt(self) -> None:
        for value in (
            "runtime/qemu/qemu-system-x86_64.exe",
            "runtime/qemu/qemu-img.exe",
            "tools/zstd.exe",
            "capabilityRecord.qemuSystemSha256",
            "capabilityRecord.runtimeManifestSha256",
            "capabilityRecord.virglDisplaySmokeTested",
            "contract.Runtime.payload.sha256",
            "contract.Guest.payload.sha256",
        ):
            self.assertIn(value, COMMON)


if __name__ == "__main__":
    unittest.main()
