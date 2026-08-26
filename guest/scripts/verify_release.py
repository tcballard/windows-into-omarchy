#!/usr/bin/env python3
"""Verify a complete split factory release without materializing another copy."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import threading
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--verify-expanded", action="store_true")
    args = parser.parse_args()
    manifest = json.loads((args.directory / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1 or manifest.get("kind") != "windows-into-omarchy.factory-guest":
        raise SystemExit("unsupported factory manifest")
    if not manifest.get("buildId") or manifest["buildId"] != manifest.get("releaseId"):
        raise SystemExit("factory buildId/releaseId mismatch")
    if manifest["lifecycle"] != {
        **manifest["lifecycle"],
        "immutableFactory": True,
        "userDiskMode": "qcow2-overlay",
        "backingFileRequired": True,
        "firstBoot": "omarchy-deferred-owner",
    }:
        raise SystemExit("unsafe lifecycle contract")

    combined = hashlib.sha256()
    combined_bytes = 0
    parts = manifest["transport"]["parts"]
    if [part["index"] for part in parts] != list(range(len(parts))):
        raise SystemExit("factory parts are not consecutively indexed")
    for part in parts:
        if not re.fullmatch(r"omarchy-factory-x86_64\.qcow2\.zst\.part[0-9]{3}", part["name"]):
            raise SystemExit(f"unsafe part name: {part['name']!r}")
        path = args.directory / part["name"]
        if path.stat().st_size != part["bytes"] or sha256(path) != part["sha256"]:
            raise SystemExit(f"factory part failed verification: {part['name']}")
        combined_bytes += path.stat().st_size
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                combined.update(chunk)
    if combined_bytes != manifest["transport"]["bytes"]:
        raise SystemExit("assembled factory byte count does not match")
    if combined.hexdigest() != manifest["transport"]["sha256"]:
        raise SystemExit("assembled factory digest does not match")
    if args.verify_expanded:
        process = subprocess.Popen(
            ["zstd", "-q", "-d", "-c"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
        )
        assert process.stdin is not None and process.stdout is not None
        writer_error: list[BaseException] = []

        def write_parts() -> None:
            try:
                for part in parts:
                    with (args.directory / part["name"]).open("rb") as stream:
                        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                            process.stdin.write(chunk)
                process.stdin.close()
            except BaseException as error:
                writer_error.append(error)
                process.kill()

        writer = threading.Thread(target=write_parts, daemon=True)
        writer.start()
        factory_digest = hashlib.sha256()
        factory_bytes = 0
        for chunk in iter(lambda: process.stdout.read(1024 * 1024), b""):
            factory_digest.update(chunk)
            factory_bytes += len(chunk)
        writer.join()
        status = process.wait()
        if writer_error:
            raise SystemExit(f"failed to stream factory parts: {writer_error[0]}")
        if status != 0:
            raise SystemExit(f"zstd verification failed with status {status}")
        if factory_bytes != manifest["factory"]["bytes"]:
            raise SystemExit("expanded factory byte count does not match")
        if factory_digest.hexdigest() != manifest["factory"]["sha256"]:
            raise SystemExit("expanded factory digest does not match")
    for metadata in manifest["metadata"]:
        path = args.directory / metadata["name"]
        if path.stat().st_size != metadata["bytes"] or sha256(path) != metadata["sha256"]:
            raise SystemExit(f"metadata failed verification: {metadata['name']}")
    suffix = " including expanded QCOW2" if args.verify_expanded else ""
    print(f"Verified factory guest {manifest['releaseId']} ({len(parts)} parts){suffix}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
