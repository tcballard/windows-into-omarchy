from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_builder():
    path = ROOT / "factory/build_release_manifest.py"
    spec = importlib.util.spec_from_file_location("factory_manifest", path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class FactoryManifestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.builder = load_builder()
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "runtime.zip.000").write_bytes(b"runtime-a")
        (self.root / "runtime.zip.001").write_bytes(b"runtime-b")
        (self.root / "guest.zst.000").write_bytes(b"guest")
        (self.root / "runtime-payload.json").write_text('{"schemaVersion":1,"files":[]}\n')
        (self.root / "omarchy-factory.qcow2").write_bytes(b"factory-disk")
        self.spec = {
            "schemaVersion": 1,
            "product": "Windows Into Onarchy",
            "productVersion": "0.3.0",
            "releaseTag": "factory-v0.3.0",
            "buildId": "factory-0.3.0-test",
            "architecture": "x86_64",
            "assets": [
                {
                    "role": "runtime",
                    "archive": "zip",
                    "outputRelativePath": "runtime/qemu",
                    "payload": {
                        "path": "runtime-payload.json",
                        "kind": "tree-manifest",
                        "relativePath": "runtime/qemu/_compliance/payload-manifest.json",
                    },
                    "parts": [
                        {
                            "path": "runtime.zip.000",
                            "url": "https://github.com/tcballard/windows-into-omarchy/releases/download/factory-v0.3.0/runtime.zip.000",
                        },
                        {
                            "path": "runtime.zip.001",
                            "url": "https://github.com/tcballard/windows-into-omarchy/releases/download/factory-v0.3.0/runtime.zip.001",
                        },
                    ],
                },
                {
                    "role": "guest",
                    "archive": "zstd",
                    "outputRelativePath": "guest/omarchy-factory.qcow2",
                    "payload": {
                        "path": "omarchy-factory.qcow2",
                        "kind": "file",
                        "relativePath": "guest/omarchy-factory.qcow2",
                    },
                    "parts": [
                        {
                            "path": "guest.zst.000",
                            "url": "https://github.com/tcballard/windows-into-omarchy/releases/download/factory-v0.3.0/guest.zst.000",
                        }
                    ],
                },
            ],
            "upstream": {
                "omarchyCommit": "1" * 40,
                "qemuSourceSha256": "2" * 64,
            },
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_builds_exact_two_role_manifest_with_computed_digests(self) -> None:
        manifest = self.builder.build_manifest(self.spec, self.root)
        self.assertEqual([a["role"] for a in manifest["assets"]], ["guest", "runtime"])
        self.assertEqual(manifest["releaseTag"], "factory-v0.3.0")
        for asset in manifest["assets"]:
            self.assertRegex(asset["assembledSha256"], r"^[0-9a-f]{64}$")
            self.assertEqual([p["index"] for p in asset["parts"]], list(range(len(asset["parts"]))))

    def test_rejects_latest_or_query_bearing_urls(self) -> None:
        self.spec["assets"][0]["parts"][0]["url"] = (
            "https://github.com/tcballard/windows-into-omarchy/releases/latest/download/runtime.zip.000"
        )
        with self.assertRaises(ValueError):
            self.builder.build_manifest(self.spec, self.root)

        self.spec["assets"][0]["parts"][0]["url"] = (
            "https://github.com/tcballard/windows-into-omarchy/releases/download/"
            "factory-v0.3.0/runtime.zip.000?token=secret"
        )
        with self.assertRaises(ValueError):
            self.builder.build_manifest(self.spec, self.root)

    def test_rejects_output_traversal_and_missing_roles(self) -> None:
        self.spec["assets"][0]["outputRelativePath"] = "../runtime"
        with self.assertRaises(ValueError):
            self.builder.build_manifest(self.spec, self.root)

        self.spec["assets"][0]["outputRelativePath"] = "runtime/qemu"
        self.spec["assets"].pop()
        with self.assertRaises(ValueError):
            self.builder.build_manifest(self.spec, self.root)

    def test_rejects_role_layout_drift(self) -> None:
        wrong_runtime = json.loads(json.dumps(self.spec))
        wrong_runtime["assets"][0]["payload"]["relativePath"] = "payload-manifest.json"
        with self.assertRaisesRegex(ValueError, "fixed factory layout"):
            self.builder.build_manifest(wrong_runtime, self.root)

        wrong_guest = json.loads(json.dumps(self.spec))
        wrong_guest["assets"][1]["outputRelativePath"] = "guest/other.qcow2"
        with self.assertRaisesRegex(ValueError, "fixed factory layout"):
            self.builder.build_manifest(wrong_guest, self.root)

    def test_schema_is_closed_and_names_the_product(self) -> None:
        schema = json.loads((ROOT / "factory/release-manifest.schema.json").read_text())
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(schema["properties"]["product"]["const"], "Windows Into Onarchy")


if __name__ == "__main__":
    unittest.main()
