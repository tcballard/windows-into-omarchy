#!/usr/bin/env python3
"""Emit measured SLSA-shaped provenance for the factory guest build."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def version(command: list[str]) -> str:
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout.splitlines()[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", type=Path, required=True)
    parser.add_argument("--iso", type=Path, required=True)
    parser.add_argument("--cidata", type=Path, required=True)
    parser.add_argument("--ovmf-code", type=Path, required=True)
    parser.add_argument("--ovmf-vars", type=Path, required=True)
    parser.add_argument("--factory-image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    spec = json.loads(args.spec.read_text(encoding="utf-8"))
    epoch = int(spec["builder"]["sourceDateEpoch"])

    payload = {
        "_type": "https://in-toto.io/Statement/v1",
        "subject": [
            {
                "name": spec["image"]["factoryFilename"],
                "digest": {"sha256": sha256(args.factory_image)},
            }
        ],
        "predicateType": "https://slsa.dev/provenance/v1",
        "predicate": {
            "buildDefinition": {
                "buildType": "https://windows-into-onarchy.invalid/build-types/omarchy-offline-iso/v1",
                "externalParameters": {
                    "releaseId": spec["releaseId"],
                    "source": spec["source"],
                    "cidata": spec["cidata"],
                    "image": spec["image"],
                    "runtime": spec["runtime"],
                },
                "internalParameters": {
                    "networkAttachedToGuest": False,
                    "hostFilesystemSharedWithGuest": False,
                    "credentialsInjected": False,
                },
                "resolvedDependencies": [
                    {"uri": spec["source"]["isoUrl"], "digest": {"sha256": sha256(args.iso)}},
                    {"uri": spec["cidata"]["path"], "digest": {"sha256": sha256(args.cidata)}},
                    {"uri": f"file:{args.ovmf_code.name}", "digest": {"sha256": sha256(args.ovmf_code)}},
                    {"uri": f"file:{args.ovmf_vars.name}", "digest": {"sha256": sha256(args.ovmf_vars)}},
                ],
            },
            "runDetails": {
                "builder": {"id": "https://github.com/tcballard/windows-into-omarchy/guest"},
                "metadata": {
                    "invocationId": os.environ.get("GITHUB_RUN_ID", "local"),
                    "startedOn": datetime.fromtimestamp(epoch, timezone.utc).isoformat().replace("+00:00", "Z"),
                    "finishedOn": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                },
                "byproducts": [
                    {"name": "qemu", "content": version(["qemu-system-x86_64", "--version"])},
                    {"name": "qemu-img", "content": version(["qemu-img", "--version"])},
                    {"name": "guestfish", "content": version(["guestfish", "--version"])},
                    {"name": "host", "content": f"{platform.system()} {platform.machine()} {platform.release()}"},
                    {"name": "sourceRevision", "content": os.environ.get("GITHUB_SHA", "local")},
                ],
            },
        },
    }
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
