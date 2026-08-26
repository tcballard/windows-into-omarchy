#!/usr/bin/env python3
"""Build the immutable release manifest consumed by the Windows experience.

The input is release-workflow metadata. File sizes and digests are always
calculated here; callers cannot assert them. Split parts are hashed separately
and again as one concatenated archive so interrupted downloads can resume
without weakening the final integrity check.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import urlparse


ROLES = {"runtime", "guest"}
ARCHIVES = {"zip", "zstd"}
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
ASSET_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$")
REPOSITORY_PATH = "/tcballard/windows-into-omarchy"


def require_release_tag(value: str, product_version: str) -> str:
    allowed = value in {f"factory-v{product_version}", f"v{product_version}"}
    allowed = allowed or re.fullmatch(
        rf"v{re.escape(product_version)}-rc\.[1-9][0-9]*", value
    ) is not None
    if not allowed:
        raise ValueError(
            "releaseTag must be factory-v<productVersion>, v<productVersion>, "
            "or v<productVersion>-rc.<positive integer>"
        )
    return value


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_concatenated(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
    return digest.hexdigest()


def require_relative_output(value: str) -> str:
    candidate = Path(value)
    if candidate.is_absolute() or ".." in candidate.parts or not candidate.parts:
        raise ValueError(f"unsafe outputRelativePath: {value}")
    return candidate.as_posix()


def require_immutable_url(url: str, release_tag: str, file_name: str) -> str:
    if not ASSET_NAME_RE.fullmatch(file_name):
        raise ValueError(f"unsafe release asset name: {file_name}")
    parsed = urlparse(url)
    expected_path = f"{REPOSITORY_PATH}/releases/download/{release_tag}/{file_name}"
    if (
        parsed.scheme != "https"
        or parsed.hostname != "github.com"
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or parsed.path != expected_path
    ):
        raise ValueError(f"asset URL is not pinned to {release_tag}/{file_name}: {url}")
    return url


def build_manifest(spec: dict, base: Path) -> dict:
    if spec.get("schemaVersion") != 1:
        raise ValueError("release input schemaVersion must be 1")
    if spec.get("product") != "Windows Into Omarchy":
        raise ValueError("unexpected product identity")
    if spec.get("architecture") != "x86_64":
        raise ValueError("only x86_64 factory releases are supported")

    release_tag = str(spec.get("releaseTag", ""))
    product_version = str(spec.get("productVersion", ""))
    build_id = str(spec.get("buildId", ""))
    require_release_tag(release_tag, product_version)
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{7,127}", build_id):
        raise ValueError("buildId must be a stable lowercase release identity")

    assets = []
    seen_roles: set[str] = set()
    seen_part_names: set[str] = set()
    for asset in spec.get("assets", []):
        role = str(asset.get("role", ""))
        archive = str(asset.get("archive", ""))
        if role not in ROLES or role in seen_roles:
            raise ValueError(f"invalid or repeated asset role: {role}")
        if archive not in ARCHIVES:
            raise ValueError(f"unsupported archive type: {archive}")
        seen_roles.add(role)

        output = require_relative_output(str(asset.get("outputRelativePath", "")))
        payload_input = asset.get("payload", {})
        payload_source = (base / str(payload_input.get("path", ""))).resolve()
        if not payload_source.is_file():
            raise ValueError(f"asset payload evidence is missing: {payload_source}")
        payload_kind = str(payload_input.get("kind", ""))
        if payload_kind not in {"file", "tree-manifest"}:
            raise ValueError(f"unsupported payload evidence kind: {payload_kind}")
        payload_relative = require_relative_output(str(payload_input.get("relativePath", "")))
        expected_layout = {
            "runtime": {
                "archive": "zip",
                "output": "runtime/qemu",
                "kind": "tree-manifest",
                "payload": "runtime/qemu/_compliance/payload-manifest.json",
            },
            "guest": {
                "archive": "zstd",
                "output": "guest/omarchy-factory.qcow2",
                "kind": "file",
                "payload": "guest/omarchy-factory.qcow2",
            },
        }[role]
        if {
            "archive": archive,
            "output": output,
            "kind": payload_kind,
            "payload": payload_relative,
        } != expected_layout:
            raise ValueError(f"asset {role} does not match its fixed factory layout")
        output_path = Path(output)
        payload_path = Path(payload_relative)
        if payload_kind == "file" and payload_path != output_path:
            raise ValueError("file payload evidence must identify outputRelativePath exactly")
        if payload_kind == "tree-manifest" and output_path not in payload_path.parents:
            raise ValueError("tree manifest must be below outputRelativePath")
        source_parts: list[Path] = []
        parts = []
        for index, part in enumerate(asset.get("parts", [])):
            source = (base / str(part.get("path", ""))).resolve()
            if not source.is_file():
                raise ValueError(f"asset part is missing: {source}")
            file_name = source.name
            if file_name in seen_part_names:
                raise ValueError(f"release part filename is repeated: {file_name}")
            seen_part_names.add(file_name)
            url = require_immutable_url(str(part.get("url", "")), release_tag, file_name)
            source_parts.append(source)
            parts.append(
                {
                    "index": index,
                    "fileName": file_name,
                    "url": url,
                    "sizeBytes": source.stat().st_size,
                    "sha256": sha256_file(source),
                }
            )
        if not parts:
            raise ValueError(f"asset {role} has no parts")

        assets.append(
            {
                "role": role,
                "archive": archive,
                "outputRelativePath": output,
                "assembledSizeBytes": sum(part["sizeBytes"] for part in parts),
                "assembledSha256": sha256_concatenated(source_parts),
                "payload": {
                    "kind": payload_kind,
                    "relativePath": payload_relative,
                    "sizeBytes": payload_source.stat().st_size,
                    "sha256": sha256_file(payload_source),
                },
                "parts": parts,
            }
        )

    if seen_roles != ROLES:
        raise ValueError(f"factory release requires roles: {sorted(ROLES)}")

    upstream = spec.get("upstream", {})
    omarchy_commit = str(upstream.get("omarchyCommit", ""))
    qemu_source_sha256 = str(upstream.get("qemuSourceSha256", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", omarchy_commit):
        raise ValueError("upstream.omarchyCommit must be a full commit SHA")
    if not SHA256_RE.fullmatch(qemu_source_sha256):
        raise ValueError("upstream.qemuSourceSha256 must be a SHA-256 digest")

    manifest = {
        "schemaVersion": 1,
        "product": "Windows Into Omarchy",
        "productVersion": product_version,
        "releaseTag": release_tag,
        "buildId": build_id,
        "architecture": "x86_64",
        "assets": sorted(assets, key=lambda item: item["role"]),
        "upstream": {
            "omarchyCommit": omarchy_commit,
            "qemuSourceSha256": qemu_source_sha256,
        },
    }
    for asset in manifest["assets"]:
        assert SHA256_RE.fullmatch(asset["assembledSha256"])
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    spec_path = args.input.resolve()
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    manifest = build_manifest(spec, spec_path.parent)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(hashlib.sha256(args.output.read_bytes()).hexdigest(), args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
