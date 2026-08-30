#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/graphene-app-repo-upstream"
REPO="$ROOT/worm-app-repo"
META=/tmp/graphene-apps-metadata.sjson

echo "=== WOS APPSTORE FULL MIRROR ==="

#
# 1. Get current official signed metadata
#

curl -fL \
  --retry 3 \
  https://apps.grapheneos.org/metadata.1.0.sjson \
  -o "$META"

python3 - "$META" <<'PY'
import json, sys

with open(sys.argv[1]) as f:
    m = json.loads(f.readline())

print("metadata packages =", len(m["packages"]))
print("fsVerityCerts =", list(m.get("fsVerityCerts", {}).keys()))
print("OFFICIAL_METADATA_PARSE=PASS")
PY


#
# 2. Preserve worm package
#

rm -rf /tmp/worm-package-backup
mkdir -p /tmp/worm-package-backup

if [ -d "$REPO/apps/packages/com.worm" ]; then
    cp -a \
      "$REPO/apps/packages/com.worm" \
      /tmp/worm-package-backup/
fi


#
# 3. Reset packages
#

rm -rf "$REPO/apps/packages"
mkdir -p "$REPO/apps/packages"

if [ -d /tmp/worm-package-backup/com.worm ]; then
    cp -a \
      /tmp/worm-package-backup/com.worm \
      "$REPO/apps/packages/"
fi


#
# 4. Remove old fs-verity certs
#

rm -f \
  "$REPO"/fsverity_cert.*.der


#
# 5. Mirror packages from official metadata
#

python3 - "$UPSTREAM" "$REPO" "$META" <<'PY'
from pathlib import Path
import base64
import json
import shutil
import subprocess
import sys

upstream = Path(sys.argv[1])
repo = Path(sys.argv[2])

with open(sys.argv[3]) as f:
    metadata = json.loads(f.readline())

packages = metadata["packages"]
certs = metadata.get("fsVerityCerts", {})

print()
print("=== IMPORT FS-VERITY CERTIFICATES ===")

for cert_id, cert_b64 in certs.items():
    data = base64.b64decode(cert_b64)

    out = repo / f"fsverity_cert.{cert_id}.der"
    out.write_bytes(data)

    print(
        f"fsverity_cert.{cert_id}.der "
        f"{len(data)} bytes"
    )


print()
print("=== IMPORT PACKAGES ===")

for package in sorted(packages):

    #
    # IMPORTANT:
    # worm OS has its own AppStore fork with a different signer.
    #

    if package == "app.grapheneos.apps":
        print(
            "SKIP app.grapheneos.apps "
            "(worm-signed AppStore fork)"
        )
        continue

    common = packages[package]

    src_pkg = (
        upstream /
        "apps/packages" /
        package
    )

    if not src_pkg.exists():
        print(
            f"SKIP {package}: "
            "missing upstream metadata"
        )
        continue

    dst_pkg = (
        repo /
        "apps/packages" /
        package
    )

    dst_pkg.mkdir(
        parents=True,
        exist_ok=True
    )

    #
    # common metadata
    #

    for filename in (
        "common-props.toml",
        "icon.webp",
    ):
        src = src_pkg / filename

        if src.exists():
            shutil.copy2(
                src,
                dst_pkg / filename
            )

    fsverity = bool(
        common.get(
            "hasFsVeritySignatures",
            False
        )
    )

    variants = common.get(
        "variants",
        {}
    )

    print()
    print(package)

    for version, variant in variants.items():

        src_ver = src_pkg / str(version)
        dst_ver = dst_pkg / str(version)

        dst_ver.mkdir(
            parents=True,
            exist_ok=True
        )

        #
        # per-version metadata
        #

        for filename in (
            "channel.toml",
            "props.toml",
        ):
            src = src_ver / filename

            if src.exists():
                shutil.copy2(
                    src,
                    dst_ver / filename
                )

        #
        # All APKs, including splits
        #

        apks = variant.get(
            "apks",
            ["base.apk"]
        )

        has_v4 = bool(
            variant.get(
                "hasV4Signatures",
                False
            )
        )

        for apk in apks:

            base_url = (
                "https://apps.grapheneos.org/"
                f"packages/{package}/"
                f"{version}/{apk}"
            )

            dst_apk = dst_ver / apk

            print(
                f"  {version}/{apk}"
            )

            subprocess.run(
                [
                    "curl",
                    "-fL",
                    "--retry", "3",
                    "--retry-delay", "1",
                    base_url,
                    "-o", str(dst_apk),
                ],
                check=True,
            )

            #
            # APK Signature Scheme v4
            #

            if has_v4:
                subprocess.run(
                    [
                        "curl",
                        "-fL",
                        "--retry", "3",
                        base_url + ".idsig",
                        "-o",
                        str(dst_apk) + ".idsig",
                    ],
                    check=True,
                )

            #
            # fs-verity signatures.
            # One signature per certificate ID.
            #

            if fsverity:
                for cert_id in certs:

                    sig_url = (
                        base_url +
                        f".{cert_id}.fsv_sig"
                    )

                    sig_out = (
                        str(dst_apk) +
                        f".{cert_id}.fsv_sig"
                    )

                    subprocess.run(
                        [
                            "curl",
                            "-fL",
                            "--retry", "3",
                            sig_url,
                            "-o", sig_out,
                        ],
                        check=True,
                    )

print()
print("GRAPHENE_APPS_IMPORT=PASS")
PY


#
# 6. Delete stale generated files for worm too
#

find "$REPO/apps/packages" \
  -type f \
  \( -name '*.apk.gz' \
     -o -name '*.apk.br' \
     -o -name '*.apk.sha256' \) \
  -delete


#
# 7. Generate worm metadata
#

cd "$REPO"

export PATH="/opt/Android/worm-os/upstream/out_adevtool_deps/host/linux-x86/bin:/usr/local/bin:/usr/bin:$PATH"

./generate.py


#
# 8. Sanity check
#

python3 - <<'PY'
import json

m = json.load(
    open("apps/metadata.1.json")
)

print()
print("=== RESULT ===")
print(
    "packages =",
    len(m["packages"])
)
print(
    "fsVerityCerts =",
    list(
        m.get(
            "fsVerityCerts",
            {}
        ).keys()
    )
)

assert "com.worm" in m["packages"]
assert "app.grapheneos.apps" not in m["packages"]

print("com.worm=PASS")
print("AppStore fork protection=PASS")
print("WOS_APPSTORE_REBUILD=PASS")
PY
