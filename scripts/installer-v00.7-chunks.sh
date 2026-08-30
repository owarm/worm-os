#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
VERSION=20260826-dev1
RELEASE="$ROOT/web-installer/releases/frankel/$VERSION"

FACTORY="$RELEASE/frankel-install-$VERSION.zip"
MANIFEST="$RELEASE/manifest.json"
CHUNKS="$RELEASE/factory-chunks.json"

echo "=== WOS-INSTALLER-V00.7 / CHUNK MANIFEST ==="

test -f "$FACTORY"
test -f "$MANIFEST"

python3 - \
  "$FACTORY" \
  "$MANIFEST" \
  "$CHUNKS" <<'PY'
import hashlib
import json
import pathlib
import sys

factory = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
chunks_path = pathlib.Path(sys.argv[3])

CHUNK_SIZE = 32 * 1024 * 1024

manifest = json.loads(
    manifest_path.read_text()
)

pkg = manifest["factory_package"]

if factory.stat().st_size != pkg["size"]:
    raise SystemExit(
        "FAIL: factory size differs from manifest"
    )

overall = hashlib.sha256()
chunks = []

offset = 0
index = 0

with factory.open("rb") as f:
    while True:
        data = f.read(CHUNK_SIZE)

        if not data:
            break

        overall.update(data)

        chunks.append({
            "index": index,
            "offset": offset,
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })

        print(
            f"chunk={index:03d} "
            f"offset={offset} "
            f"size={len(data)}"
        )

        offset += len(data)
        index += 1

actual = overall.hexdigest()

if actual.lower() != pkg["sha256"].lower():
    raise SystemExit(
        "FAIL: overall SHA-256 mismatch"
    )

chunk_manifest = {
    "schema": 1,
    "algorithm": "SHA-256",
    "name": pkg["name"],
    "size": pkg["size"],
    "sha256": pkg["sha256"],
    "chunk_size": CHUNK_SIZE,
    "chunks": chunks,
}

chunks_path.write_text(
    json.dumps(
        chunk_manifest,
        indent=2
    ) + "\n"
)

pkg["chunk_manifest"] = "factory-chunks.json"

manifest["installer"] = \
    "WOS-INSTALLER-V00.7"

manifest["safety"] = {
    "unlock_enabled": True,
    "flash_enabled": True,
    "lock_enabled": False,
}

manifest_path.write_text(
    json.dumps(
        manifest,
        indent=2
    ) + "\n"
)

print()
print(f"chunks={len(chunks)}")
print(f"size={offset}")
print(f"sha256={actual}")
print("CHUNK_MANIFEST=PASS")
PY

echo
echo "=== VERIFY ==="

python3 -m json.tool \
  "$CHUNKS" >/dev/null

python3 -m json.tool \
  "$MANIFEST" >/dev/null

grep -A8 \
  '"factory_package"' \
  "$MANIFEST"

echo
echo "WOS_INSTALLER_V00_7_CHUNKS=PASS"
