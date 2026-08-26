#!/usr/bin/env python3
"""Create package inventory, CycloneDX SBOM, and license inventory from pacman DB."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import quote


def read_desc(path: Path) -> dict[str, list[str]]:
    fields: dict[str, list[str]] = {}
    key: str | None = None
    for line in path.read_text(encoding="utf-8", errors="strict").splitlines():
        if line.startswith("%") and line.endswith("%"):
            key = line[1:-1]
            fields.setdefault(key, [])
        elif line and key is not None:
            fields[key].append(line)
    return fields


def one(fields: dict[str, list[str]], key: str) -> str:
    values = fields.get(key, [])
    if len(values) != 1:
        raise ValueError(f"expected one %{key}% value, got {values!r}")
    return values[0]


def normalized_license(value: str) -> dict[str, dict[str, str]]:
    # Arch license values are identifiers or free-form expressions. Preserve
    # the exact installed metadata; emit SPDX IDs only when they are plainly
    # valid SPDX-like tokens rather than guessing equivalence.
    if re.fullmatch(r"[A-Za-z0-9.+-]+", value) and value not in {"custom", "unknown"}:
        return {"license": {"id": value}}
    return {"license": {"name": value}}


def load_packages(database: Path) -> list[dict[str, object]]:
    packages: list[dict[str, object]] = []
    for desc in sorted(database.glob("*/desc")):
        fields = read_desc(desc)
        name = one(fields, "NAME")
        version = one(fields, "VERSION")
        architecture = one(fields, "ARCH")
        licenses = fields.get("LICENSE", ["unknown"])
        purl = f"pkg:pacman/{quote(name)}@{quote(version)}?arch={quote(architecture)}"
        packages.append(
            {
                "name": name,
                "version": version,
                "architecture": architecture,
                "description": " ".join(fields.get("DESC", [])),
                "url": " ".join(fields.get("URL", [])),
                "packager": " ".join(fields.get("PACKAGER", [])),
                "licenses": licenses,
                "purl": purl,
            }
        )
    if not packages:
        raise ValueError(f"no pacman package descriptions found under {database}")
    packages.sort(key=lambda package: (str(package["name"]), str(package["version"])))
    return packages


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pacman-db", type=Path, required=True)
    parser.add_argument("--license-tree", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--release-id", required=True)
    parser.add_argument("--source-epoch", type=int, required=True)
    args = parser.parse_args()

    packages = load_packages(args.pacman_db)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    lines = ["name\tversion\tarchitecture\tlicenses\turl"]
    for package in packages:
        fields = [
            str(package["name"]),
            str(package["version"]),
            str(package["architecture"]),
            ", ".join(package["licenses"]),  # type: ignore[arg-type]
            str(package["url"]),
        ]
        if any("\t" in field or "\n" in field for field in fields):
            raise ValueError(f"package metadata contains unsafe TSV text: {package['name']}")
        lines.append("\t".join(fields))
    (args.output_dir / "packages.lock.tsv").write_text(
        "\n".join(lines) + "\n", encoding="utf-8", newline="\n"
    )

    components = []
    for package in packages:
        component: dict[str, object] = {
            "type": "library",
            "bom-ref": package["purl"],
            "name": package["name"],
            "version": package["version"],
            "purl": package["purl"],
            "licenses": [normalized_license(value) for value in package["licenses"]],
            "properties": [
                {"name": "arch:architecture", "value": package["architecture"]},
                {"name": "arch:packager", "value": package["packager"] or "unknown"},
            ],
        }
        if package["description"]:
            component["description"] = package["description"]
        if package["url"]:
            component["externalReferences"] = [
                {"type": "website", "url": package["url"]}
            ]
        components.append(component)

    timestamp = __import__("datetime").datetime.fromtimestamp(
        args.source_epoch, tz=__import__("datetime").timezone.utc
    ).isoformat().replace("+00:00", "Z")
    sbom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{__import__('uuid').uuid5(__import__('uuid').NAMESPACE_URL, args.release_id)}",
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "component": {
                "type": "operating-system",
                "name": "Windows Into Onarchy factory guest",
                "version": args.release_id,
            },
            "properties": [
                {"name": "inventory:source", "value": "/var/lib/pacman/local"},
                {"name": "inventory:network-used", "value": "false"},
            ],
        },
        "components": components,
    }
    (args.output_dir / "sbom.cdx.json").write_text(
        json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
    )

    license_text_packages = (
        sorted(path.name for path in args.license_tree.iterdir())
        if args.license_tree.is_dir()
        else []
    )
    expressions: dict[str, list[str]] = {}
    for package in packages:
        for license_name in package["licenses"]:  # type: ignore[union-attr]
            expressions.setdefault(str(license_name), []).append(str(package["name"]))
    license_inventory = {
        "schemaVersion": 1,
        "releaseId": args.release_id,
        "claim": "Exact installed pacman license fields plus packaged /usr/share/licenses texts; no SPDX equivalence is inferred for custom expressions.",
        "packageCount": len(packages),
        "licenseExpressions": [
            {"expression": expression, "packages": sorted(names)}
            for expression, names in sorted(expressions.items())
        ],
        "packagesWithLicenseTextDirectories": license_text_packages,
        "licenseTextArchive": "license-texts.tar.zst",
        "distributionApprovalRequired": True,
    }
    (args.output_dir / "licenses.json").write_text(
        json.dumps(license_inventory, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
