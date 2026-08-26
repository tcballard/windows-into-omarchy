#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 4 ]] || {
  echo "Usage: guest/extract-metadata.sh IMAGE.qcow2 SPEC.json OUTPUT_DIR WORK_DIR" >&2
  exit 2
}
IMAGE=$1
SPEC=$2
OUTPUT=$3
WORK=$4
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

for command in guestfish python3 tar zstd; do
  command -v "$command" >/dev/null || { echo "$command is required" >&2; exit 1; }
done
mkdir -p "$OUTPUT" "$WORK"
EXTRACT="$WORK/metadata"
mkdir -p "$EXTRACT"
[[ ! -e $EXTRACT/local && ! -e $EXTRACT/licenses ]] || {
  echo "metadata work directory is not empty: $EXTRACT" >&2
  exit 1
}

guestfish --ro -a "$IMAGE" <<EOF
run
mount-options ro,subvol=@ /dev/sda2 /
copy-out /var/lib/pacman/local $EXTRACT
copy-out /usr/share/licenses $EXTRACT
EOF

RELEASE_ID=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["releaseId"])' "$SPEC")
SOURCE_EPOCH=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["builder"]["sourceDateEpoch"])' "$SPEC")
python3 "$SCRIPT_DIR/scripts/package_metadata.py" \
  --pacman-db "$EXTRACT/local" \
  --license-tree "$EXTRACT/licenses" \
  --output-dir "$OUTPUT" \
  --release-id "$RELEASE_ID" \
  --source-epoch "$SOURCE_EPOCH"

tar --sort=name --mtime="@$SOURCE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$EXTRACT" -cf - licenses | zstd -q -T0 -15 -o "$OUTPUT/license-texts.tar.zst"

PACKAGE_COUNT=$(($(wc -l < "$OUTPUT/packages.lock.tsv") - 1))
cat >"$OUTPUT/THIRD_PARTY_NOTICES.md" <<EOF
# Factory guest third-party notices

This candidate contains a complete Arch Linux and Omarchy filesystem, not only
Windows Into Omarchy's MIT-licensed launcher code.

- Omarchy version: 4.0.1
- Omarchy source commit: 0ae1694830b6bd9511042fe1b89a0062d8c083cb
- Installed package count: $PACKAGE_COUNT
- Exact package/version/license fields: \`packages.lock.tsv\` and \`licenses.json\`
- Machine-readable inventory: \`sbom.cdx.json\`
- Packaged license texts: \`license-texts.tar.zst\`

Names and license expressions are transcribed from the installed pacman
database. Custom license labels are not silently converted to SPDX identifiers.
Review corresponding-source, notice, firmware, font, media, trademark, and any
proprietary-package obligations before publishing this disk. These generated
materials support that review but are not a legal conclusion.
EOF
