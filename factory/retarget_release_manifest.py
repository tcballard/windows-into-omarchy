#!/usr/bin/env python3
"""Bind a verified factory manifest to a permanent public release tag.

Promotion deliberately does not rebuild or decompress the multi-gigabyte guest.
It verifies every transport part against the assembly manifest, verifies each
concatenated archive, and changes only the release tag and exact asset URLs.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from pathlib import Path

from build_release_manifest import (
    ASSET_NAME_RE,
    REPOSITORY_PATH,
    ROLES,
    SHA256_RE,
    require_immutable_url,
    require_release_tag,
    sha256_file,
)


TOP_LEVEL_KEYS = {
    "schemaVersion",
    "product",
    "productVersion",
    "releaseTag",
    "buildId",
    "architecture",
    "assets",
    "upstream",
}
ASSET_KEYS = {
    "role",
    "archive",
    "outputRelativePath",
    "assembledSizeBytes",
    "assembledSha256",
    "payload",
    "parts",
}
PAYLOAD_KEYS = {"kind", "relativePath", "sizeBytes", "sha256"}
PART_KEYS = {"index", "fileName", "url", "sizeBytes", "sha256"}
EXPECTED_LAYOUT = {
    "runtime": ("zip", "runtime/qemu", "tree-manifest", "runtime/qemu/_compliance/payload-manifest.json"),
    "guest": ("zstd", "guest/omarchy-factory.qcow2", "file", "guest/omarchy-factory.qcow2"),
}


def strict_object(pairs: list[tuple[str, object]]) -> dict:
    result: dict = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read_manifest(path: Path) -> dict:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"manifest is missing or not a plain file: {path}")
    value = json.loads(path.read_text(encoding="utf-8-sig"), object_pairs_hook=strict_object)
    if not isinstance(value, dict):
        raise ValueError("manifest must be a JSON object")
    return value


def require_exact_keys(value: dict, expected: set[str], label: str) -> None:
    if set(value) != expected:
        raise ValueError(
            f"{label} keys differ (missing={sorted(expected - set(value))}, "
            f"unexpected={sorted(set(value) - expected)})"
        )


def require_positive_integer(value: object, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def hash_parts(paths: list[Path]) -> tuple[int, str]:
    digest = hashlib.sha256()
    size = 0
    for path in paths:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                size += len(block)
                digest.update(block)
    return size, digest.hexdigest()


def retarget_manifest(source: dict, assets_dir: Path, target_tag: str) -> dict:
    require_exact_keys(source, TOP_LEVEL_KEYS, "manifest")
    if source["schemaVersion"] != 1 or source["product"] != "Windows Into Omarchy":
        raise ValueError("unsupported source manifest product or schema")
    if source["architecture"] != "x86_64":
        raise ValueError("unsupported source manifest architecture")
    product_version = str(source["productVersion"])
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", product_version):
        raise ValueError("invalid productVersion")
    source_tag = require_release_tag(str(source["releaseTag"]), product_version)
    target_tag = require_release_tag(target_tag, product_version)
    if not target_tag.startswith(f"v{product_version}"):
        raise ValueError("promotion target must be a public version tag")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{7,127}", str(source["buildId"])):
        raise ValueError("invalid buildId")

    assets = source["assets"]
    if not isinstance(assets, list) or len(assets) != 2:
        raise ValueError("manifest must contain exactly two assets")
    seen_roles: set[str] = set()
    seen_part_names: set[str] = set()
    result = copy.deepcopy(source)
    result["releaseTag"] = target_tag

    for source_asset, target_asset in zip(assets, result["assets"], strict=True):
        if not isinstance(source_asset, dict):
            raise ValueError("asset must be an object")
        require_exact_keys(source_asset, ASSET_KEYS, "asset")
        role = str(source_asset["role"])
        if role not in ROLES or role in seen_roles:
            raise ValueError(f"invalid or repeated asset role: {role}")
        seen_roles.add(role)
        payload = source_asset["payload"]
        if not isinstance(payload, dict):
            raise ValueError(f"{role} payload must be an object")
        require_exact_keys(payload, PAYLOAD_KEYS, f"{role} payload")
        layout = (
            source_asset["archive"],
            source_asset["outputRelativePath"],
            payload["kind"],
            payload["relativePath"],
        )
        if layout != EXPECTED_LAYOUT[role]:
            raise ValueError(f"{role} asset does not match its fixed factory layout")
        require_positive_integer(payload["sizeBytes"], f"{role} payload size")
        if not SHA256_RE.fullmatch(str(payload["sha256"])):
            raise ValueError(f"{role} payload digest is invalid")

        source_parts = source_asset["parts"]
        if not isinstance(source_parts, list) or not source_parts:
            raise ValueError(f"{role} asset has no parts")
        local_parts: list[Path] = []
        for index, (part, target_part) in enumerate(
            zip(source_parts, target_asset["parts"], strict=True)
        ):
            if not isinstance(part, dict):
                raise ValueError(f"{role} part must be an object")
            require_exact_keys(part, PART_KEYS, f"{role} part")
            file_name = str(part["fileName"])
            if part["index"] != index or not ASSET_NAME_RE.fullmatch(file_name):
                raise ValueError(f"invalid {role} part identity at index {index}")
            if file_name in seen_part_names:
                raise ValueError(f"release part filename is repeated: {file_name}")
            seen_part_names.add(file_name)
            require_immutable_url(str(part["url"]), source_tag, file_name)
            part_size = require_positive_integer(part["sizeBytes"], f"{role} part size")
            part_digest = str(part["sha256"])
            if not SHA256_RE.fullmatch(part_digest):
                raise ValueError(f"invalid {role} part digest at index {index}")
            local = assets_dir / file_name
            if (
                not local.is_file()
                or local.is_symlink()
                or local.parent.resolve() != assets_dir.resolve()
                or local.stat().st_size != part_size
            ):
                raise ValueError(f"release part is missing or has the wrong size: {file_name}")
            actual = sha256_file(local)
            if actual != part_digest:
                raise ValueError(f"release part digest mismatch: {file_name}")
            local_parts.append(local)
            target_part["url"] = (
                f"https://github.com{REPOSITORY_PATH}/releases/download/{target_tag}/{file_name}"
            )

        assembled_size, assembled_digest = hash_parts(local_parts)
        if assembled_size != require_positive_integer(
            source_asset["assembledSizeBytes"], f"{role} assembled size"
        ) or assembled_digest != str(source_asset["assembledSha256"]):
            raise ValueError(f"{role} parts do not reconstruct the declared archive")

    if seen_roles != ROLES:
        raise ValueError(f"manifest requires roles: {sorted(ROLES)}")
    upstream = source["upstream"]
    if not isinstance(upstream, dict) or set(upstream) != {"omarchyCommit", "qemuSourceSha256"}:
        raise ValueError("invalid upstream evidence")
    if not re.fullmatch(r"[0-9a-f]{40}", str(upstream["omarchyCommit"])):
        raise ValueError("invalid upstream Omarchy commit")
    if not SHA256_RE.fullmatch(str(upstream["qemuSourceSha256"])):
        raise ValueError("invalid upstream QEMU digest")
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--assets-dir", required=True, type=Path)
    parser.add_argument("--release-tag", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    assets_dir = args.assets_dir.resolve()
    if not assets_dir.is_dir() or assets_dir.is_symlink():
        raise ValueError("assets directory is missing or unsafe")
    output = args.output.resolve()
    if output.exists():
        raise ValueError(f"refusing to overwrite manifest output: {output}")
    manifest = retarget_manifest(read_manifest(args.input.resolve()), assets_dir, args.release_tag)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(hashlib.sha256(output.read_bytes()).hexdigest(), output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"factory manifest retarget failed: {error}", file=sys.stderr)
        raise SystemExit(1)
