#!/usr/bin/env python3
"""Build the deterministic, credential-free Omarchy cidata FAT image.

The launcher needs no filesystem tooling on Windows: the generated 1.44 MiB
FAT12 image is committed at image/cidata/cidata.img and attached read-only to
QEMU.  All timestamps, aliases, allocation order, and the volume serial are
fixed so the same two source files produce identical bytes on every host.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import struct
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE_DIR = ROOT / "cidata"
DEFAULT_OUTPUT = SOURCE_DIR / "cidata.img"

BYTES_PER_SECTOR = 512
TOTAL_SECTORS = 2880
RESERVED_SECTORS = 1
FAT_COUNT = 2
SECTORS_PER_FAT = 9
ROOT_ENTRIES = 224
ROOT_SECTORS = 14
DATA_START_SECTOR = RESERVED_SECTORS + FAT_COUNT * SECTORS_PER_FAT + ROOT_SECTORS
IMAGE_BYTES = BYTES_PER_SECTOR * TOTAL_SECTORS
FAT_EOF = 0xFFF

FILES = (
    ("user_configuration.json", b"USER_C~1JSO"),
    ("defer-provisioning", b"DEFER-~1   "),
)


def _read_payload(name: str) -> bytes:
    payload = (SOURCE_DIR / name).read_bytes()
    # Git may materialize text with CRLF on Windows. The cidata artifact is a
    # cryptographically locked build input, so canonicalize text before laying
    # it out rather than allowing checkout policy to change its identity.
    if name.endswith((".json", ".txt")):
        payload = payload.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return payload


def _set_fat12_entry(fat: bytearray, cluster: int, value: int) -> None:
    offset = cluster + cluster // 2
    if cluster % 2 == 0:
        fat[offset] = value & 0xFF
        fat[offset + 1] = (fat[offset + 1] & 0xF0) | ((value >> 8) & 0x0F)
    else:
        fat[offset] = (fat[offset] & 0x0F) | ((value << 4) & 0xF0)
        fat[offset + 1] = (value >> 4) & 0xFF


def _short_name_checksum(short_name: bytes) -> int:
    checksum = 0
    for value in short_name:
        checksum = (((checksum & 1) << 7) | (checksum >> 1)) + value
        checksum &= 0xFF
    return checksum


def _lfn_entries(name: str, short_name: bytes) -> list[bytes]:
    units = list(struct.unpack(f"<{len(name)}H", name.encode("utf-16le")))
    units.append(0x0000)
    while len(units) % 13:
        units.append(0xFFFF)

    chunks = [units[index : index + 13] for index in range(0, len(units), 13)]
    checksum = _short_name_checksum(short_name)
    entries: list[bytes] = []
    for sequence in range(len(chunks), 0, -1):
        chunk = chunks[sequence - 1]
        entry = bytearray(32)
        entry[0] = sequence | (0x40 if sequence == len(chunks) else 0)
        entry[1:11] = struct.pack("<5H", *chunk[0:5])
        entry[11] = 0x0F
        entry[12] = 0
        entry[13] = checksum
        entry[14:26] = struct.pack("<6H", *chunk[5:11])
        entry[26:28] = b"\0\0"
        entry[28:32] = struct.pack("<2H", *chunk[11:13])
        entries.append(bytes(entry))
    return entries


def _directory_entry(short_name: bytes, first_cluster: int, size: int) -> bytes:
    if len(short_name) != 11:
        raise ValueError("FAT short names must be exactly 11 bytes")
    entry = bytearray(32)
    entry[0:11] = short_name
    entry[11] = 0x20  # archive
    # Deterministic 1980-01-01 00:00:00 DOS timestamps.
    dos_date = 0x0021
    struct.pack_into("<H", entry, 16, dos_date)
    struct.pack_into("<H", entry, 18, dos_date)
    struct.pack_into("<H", entry, 24, dos_date)
    struct.pack_into("<H", entry, 26, first_cluster)
    struct.pack_into("<I", entry, 28, size)
    return bytes(entry)


def _boot_sector() -> bytes:
    sector = bytearray(BYTES_PER_SECTOR)
    sector[0:3] = b"\xeb\x3c\x90"
    sector[3:11] = b"WIOCIDAT"
    struct.pack_into("<H", sector, 11, BYTES_PER_SECTOR)
    sector[13] = 1  # sectors per cluster
    struct.pack_into("<H", sector, 14, RESERVED_SECTORS)
    sector[16] = FAT_COUNT
    struct.pack_into("<H", sector, 17, ROOT_ENTRIES)
    struct.pack_into("<H", sector, 19, TOTAL_SECTORS)
    sector[21] = 0xF0
    struct.pack_into("<H", sector, 22, SECTORS_PER_FAT)
    struct.pack_into("<H", sector, 24, 18)  # sectors per track
    struct.pack_into("<H", sector, 26, 2)  # heads
    sector[36] = 0
    sector[38] = 0x29
    struct.pack_into("<I", sector, 39, 0x57494F31)  # "WIO1"
    sector[43:54] = b"CIDATA     "
    sector[54:62] = b"FAT12   "
    sector[510:512] = b"\x55\xaa"
    return bytes(sector)


def build_image() -> bytes:
    present = {path.name for path in SOURCE_DIR.iterdir() if path.is_file()}
    expected = {name for name, _ in FILES}
    # cidata.img is an output, not configuration input.
    unexpected = present - expected - {"cidata.img"}
    missing = expected - present
    if unexpected or missing:
        raise ValueError(
            f"cidata source set mismatch; missing={sorted(missing)}, "
            f"unexpected={sorted(unexpected)}"
        )

    payloads = [(name, short_name, _read_payload(name)) for name, short_name in FILES]
    image = bytearray(IMAGE_BYTES)
    image[:BYTES_PER_SECTOR] = _boot_sector()

    fat = bytearray(SECTORS_PER_FAT * BYTES_PER_SECTOR)
    fat[0:3] = b"\xf0\xff\xff"
    root_entries: list[bytes] = []
    volume = bytearray(32)
    volume[0:11] = b"CIDATA     "
    volume[11] = 0x08
    root_entries.append(bytes(volume))

    next_cluster = 2
    data_offset = DATA_START_SECTOR * BYTES_PER_SECTOR
    for name, short_name, payload in payloads:
        cluster_count = (len(payload) + BYTES_PER_SECTOR - 1) // BYTES_PER_SECTOR
        first_cluster = next_cluster if cluster_count else 0
        for index in range(cluster_count):
            cluster = next_cluster + index
            following = cluster + 1 if index + 1 < cluster_count else FAT_EOF
            _set_fat12_entry(fat, cluster, following)
            start = data_offset + (cluster - 2) * BYTES_PER_SECTOR
            chunk = payload[index * BYTES_PER_SECTOR : (index + 1) * BYTES_PER_SECTOR]
            image[start : start + len(chunk)] = chunk
        next_cluster += cluster_count
        root_entries.extend(_lfn_entries(name, short_name))
        root_entries.append(_directory_entry(short_name, first_cluster, len(payload)))

    if len(root_entries) > ROOT_ENTRIES:
        raise ValueError("cidata root directory overflow")

    fat_start = RESERVED_SECTORS * BYTES_PER_SECTOR
    for index in range(FAT_COUNT):
        start = fat_start + index * len(fat)
        image[start : start + len(fat)] = fat

    root_start = (RESERVED_SECTORS + FAT_COUNT * SECTORS_PER_FAT) * BYTES_PER_SECTOR
    for index, entry in enumerate(root_entries):
        start = root_start + index * 32
        image[start : start + 32] = entry

    return bytes(image)


def _write_atomic(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail unless the existing output exactly matches a fresh build",
    )
    args = parser.parse_args()

    content = build_image()
    digest = hashlib.sha256(content).hexdigest()
    if args.check:
        if not args.output.is_file() or args.output.read_bytes() != content:
            raise SystemExit(f"cidata image is stale: regenerate {args.output}")
    else:
        _write_atomic(args.output, content)
    print(f"{digest}  {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
