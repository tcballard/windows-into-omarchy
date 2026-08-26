from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_assembler():
    path = ROOT / "factory/assemble_release.py"
    spec = importlib.util.spec_from_file_location("factory_assembly", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_sums(directory: Path) -> None:
    lines = [
        f"{sha256(path)}  {path.name}"
        for path in sorted(directory.iterdir())
        if path.is_file() and path.name != "SHA256SUMS"
    ]
    (directory / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="ascii")


class FactoryReleaseAssemblyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.assembly = load_assembler()

    def test_checksum_verification_is_exhaustive_and_detects_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "one.bin").write_bytes(b"one")
            write_sums(root)
            self.assertEqual(set(self.assembly.verify_checksum_set(root)), {"one.bin"})
            (root / "unlisted.bin").write_bytes(b"unexpected")
            with self.assertRaisesRegex(ValueError, "not exhaustive"):
                self.assembly.verify_checksum_set(root)
            (root / "unlisted.bin").unlink()
            (root / "one.bin").write_bytes(b"changed")
            with self.assertRaisesRegex(ValueError, "checksum mismatch"):
                self.assembly.verify_checksum_set(root)

    def test_runtime_zip_is_verified_against_lock_provenance_and_every_payload_file(self) -> None:
        lock = json.loads((ROOT / "runtime/portable-runtime.lock.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            runtime = base / "runtime"
            work = base / "work"
            runtime.mkdir()
            work.mkdir()
            files = {
                "runtime/qemu/qemu-system-x86_64.exe": b"qemu",
                "runtime/qemu/qemu-img.exe": b"qemu-img",
                "tools/zstd.exe": b"zstd",
                "licenses/qemu/COPYING": b"license",
                "capability-receipt.json": b"{}\n",
            }
            records = [
                {"path": name, "size": len(content), "sha256": hashlib.sha256(content).hexdigest()}
                for name, content in sorted(files.items())
            ]
            payload = {
                "schemaVersion": 1,
                "target": "windows-x86_64",
                "qemuVersion": lock["qemu"]["version"],
                "qemuBuild": lock["qemu"]["build"],
                "zstdVersion": lock["zstd"]["version"],
                "fileCount": len(records),
                "files": records,
            }
            payload_bytes = (json.dumps(payload) + "\n").encode()
            (runtime / "payload-manifest.json").write_bytes(payload_bytes)
            provenance_inputs = [
                {"uri": lock["qemu"]["installer"]["url"], "digest": {"sha512": lock["qemu"]["installer"]["sha512"]}},
                {"uri": lock["qemu"]["source"]["url"], "digest": {"sha256": lock["qemu"]["source"]["sha256"]}},
                {"uri": lock["zstd"]["binary"]["url"], "digest": {"sha256": lock["zstd"]["binary"]["sha256"]}},
                {"uri": lock["zstd"]["source"]["url"], "digest": {"sha256": lock["zstd"]["source"]["sha256"]}},
            ]
            (runtime / "provenance.json").write_text(json.dumps({"inputs": provenance_inputs}))
            for name in (
                lock["payload"]["sourceArchiveName"], "runtime.spdx.json",
                "corresponding-source-manifest.json", "license-manifest.json",
                "SOURCE-OFFER.txt", "capability-receipt.json",
            ):
                (runtime / name).write_bytes((name + "\n").encode())
            archive = runtime / lock["payload"]["archiveName"]
            with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_STORED) as bundle:
                # Match the explicit directory records emitted by 7-Zip on the
                # Windows runtime builder. They are metadata, not payload files.
                for name in (
                    "runtime/", "runtime/qemu/", "runtime/qemu/_compliance/",
                    "tools/", "licenses/", "licenses/qemu/",
                ):
                    bundle.writestr(name, b"")
                for name, content in files.items():
                    bundle.writestr(name, content)
                bundle.writestr("runtime/qemu/_compliance/payload-manifest.json", payload_bytes)
            archive_bytes = archive.read_bytes()
            midpoint = len(archive_bytes) // 2
            (runtime / f"{archive.name}.part001").write_bytes(archive_bytes[:midpoint])
            (runtime / f"{archive.name}.part002").write_bytes(archive_bytes[midpoint:])
            write_sums(runtime)
            parts, zstd, result = self.assembly.verify_runtime(runtime, lock, work)
            self.assertEqual([path.name for path in parts], [f"{archive.name}.part001", f"{archive.name}.part002"])
            self.assertEqual(zstd.read_bytes(), b"zstd")
            self.assertEqual(result["fileCount"], len(files))
            with zipfile.ZipFile(archive, "a") as bundle:
                bundle.writestr("unexpected.exe", b"bad")
            archive_bytes = archive.read_bytes()
            midpoint = len(archive_bytes) // 2
            (runtime / f"{archive.name}.part001").write_bytes(archive_bytes[:midpoint])
            (runtime / f"{archive.name}.part002").write_bytes(archive_bytes[midpoint:])
            write_sums(runtime)
            with self.assertRaisesRegex(ValueError, "contents differ"):
                self.assembly.verify_runtime(runtime, lock, base / "second-work")

    @unittest.skipUnless(shutil.which("zstd"), "zstd is unavailable")
    def test_guest_parts_expand_to_independently_verified_factory_payload(self) -> None:
        spec = json.loads((ROOT / "guest/spec.json").read_text())
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            guest = base / "guest"
            work = base / "work"
            guest.mkdir()
            work.mkdir()
            factory = base / "source.qcow2"
            factory.write_bytes((b"factory-qcow2\0" * 10000) + b"end")
            compressed = base / spec["image"]["compressedFilename"]
            subprocess.run([shutil.which("zstd"), "-q", "-3", str(factory), "-o", str(compressed)], check=True)
            payload = compressed.read_bytes()
            midpoint = len(payload) // 2
            parts = [
                guest / f"{compressed.name}.part000",
                guest / f"{compressed.name}.part001",
            ]
            parts[0].write_bytes(payload[:midpoint])
            parts[1].write_bytes(payload[midpoint:])
            manifest = {
                "schemaVersion": 1,
                "kind": "windows-into-omarchy.factory-guest",
                "releaseId": spec["releaseId"],
                "source": spec["source"],
                "lifecycle": spec["lifecycle"],
                "factory": {"filename": spec["image"]["factoryFilename"], "bytes": factory.stat().st_size, "sha256": sha256(factory)},
                "transport": {
                    "assembledFilename": compressed.name,
                    "bytes": compressed.stat().st_size,
                    "sha256": sha256(compressed),
                    "parts": [
                        {"name": path.name, "index": index, "bytes": path.stat().st_size, "sha256": sha256(path)}
                        for index, path in enumerate(parts)
                    ],
                },
            }
            (guest / "manifest.json").write_text(json.dumps(manifest))
            for name in (
                "provenance.json", "sbom.cdx.json", "packages.lock.tsv", "licenses.json",
                "license-texts.tar.zst", "THIRD_PARTY_NOTICES.md",
            ):
                (guest / name).write_bytes((name + "\n").encode())
            write_sums(guest)
            verified_parts, expanded, _ = self.assembly.verify_guest(
                guest, spec, Path(shutil.which("zstd")), work
            )
            self.assertEqual(verified_parts, parts)
            self.assertEqual(expanded.read_bytes(), factory.read_bytes())
            parts[1].write_bytes(b"tampered")
            write_sums(guest)
            with self.assertRaisesRegex(ValueError, "part record mismatch"):
                self.assembly.verify_guest(guest, spec, Path(shutil.which("zstd")), base / "second-work")

    def test_workflow_is_manual_protected_and_draft_only(self) -> None:
        workflow = (ROOT / ".github/workflows/factory-release-v0.3.0.yml").read_text()
        trigger = workflow.split("jobs:", 1)[0]
        self.assertIn("workflow_dispatch:", trigger)
        self.assertNotIn("pull_request:", trigger)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn("github.ref_protected", workflow)
        self.assertIn("environment: factory-v0.3.0-draft", workflow)
        self.assertIn(".protection_rules | length", workflow)
        self.assertIn("--draft", workflow)
        self.assertIn("factory-v0.3.0", workflow)
        self.assertIn("innosetup --version=6.7.1", workflow)
        self.assertIn("7zip --version=26.2.0", workflow)
        self.assertNotIn("/latest", workflow)
        self.assertRegex(workflow, r"actions/checkout@[0-9a-f]{40}")
        self.assertRegex(workflow, r"actions/upload-artifact@[0-9a-f]{40}")
        self.assertRegex(workflow, r"actions/download-artifact@[0-9a-f]{40}")

    def test_reassembly_reuses_one_immutable_verified_source_run(self) -> None:
        workflow = (ROOT / ".github/workflows/reassemble-factory-v0.3.0.yml").read_text()
        self.assertIn("SOURCE_RUN_ID: '32958526312'", workflow)
        self.assertIn("SOURCE_SHA: 3e7e9506df0f7ce6cec9a125e9b596269c9ca755", workflow)
        self.assertIn("factory-v0.3.0-runtime-32958526312", workflow)
        self.assertIn("factory-v0.3.0-guest-32958526312", workflow)
        self.assertIn("github.actor == github.repository_owner", workflow)
        self.assertIn("actions: read", workflow)
        self.assertIn("run-id: ${{ env.SOURCE_RUN_ID }}", workflow)
        self.assertIn("if ($run.head_sha -ne $env:SOURCE_SHA)", workflow)
        self.assertNotIn("/latest", workflow)
        self.assertRegex(workflow, r"actions/checkout@[0-9a-f]{40}")
        self.assertRegex(workflow, r"actions/upload-artifact@[0-9a-f]{40}")
        self.assertRegex(workflow, r"actions/download-artifact@[0-9a-f]{40}")

    def test_wrapper_embeds_manifest_before_native_installer_and_checksums_every_asset(self) -> None:
        wrapper = (ROOT / "scripts/Assemble-FactoryRelease.ps1").read_text(encoding="utf-8")
        verify_at = wrapper.index("factory\\assemble_release.py")
        build_at = wrapper.index("Build-Installer.ps1")
        sums_at = wrapper.index("'SHA256SUMS'")
        self.assertLess(verify_at, build_at)
        self.assertLess(build_at, sums_at)
        self.assertIn("factory\\factory-release.json", wrapper)
        self.assertIn("-RequireFactory", wrapper)
        self.assertIn("-SkipTests", wrapper)
        self.assertIn("Get-FileHash", wrapper)
        self.assertIn("Join-Path $projectRoot 'dist'", wrapper)
        self.assertIn("GetDirectoryName($work).Equals($workRoot", wrapper)
        self.assertNotIn("GetTempPath", wrapper)
        self.assertNotRegex(wrapper, r"https?://")


if __name__ == "__main__":
    unittest.main(verbosity=2)
