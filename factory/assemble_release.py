#!/usr/bin/env python3
"""Verify runtime/guest build outputs and prepare an immutable factory release.

This script intentionally computes the root release manifest from local bytes.
Component manifests are evidence to verify, never authority for release URLs or
the final payload digest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SUM_LINE_RE = re.compile(r"^([0-9a-f]{64})  ([^/\\\r\n]+)$")
RUNTIME_PART_RE = re.compile(r"^windows-into-onarchy-qemu-x86_64\.zip\.part([0-9]{3})$")
GUEST_PART_RE = re.compile(r"^omarchy-factory-x86_64\.qcow2\.zst\.part([0-9]{3})$")
REPOSITORY = "tcballard/windows-into-omarchy"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_files(paths: list[Path]) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    for path in paths:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                total += len(block)
                digest.update(block)
    return total, digest.hexdigest()


def plain_file(path: Path, label: str) -> Path:
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"{label} is missing or not a plain file: {path}")
    return path


def load_json(path: Path, label: str) -> dict:
    plain_file(path, label)
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except (UnicodeError, json.JSONDecodeError) as error:
        raise ValueError(f"{label} is not strict JSON: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a JSON object")
    return value


def verify_checksum_set(directory: Path) -> dict[str, str]:
    sums_path = plain_file(directory / "SHA256SUMS", "SHA256SUMS")
    records: dict[str, str] = {}
    for line in sums_path.read_text(encoding="ascii").splitlines():
        match = SUM_LINE_RE.fullmatch(line)
        if not match:
            raise ValueError(f"malformed SHA256SUMS line in {directory}: {line!r}")
        digest, name = match.groups()
        if name in records:
            raise ValueError(f"duplicate SHA256SUMS entry: {name}")
        path = plain_file(directory / name, f"checksummed file {name}")
        if path.parent.resolve() != directory.resolve():
            raise ValueError(f"checksum path escapes its component directory: {name}")
        actual = sha256_file(path)
        if actual != digest:
            raise ValueError(f"checksum mismatch for {name}: expected {digest}, got {actual}")
        records[name] = digest
    actual_files = {
        path.name
        for path in directory.iterdir()
        if path.is_file() and not path.is_symlink() and path.name != "SHA256SUMS"
    }
    if set(records) != actual_files:
        missing = sorted(actual_files - set(records))
        stale = sorted(set(records) - actual_files)
        raise ValueError(f"SHA256SUMS is not exhaustive (missing={missing}, stale={stale})")
    return records


def consecutive_parts(directory: Path, pattern: re.Pattern[str], start: int) -> list[Path]:
    indexed: list[tuple[int, Path]] = []
    for path in directory.iterdir():
        match = pattern.fullmatch(path.name)
        if match:
            plain_file(path, "archive part")
            indexed.append((int(match.group(1)), path))
    indexed.sort()
    if not indexed:
        raise ValueError(f"no parts matched {pattern.pattern}")
    expected = list(range(start, start + len(indexed)))
    if [index for index, _ in indexed] != expected:
        raise ValueError(f"archive parts are not consecutive from {start:03d}")
    return [path for _, path in indexed]


def safe_zip_name(name: str) -> str:
    if "\\" in name or ":" in name or name.startswith("/"):
        raise ValueError(f"runtime ZIP contains unsafe path: {name!r}")
    path = PurePosixPath(name)
    if not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise ValueError(f"runtime ZIP contains unsafe path: {name!r}")
    return path.as_posix()


def verify_runtime(runtime: Path, portable_lock: dict, work: Path) -> tuple[list[Path], Path, dict]:
    sums = verify_checksum_set(runtime)
    archive_name = portable_lock["payload"]["archiveName"]
    required = {
        archive_name,
        portable_lock["payload"]["sourceArchiveName"],
        "payload-manifest.json",
        "runtime.spdx.json",
        "provenance.json",
        "corresponding-source-manifest.json",
        "license-manifest.json",
        "SOURCE-OFFER.txt",
        "capability-receipt.json",
    }
    if not required.issubset(sums):
        raise ValueError(f"runtime release is incomplete: {sorted(required - set(sums))}")

    archive = plain_file(runtime / archive_name, "runtime archive")
    parts = consecutive_parts(runtime, RUNTIME_PART_RE, 1)
    part_size, part_digest = sha256_files(parts)
    if part_size != archive.stat().st_size or part_digest != sha256_file(archive):
        raise ValueError("runtime parts do not reconstruct the verified runtime archive")

    payload = load_json(runtime / "payload-manifest.json", "runtime payload manifest")
    if payload.get("schemaVersion") != 1 or payload.get("target") != "windows-x86_64":
        raise ValueError("runtime payload manifest has an unsupported schema or target")
    if payload.get("qemuVersion") != portable_lock["qemu"]["version"]:
        raise ValueError("runtime payload QEMU version differs from its lock")
    if payload.get("qemuBuild") != portable_lock["qemu"]["build"]:
        raise ValueError("runtime payload QEMU build differs from its lock")
    if payload.get("zstdVersion") != portable_lock["zstd"]["version"]:
        raise ValueError("runtime payload zstd version differs from its lock")
    records = payload.get("files")
    if not isinstance(records, list) or payload.get("fileCount") != len(records):
        raise ValueError("runtime payload file count is invalid")

    provenance = load_json(runtime / "provenance.json", "runtime provenance")
    expected_inputs = [
        (portable_lock["qemu"]["installer"]["url"], "sha512", portable_lock["qemu"]["installer"]["sha512"]),
        (portable_lock["qemu"]["source"]["url"], "sha256", portable_lock["qemu"]["source"]["sha256"]),
        (portable_lock["zstd"]["binary"]["url"], "sha256", portable_lock["zstd"]["binary"]["sha256"]),
        (portable_lock["zstd"]["source"]["url"], "sha256", portable_lock["zstd"]["source"]["sha256"]),
    ]
    actual_inputs = [
        (item.get("uri"), next(iter(item.get("digest", {})), ""), next(iter(item.get("digest", {}).values()), ""))
        for item in provenance.get("inputs", [])
    ]
    if actual_inputs != expected_inputs:
        raise ValueError("runtime provenance is not bound to portable-runtime.lock.json")

    expected_records: dict[str, tuple[int, str]] = {}
    for record in records:
        name = safe_zip_name(str(record.get("path", "")))
        size = record.get("size")
        digest = str(record.get("sha256", ""))
        if name in expected_records or not isinstance(size, int) or size < 0 or not SHA256_RE.fullmatch(digest):
            raise ValueError(f"invalid runtime payload record: {record!r}")
        expected_records[name] = (size, digest)
    for required_payload in ("runtime/qemu/qemu-system-x86_64.exe", "runtime/qemu/qemu-img.exe", "tools/zstd.exe"):
        if required_payload not in expected_records:
            raise ValueError(f"runtime payload is missing {required_payload}")

    zstd_destination = work / "zstd.exe"
    with zipfile.ZipFile(archive) as bundle:
        entries: dict[str, zipfile.ZipInfo] = {}
        for entry in bundle.infolist():
            name = safe_zip_name(entry.filename)
            if name.endswith("/"):
                continue
            if name in entries:
                raise ValueError(f"runtime ZIP contains duplicate entry: {name}")
            unix_type = (entry.external_attr >> 16) & 0xF000
            if unix_type == 0xA000:
                raise ValueError(f"runtime ZIP contains a symbolic link: {name}")
            entries[name] = entry
        embedded_name = "runtime/qemu/_compliance/payload-manifest.json"
        if set(entries) != set(expected_records) | {embedded_name}:
            raise ValueError("runtime ZIP contents differ from its payload manifest")
        embedded = bundle.read(embedded_name)
        if embedded != (runtime / "payload-manifest.json").read_bytes():
            raise ValueError("runtime ZIP embeds a different payload manifest")
        for name, (size, digest) in expected_records.items():
            entry = entries[name]
            if entry.file_size != size:
                raise ValueError(f"runtime ZIP length mismatch: {name}")
            hasher = hashlib.sha256()
            with bundle.open(entry) as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    hasher.update(block)
            if hasher.hexdigest() != digest:
                raise ValueError(f"runtime ZIP digest mismatch: {name}")
        with bundle.open(entries["tools/zstd.exe"]) as source, zstd_destination.open("xb") as target:
            shutil.copyfileobj(source, target)
    return parts, zstd_destination, payload


def verify_guest(guest: Path, guest_spec: dict, zstd: Path, work: Path) -> tuple[list[Path], Path, dict]:
    sums = verify_checksum_set(guest)
    required = {
        "manifest.json",
        "provenance.json",
        "sbom.cdx.json",
        "packages.lock.tsv",
        "licenses.json",
        "license-texts.tar.zst",
        "THIRD_PARTY_NOTICES.md",
    }
    if not required.issubset(sums):
        raise ValueError(f"guest release is incomplete: {sorted(required - set(sums))}")
    manifest = load_json(guest / "manifest.json", "guest manifest")
    if manifest.get("schemaVersion") != 1 or manifest.get("kind") != "windows-into-onarchy.factory-guest":
        raise ValueError("guest manifest has an unsupported schema or kind")
    if manifest.get("releaseId") != guest_spec["releaseId"]:
        raise ValueError("guest manifest releaseId differs from guest/spec.json")
    if manifest.get("source") != guest_spec["source"]:
        raise ValueError("guest manifest source differs from guest/spec.json")
    if manifest.get("lifecycle") != guest_spec["lifecycle"]:
        raise ValueError("guest lifecycle differs from guest/spec.json")

    parts = consecutive_parts(guest, GUEST_PART_RE, 0)
    part_records = manifest.get("transport", {}).get("parts", [])
    if [path.name for path in parts] != [record.get("name") for record in part_records]:
        raise ValueError("guest part order differs from its manifest")
    for index, (path, record) in enumerate(zip(parts, part_records, strict=True)):
        if record.get("index") != index or record.get("bytes") != path.stat().st_size or record.get("sha256") != sha256_file(path):
            raise ValueError(f"guest part record mismatch: {path.name}")
    compressed_size, compressed_digest = sha256_files(parts)
    transport = manifest.get("transport", {})
    if compressed_size != transport.get("bytes") or compressed_digest != transport.get("sha256"):
        raise ValueError("guest parts do not reconstruct the declared zstd stream")

    compressed = work / str(transport.get("assembledFilename", ""))
    if compressed.name != guest_spec["image"]["compressedFilename"]:
        raise ValueError("guest compressed filename differs from guest/spec.json")
    with compressed.open("xb") as output:
        for part in parts:
            with part.open("rb") as source:
                shutil.copyfileobj(source, output, 1024 * 1024)
    factory = work / guest_spec["image"]["factoryFilename"]
    subprocess.run(
        [str(zstd), "-q", "-d", "-f", "--sparse", str(compressed), "-o", str(factory)],
        check=True,
    )
    factory_record = manifest.get("factory", {})
    if factory.name != factory_record.get("filename"):
        raise ValueError("expanded guest filename differs from its manifest")
    if factory.stat().st_size != factory_record.get("bytes") or sha256_file(factory) != factory_record.get("sha256"):
        raise ValueError("expanded factory QCOW2 differs from its manifest")
    return parts, factory, manifest


def release_url(tag: str, name: str) -> str:
    if name != Path(name).name:
        raise ValueError(f"unsafe release asset name: {name}")
    return f"https://github.com/{REPOSITORY}/releases/download/{tag}/{name}"


def copy_new(source: Path, destination: Path) -> None:
    plain_file(source, f"release source {source.name}")
    if destination.exists():
        raise ValueError(f"refusing to overwrite staged release asset: {destination}")
    shutil.copyfile(source, destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--runtime", type=Path, required=True)
    parser.add_argument("--guest", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--staging", type=Path, required=True)
    parser.add_argument("--manifest-output", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    runtime = args.runtime.resolve()
    guest = args.guest.resolve()
    work = args.work.resolve()
    staging = args.staging.resolve()
    if work.exists() or staging.exists():
        raise ValueError("assembly work and staging directories must not already exist")
    work.mkdir(parents=True)
    staging.mkdir(parents=True)

    product_lock = load_json(root / "config/runtime.lock.json", "product runtime lock")
    portable_lock = load_json(root / "runtime/portable-runtime.lock.json", "portable runtime lock")
    guest_spec = load_json(root / "guest/spec.json", "guest spec")
    product_version = product_lock["product"]["version"]
    if product_version != "0.3.0":
        raise ValueError("factory assembly is locked to product version 0.3.0")
    if product_lock["qemu"]["version"] != portable_lock["qemu"]["version"]:
        raise ValueError("product and portable runtime QEMU versions differ")
    if product_lock["omarchy"]["version"] != guest_spec["source"]["version"]:
        raise ValueError("product and factory guest Omarchy versions differ")

    runtime_parts, _, runtime_payload = verify_runtime(runtime, portable_lock, work)
    zstd = work / "zstd.exe"
    guest_parts, factory, guest_manifest = verify_guest(guest, guest_spec, zstd, work)
    release_tag = f"factory-v{product_version}"
    build_id = (
        f"factory-{product_version}-omarchy-{guest_spec['source']['version']}-"
        f"qemu-{portable_lock['qemu']['version']}"
    )

    manifest_input = {
        "schemaVersion": 1,
        "product": "Windows Into Onarchy",
        "productVersion": product_version,
        "releaseTag": release_tag,
        "buildId": build_id,
        "architecture": "x86_64",
        "assets": [
            {
                "role": "runtime",
                "archive": "zip",
                "outputRelativePath": "runtime/qemu",
                "payload": {
                    "path": os.path.relpath(runtime / "payload-manifest.json", work),
                    "kind": "tree-manifest",
                    "relativePath": "runtime/qemu/_compliance/payload-manifest.json",
                },
                "parts": [
                    {"path": os.path.relpath(path, work), "url": release_url(release_tag, path.name)}
                    for path in runtime_parts
                ],
            },
            {
                "role": "guest",
                "archive": "zstd",
                "outputRelativePath": "guest/omarchy-factory.qcow2",
                "payload": {
                    "path": os.path.relpath(factory, work),
                    "kind": "file",
                    "relativePath": "guest/omarchy-factory.qcow2",
                },
                "parts": [
                    {"path": os.path.relpath(path, work), "url": release_url(release_tag, path.name)}
                    for path in guest_parts
                ],
            },
        ],
        "upstream": {
            "omarchyCommit": guest_spec["source"]["sourceCommit"],
            "qemuSourceSha256": portable_lock["qemu"]["source"]["sha256"],
        },
    }
    input_path = work / "factory-release-input.json"
    input_path.write_text(json.dumps(manifest_input, indent=2) + "\n", encoding="utf-8")
    manifest_output = args.manifest_output.resolve()
    manifest_output.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [sys.executable, str(root / "factory/build_release_manifest.py"), "--input", str(input_path), "--output", str(manifest_output)],
        check=True,
    )
    root_manifest = load_json(manifest_output, "generated root factory manifest")
    if root_manifest.get("releaseTag") != release_tag or root_manifest.get("buildId") != build_id:
        raise ValueError("root factory manifest identity differs from assembly plan")
    by_role = {asset["role"]: asset for asset in root_manifest["assets"]}
    if by_role["guest"]["payload"]["sha256"] != guest_manifest["factory"]["sha256"]:
        raise ValueError("root manifest guest payload digest differs from independently verified guest")
    if by_role["runtime"]["payload"]["sha256"] != sha256_file(runtime / "payload-manifest.json"):
        raise ValueError("root manifest runtime payload digest differs from independently verified runtime")

    for path in runtime_parts + guest_parts:
        copy_new(path, staging / path.name)
    metadata = {
        runtime / portable_lock["payload"]["sourceArchiveName"]: portable_lock["payload"]["sourceArchiveName"],
        runtime / "payload-manifest.json": "runtime-payload-manifest.json",
        runtime / "runtime.spdx.json": "runtime.spdx.json",
        runtime / "provenance.json": "runtime-provenance.json",
        runtime / "corresponding-source-manifest.json": "runtime-corresponding-source-manifest.json",
        runtime / "license-manifest.json": "runtime-license-manifest.json",
        runtime / "SOURCE-OFFER.txt": "runtime-SOURCE-OFFER.txt",
        runtime / "capability-receipt.json": "runtime-capability-receipt.json",
        guest / "manifest.json": "guest-manifest.json",
        guest / "provenance.json": "guest-provenance.json",
        guest / "sbom.cdx.json": "guest-sbom.cdx.json",
        guest / "packages.lock.tsv": "guest-packages.lock.tsv",
        guest / "licenses.json": "guest-licenses.json",
        guest / "license-texts.tar.zst": "guest-license-texts.tar.zst",
        guest / "THIRD_PARTY_NOTICES.md": "guest-THIRD_PARTY_NOTICES.md",
        manifest_output: "factory-release.json",
    }
    for source, name in metadata.items():
        copy_new(source, staging / name)

    report = {
        "schemaVersion": 1,
        "releaseTag": release_tag,
        "buildId": build_id,
        "runtime": {
            "partCount": len(runtime_parts),
            "payloadManifestSha256": sha256_file(runtime / "payload-manifest.json"),
            "verifiedFileCount": runtime_payload["fileCount"],
        },
        "guest": {
            "partCount": len(guest_parts),
            "factoryBytes": factory.stat().st_size,
            "factorySha256": sha256_file(factory),
        },
        "rootManifestSha256": sha256_file(manifest_output),
        "policy": {"draftOnly": True, "unsignedInstaller": True, "physicalWindowsAcceptanceRequired": True},
    }
    (staging / "assembly-report.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"Prepared verified factory assembly {release_tag} at {staging}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"factory assembly failed: {error}", file=sys.stderr)
        raise SystemExit(1)
