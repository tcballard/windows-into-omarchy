#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


GUEST = Path(__file__).resolve().parents[1]
ROOT = GUEST.parent
SPEC = json.loads((GUEST / "spec.json").read_text(encoding="utf-8"))


def load_script(name: str):
    path = GUEST / "scripts" / name
    spec = importlib.util.spec_from_file_location(name.replace(".", "_"), path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SourceContractTests(unittest.TestCase):
    def test_factory_source_matches_existing_immutable_locks(self) -> None:
        image = json.loads((ROOT / "image/image.lock.json").read_text(encoding="utf-8"))
        runtime = json.loads((ROOT / "config/runtime.lock.json").read_text(encoding="utf-8"))
        source = SPEC["source"]
        self.assertEqual(source["version"], image["source"]["version"])
        self.assertEqual(source["version"], runtime["omarchy"]["version"])
        self.assertEqual(source["isoUrl"], image["source"]["url"])
        self.assertEqual(source["isoUrl"], runtime["omarchy"]["downloadUrl"])
        self.assertEqual(source["isoSha256"], image["source"]["sha256"])
        self.assertEqual(source["isoSha256"], runtime["omarchy"]["sha256"])
        self.assertEqual(source["installerSourceCommit"], image["source"]["installerSourceCommit"])
        self.assertRegex(source["sourceCommit"], r"^[0-9a-f]{40}$")
        self.assertRegex(source["sourceTree"], r"^[0-9a-f]{40}$")
        self.assertRegex(source["unattendedSpecification"], r"/blob/[0-9a-f]{40}/")

    def test_factory_cidata_is_exact_deferred_owner_input(self) -> None:
        image = json.loads((ROOT / "image/image.lock.json").read_text(encoding="utf-8"))
        self.assertEqual(SPEC["cidata"]["sha256"], image["cidata"]["sha256"])
        self.assertEqual(SPEC["cidata"]["bytes"], image["cidata"]["bytes"])
        self.assertEqual(SPEC["cidata"]["mode"], "deferred-first-owner")
        config = json.loads((ROOT / "image/cidata/user_configuration.json").read_text(encoding="utf-8"))
        self.assertTrue(config["omarchy_install"]["defer_provisioning"])
        self.assertEqual(config["disk_config"]["device_modifications"][0]["device"], "/dev/vda")
        self.assertEqual((ROOT / "image/cidata/defer-provisioning").stat().st_size, 0)


class BuildBoundaryTests(unittest.TestCase):
    def test_guest_install_is_offline_and_private(self) -> None:
        build = (GUEST / "build.sh").read_text(encoding="utf-8")
        self.assertIn("-nic none", build)
        self.assertNotRegex(build, r"(?:virtiofs|virtfs|9p|hostfwd|PhysicalDrive)")
        self.assertIn("readonly=on,id=cidata", build)
        self.assertIn("readonly=on,id=installer", build)
        self.assertIn("--proto '=https'", build)
        self.assertIn("sha256sum --check --status", build)
        self.assertLess(build.index('"$GUEST_DIR/audit.sh"'), build.index("split --bytes"))

    def test_release_requires_real_kvm_but_tcg_is_explicit_smoke_mode(self) -> None:
        build = (GUEST / "build.sh").read_text(encoding="utf-8")
        self.assertIn("WIO_FACTORY_REQUIRE_KVM", build)
        self.assertIn("WIO_FACTORY_EPHEMERAL_CACHE", build)
        self.assertIn("--accel kvm|tcg", build)
        workflow = (ROOT / ".github/workflows/build-factory-guest.yml").read_text(encoding="utf-8")
        self.assertIn("onarchy-factory-builder", workflow)
        self.assertIn("WIO_FACTORY_REQUIRE_KVM: '1'", workflow)
        self.assertIn("github.ref_protected", workflow)
        self.assertNotIn("pull_request:", workflow.split("jobs:", 1)[0])
        self.assertIn("persist-credentials: false", workflow)

        release_workflow = (ROOT / ".github/workflows/factory-release-v0.3.0.yml").read_text(encoding="utf-8")
        self.assertIn("runs-on: ubuntu-24.04", release_workflow)
        self.assertIn("github.actor == github.repository_owner", release_workflow)
        self.assertIn("test -c /dev/kvm", release_workflow)
        self.assertIn("libguestfs-tools", release_workflow)
        self.assertIn("WIO_FACTORY_EPHEMERAL_CACHE: '1'", release_workflow)
        self.assertNotIn("pull_request:", release_workflow.split("jobs:", 1)[0])

    def test_lifecycle_and_transport_are_launcher_safe(self) -> None:
        lifecycle = SPEC["lifecycle"]
        self.assertTrue(lifecycle["immutableFactory"])
        self.assertEqual(lifecycle["userDiskMode"], "qcow2-overlay")
        self.assertTrue(lifecycle["backingFileRequired"])
        self.assertEqual(lifecycle["firstBoot"], "omarchy-deferred-owner")
        image = SPEC["image"]
        self.assertEqual(image["factoryFilename"], "omarchy-factory.qcow2")
        self.assertEqual(image["compressedFilename"], "omarchy-factory-x86_64.qcow2.zst")
        self.assertGreater(image["partSizeMiB"], 0)
        self.assertLess(image["partSizeMiB"], 2048)

    def test_audit_requires_pending_owner_and_absent_identity(self) -> None:
        audit = (GUEST / "audit.sh").read_text(encoding="utf-8")
        for required in (
            "/var/lib/omarchy/provisioning/pending",
            "/usr/bin/omarchy-provision-owner",
            "/root/user_credentials.json",
            "/root/.ssh/authorized_keys",
            "/var/lib/tailscale/tailscaled.state",
            "/etc/ssh/ssh_host_ed25519_key",
            "/etc/machine-id",
        ):
            self.assertIn(required, audit)
        self.assertIn("uid >= 1000", audit)


class MetadataTests(unittest.TestCase):
    def test_pacman_fixture_generates_deterministic_sbom_and_license_inventory(self) -> None:
        script = GUEST / "scripts/package_metadata.py"
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            base_command = [
                "python3", str(script),
                "--pacman-db", str(GUEST / "fixtures/pacman-local"),
                "--license-tree", str(GUEST / "fixtures/licenses"),
                "--release-id", SPEC["releaseId"],
                "--source-epoch", str(SPEC["builder"]["sourceDateEpoch"]),
            ]
            subprocess.run(base_command + ["--output-dir", first], check=True)
            subprocess.run(base_command + ["--output-dir", second], check=True)
            for name in ("packages.lock.tsv", "sbom.cdx.json", "licenses.json"):
                self.assertEqual((Path(first) / name).read_bytes(), (Path(second) / name).read_bytes())
            sbom = json.loads((Path(first) / "sbom.cdx.json").read_text())
            self.assertEqual(sbom["bomFormat"], "CycloneDX")
            self.assertEqual(sbom["specVersion"], "1.6")
            self.assertEqual(sbom["components"][0]["name"], "example")
            self.assertEqual(sbom["components"][0]["licenses"][0]["license"]["id"], "MIT")
            self.assertEqual(sbom["components"][0]["licenses"][1]["license"]["name"], "custom:fixture")

    def test_manifest_and_streaming_verifier_agree(self) -> None:
        writer = GUEST / "scripts/write_manifest.py"
        verifier = GUEST / "scripts/verify_release.py"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            factory = output / "factory.tmp"
            compressed = output / SPEC["image"]["compressedFilename"]
            factory.write_bytes(b"qcow2-fixture")
            compressed.write_bytes(b"zstd-fixture-split")
            (output / f"{compressed.name}.part000").write_bytes(b"zstd-fixture-")
            (output / f"{compressed.name}.part001").write_bytes(b"split")
            for name in load_script("write_manifest.py").METADATA:
                (output / name).write_text(f"fixture {name}\n", encoding="utf-8")
            subprocess.run(
                ["python3", str(writer), "--spec", str(GUEST / "spec.json"),
                 "--output-dir", str(output), "--factory-image", str(factory),
                 "--compressed-image", str(compressed)],
                check=True,
            )
            subprocess.run(["python3", str(verifier), str(output)], check=True)
            manifest = json.loads((output / "manifest.json").read_text())
            self.assertEqual(manifest["buildId"], SPEC["releaseId"])
            self.assertEqual(manifest["factory"]["sha256"], hashlib.sha256(factory.read_bytes()).hexdigest())
            self.assertEqual(manifest["transport"]["sha256"], hashlib.sha256(compressed.read_bytes()).hexdigest())

    @unittest.skipUnless(shutil.which("zstd"), "zstd is unavailable")
    def test_release_verifier_streams_parts_into_expanded_factory_digest(self) -> None:
        writer = GUEST / "scripts/write_manifest.py"
        verifier = GUEST / "scripts/verify_release.py"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            factory = output / "factory.tmp"
            compressed = output / SPEC["image"]["compressedFilename"]
            factory.write_bytes((b"qcow2-expanded-fixture\0" * 10000) + b"end")
            subprocess.run(["zstd", "-q", "-3", str(factory), "-o", str(compressed)], check=True)
            compressed_bytes = compressed.read_bytes()
            midpoint = len(compressed_bytes) // 2
            (output / f"{compressed.name}.part000").write_bytes(compressed_bytes[:midpoint])
            (output / f"{compressed.name}.part001").write_bytes(compressed_bytes[midpoint:])
            for name in load_script("write_manifest.py").METADATA:
                (output / name).write_text(f"fixture {name}\n", encoding="utf-8")
            subprocess.run(
                ["python3", str(writer), "--spec", str(GUEST / "spec.json"),
                 "--output-dir", str(output), "--factory-image", str(factory),
                 "--compressed-image", str(compressed)],
                check=True,
            )
            subprocess.run(["python3", str(verifier), "--verify-expanded", str(output)], check=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
