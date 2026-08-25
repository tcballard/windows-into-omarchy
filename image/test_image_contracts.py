#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import struct
import unittest
from pathlib import Path


IMAGE_DIR = Path(__file__).resolve().parent
ROOT = IMAGE_DIR.parent
LOCK = json.loads((IMAGE_DIR / "image.lock.json").read_text(encoding="utf-8"))
CONFIG = json.loads(
    (IMAGE_DIR / "cidata/user_configuration.json").read_text(encoding="utf-8")
)


def load_builder():
    spec = importlib.util.spec_from_file_location(
        "make_cidata", IMAGE_DIR / "make_cidata.py"
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def fat_long_names(image: bytes) -> set[str]:
    root_offset = 19 * 512
    names: set[str] = set()
    fragments: dict[int, str] = {}
    for offset in range(root_offset, root_offset + 224 * 32, 32):
        entry = image[offset : offset + 32]
        if entry[0] == 0:
            break
        if entry[0] == 0xE5:
            fragments.clear()
            continue
        if entry[11] == 0x0F:
            sequence = entry[0] & 0x1F
            encoded = entry[1:11] + entry[14:26] + entry[28:32]
            units = struct.unpack("<13H", encoded)
            fragments[sequence] = "".join(
                chr(unit) for unit in units if unit not in (0x0000, 0xFFFF)
            )
            continue
        if fragments:
            names.add("".join(fragments[index] for index in sorted(fragments)))
            fragments.clear()
    return names


class CidataTests(unittest.TestCase):
    def test_cidata_is_reproducible_and_pinned(self) -> None:
        generated = load_builder().build_image()
        committed = (IMAGE_DIR / "cidata/cidata.img").read_bytes()
        self.assertEqual(generated, committed)
        self.assertEqual(len(committed), LOCK["cidata"]["bytes"])
        self.assertEqual(hashlib.sha256(committed).hexdigest(), LOCK["cidata"]["sha256"])
        self.assertEqual(
            fat_long_names(committed), {"user_configuration.json", "defer-provisioning"}
        )

    def test_cidata_has_no_identity_or_access_material(self) -> None:
        self.assertEqual(
            {path.name for path in (IMAGE_DIR / "cidata").iterdir() if path.is_file()},
            {"cidata.img", "user_configuration.json", "defer-provisioning"},
        )
        self.assertEqual((IMAGE_DIR / "cidata/defer-provisioning").stat().st_size, 0)
        serialized = json.dumps(CONFIG).lower()
        for forbidden in (
            "user_credentials",
            "enc_password",
            "encryption_password",
            "disk_encryption",
            "authorized_keys",
            "tailscale_authkey",
            "private_key",
        ):
            self.assertNotIn(forbidden, serialized)

    def test_config_is_fixed_to_private_64_gib_virtio_disk(self) -> None:
        modification = CONFIG["disk_config"]["device_modifications"][0]
        self.assertEqual(modification["device"], "/dev/vda")
        self.assertTrue(modification["wipe"])
        self.assertTrue(CONFIG["omarchy_install"]["defer_provisioning"])
        self.assertEqual(CONFIG["omarchy_install"]["mode"], "full_disk")
        partitions = modification["partitions"]
        self.assertEqual(partitions[0]["start"]["value"], 1024**2)
        self.assertEqual(partitions[0]["size"]["value"], 2 * 1024**3)
        self.assertEqual(
            partitions[1]["start"]["value"]
            + partitions[1]["size"]["value"]
            + 1024**2,
            LOCK["guest"]["virtualDiskGiB"] * 1024**3,
        )


class PinningTests(unittest.TestCase):
    def test_image_and_runtime_use_the_same_immutable_iso(self) -> None:
        runtime = json.loads((ROOT / "config/runtime.lock.json").read_text(encoding="utf-8"))
        source = LOCK["source"]
        self.assertEqual(source["version"], runtime["omarchy"]["version"])
        self.assertEqual(source["url"], runtime["omarchy"]["downloadUrl"])
        self.assertEqual(source["sha256"], runtime["omarchy"]["sha256"])
        self.assertRegex(source["sha256"], r"^[0-9a-f]{64}$")
        self.assertRegex(source["unattendedSpecification"], r"/blob/[0-9a-f]{40}/")
        self.assertRegex(source["installerSourceCommit"], r"^[0-9a-f]{40}$")
        self.assertEqual(LOCK["guest"]["virtualDiskGiB"], runtime["machine"]["diskSizeGiB"])
        self.assertEqual(
            LOCK["cidata"]["sha256"], runtime["machine"]["unattended"]["sha256"]
        )
        self.assertEqual(
            runtime["machine"]["unattended"]["imageRelativePath"],
            LOCK["cidata"]["path"],
        )

    def test_release_chunk_is_below_github_asset_limit(self) -> None:
        self.assertGreater(LOCK["artifact"]["chunkMiB"], 0)
        self.assertLess(LOCK["artifact"]["chunkMiB"], 2048)


class PipelineTests(unittest.TestCase):
    def test_build_is_offline_and_promotes_only_after_audit(self) -> None:
        script = (IMAGE_DIR / "build.sh").read_text(encoding="utf-8")
        self.assertIn("-nic none", script)
        self.assertNotRegex(script, r"(?:virtiofs|virtfs|9p|hostfwd|PhysicalDrive)")
        self.assertIn(".qcow2.building", script)
        audit_at = script.index('"$IMAGE_DIR/audit.sh"')
        split_at = script.index("split --bytes")
        self.assertLess(audit_at, split_at)
        self.assertIn("sha256sum --check --status", script)
        self.assertIn("--proto '=https'", script)

    def test_workflow_never_executes_pull_request_code_on_image_runner(self) -> None:
        workflow = (ROOT / ".github/workflows/build-image.yml").read_text(
            encoding="utf-8"
        )
        trigger = workflow.split("jobs:", 1)[0]
        self.assertIn("workflow_dispatch:", trigger)
        self.assertNotIn("pull_request:", trigger)
        self.assertIn("omarchy-image-builder", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("github.ref == 'refs/heads/main'", workflow)
        self.assertIn("draft", workflow)
        self.assertRegex(workflow, r"actions/checkout@[0-9a-f]{40}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
