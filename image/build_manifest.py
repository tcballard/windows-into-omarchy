#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--artifact-name", required=True)
    parser.add_argument("--compressed-sha256", required=True)
    parser.add_argument("--compressed-bytes", type=int, required=True)
    parser.add_argument("--ovmf-code", type=Path, required=True)
    args = parser.parse_args()

    lock = json.loads(args.lock.read_text(encoding="utf-8"))
    parts = sorted(args.output_dir.glob(f"{args.artifact_name}.part-*"))
    if not parts:
        raise SystemExit("no split artifact parts found")

    source_date_epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if source_date_epoch:
        built_at = datetime.fromtimestamp(int(source_date_epoch), timezone.utc)
    else:
        built_at = datetime.now(timezone.utc)

    qemu_version = subprocess.run(
        ["qemu-system-x86_64", "--version"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.splitlines()[0]

    manifest = {
        "schemaVersion": 1,
        "product": "Windows Into Omarchy prepared image",
        "builtAtUtc": built_at.isoformat().replace("+00:00", "Z"),
        "sourceRevision": os.environ.get("GITHUB_SHA", "local"),
        "source": lock["source"],
        "guest": lock["guest"],
        "cidata": {
            "sha256": lock["cidata"]["sha256"],
            "containsCredentials": False,
            "containsAuthorizedKeys": False,
            "containsTailscaleKey": False,
        },
        "builder": {
            "qemu": qemu_version,
            "ovmfCodeSha256": sha256(args.ovmf_code),
            "networkAttachedDuringInstall": False,
        },
        "artifact": {
            "name": args.artifact_name,
            "format": "qcow2.zst.split",
            "compressedBytes": args.compressed_bytes,
            "compressedSha256": args.compressed_sha256,
            "parts": [
                {"name": part.name, "bytes": part.stat().st_size, "sha256": sha256(part)}
                for part in parts
            ],
        },
    }
    destination = args.output_dir / "build-manifest.json"
    destination.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

