#!/usr/bin/env python3
"""Assemble the launcher-facing factory guest manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


METADATA = (
    "sbom.cdx.json",
    "packages.lock.tsv",
    "licenses.json",
    "license-texts.tar.zst",
    "provenance.json",
    "THIRD_PARTY_NOTICES.md",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--factory-image", type=Path, required=True)
    parser.add_argument("--compressed-image", type=Path, required=True)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    compressed_name = spec["image"]["compressedFilename"]
    parts = sorted(args.output_dir.glob(f"{compressed_name}.part[0-9][0-9][0-9]"))
    if not parts:
        raise SystemExit("no factory image parts found")
    metadata = []
    for name in METADATA:
        path = args.output_dir / name
        if not path.is_file():
            raise SystemExit(f"required release metadata is missing: {name}")
        metadata.append({"name": name, "bytes": path.stat().st_size, "sha256": sha256(path)})

    manifest = {
        "schemaVersion": 1,
        "kind": "windows-into-omarchy.factory-guest",
        "buildId": spec["releaseId"],
        "releaseId": spec["releaseId"],
        "source": spec["source"],
        "guest": {
            "architecture": spec["source"]["architecture"],
            "virtualSizeGiB": spec["image"]["virtualSizeGiB"],
            "machine": spec["runtime"]["machine"],
            "firmware": spec["runtime"]["firmware"],
            "secureBoot": spec["runtime"]["secureBoot"],
            "diskDevice": spec["runtime"]["diskDevice"],
            "minimumQemuMajor": spec["runtime"]["minimumQemuMajor"],
        },
        "lifecycle": spec["lifecycle"],
        "factory": {
            "filename": spec["image"]["factoryFilename"],
            "format": spec["image"]["format"],
            "virtualBytes": spec["image"]["virtualSizeGiB"] * 1024**3,
            "bytes": args.factory_image.stat().st_size,
            "sha256": sha256(args.factory_image),
        },
        "transport": {
            "assembledFilename": compressed_name,
            "compression": spec["image"]["compression"],
            "bytes": args.compressed_image.stat().st_size,
            "sha256": sha256(args.compressed_image),
            "parts": [
                {"name": part.name, "index": index, "bytes": part.stat().st_size, "sha256": sha256(part)}
                for index, part in enumerate(parts)
            ],
        },
        "metadata": metadata,
        "releasePolicy": spec["releasePolicy"],
    }
    (args.output_dir / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
