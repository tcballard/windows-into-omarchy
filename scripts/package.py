#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import shutil
import stat
import subprocess
import sys
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
LOCK = json.loads((ROOT / "config/runtime.lock.json").read_text(encoding="utf-8"))
VERSION = LOCK["product"]["version"]
NAME = f"Windows-Into-Onarchy-v{VERSION}"
STAGE = DIST / "package" / NAME
ARCHIVE = DIST / f"{NAME}.zip"
FIXED_TIME = (2026, 8, 25, 12, 0, 0)

INCLUDED_ROOTS = (
    ".github",
    "assets",
    "config",
    "docs",
    "installer",
    "image",
    "launcher",
    "runtime",
    "scripts",
    "tests",
)
INCLUDED_FILES = (
    "LICENSE",
    "Makefile",
    "README.md",
    "SECURITY.md",
    "Start-WindowsIntoOmarchy.cmd",
    "WindowsIntoOmarchy.vbs",
    "THIRD_PARTY_NOTICES.md",
)


def included_files() -> list[Path]:
    files = [ROOT / name for name in INCLUDED_FILES]
    for name in INCLUDED_ROOTS:
        files.extend(
            path
            for path in (ROOT / name).rglob("*")
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc"
        )
    result = sorted(set(files))
    result = [path for path in result if path != ROOT / "assets/cidata.img"]
    for path in result:
        if path.is_symlink():
            raise SystemExit(f"refusing symlink in package: {path}")
    return result


def main() -> None:
    subprocess.run([sys.executable, str(ROOT / "image/make_cidata.py")], check=True)
    files = included_files()
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True)
    for source in files:
        target = STAGE / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    ARCHIVE.parent.mkdir(parents=True, exist_ok=True)
    if ARCHIVE.exists():
        ARCHIVE.unlink()
    with zipfile.ZipFile(ARCHIVE, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in sorted(path for path in STAGE.rglob("*") if path.is_file()):
            relative = source.relative_to(STAGE.parent).as_posix()
            info = zipfile.ZipInfo(relative, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if source.suffix in {".py", ".ps1", ".cmd"} else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            archive.writestr(info, source.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)

    digest = hashlib.sha256(ARCHIVE.read_bytes()).hexdigest()
    (DIST / "SHA256SUMS").write_text(f"{digest}  {ARCHIVE.name}\n", encoding="ascii")
    print(f"built {ARCHIVE}")
    print(f"sha256 {digest}")


if __name__ == "__main__":
    main()
