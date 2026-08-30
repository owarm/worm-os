#!/bin/bash
set -Eeuo pipefail

WORM=/opt/Android/worm
OS=/opt/Android/worm-os
UPSTREAM="$OS/upstream"

DEST="$UPSTREAM/vendor/worm/WormLauncher"
FRANKEL="$UPSTREAM/vendor/google_devices/frankel/frankel.mk"
PATCHDIR="$OS/patches/launcher"

APK="$WORM/app/build/outputs/apk/release/app-release.apk"
APKSIG_JAR="$WORM/.gradle-codex/caches/modules-2/files-2.1/com.android.tools.build/apksig/9.3.1/2881101f6a9d0baf6a341926ef0ff08c98a5d13b/apksig-9.3.1.jar"

mkdir -p "$PATCHDIR"

echo "=== WOS-WORM-V00.1 ==="
echo "source=$WORM"
echo "target=frankel"
echo

test -x "$WORM/gradlew"

echo "=== BUILD WORM APK ==="

cd "$WORM"

export GRADLE_USER_HOME="$WORM/.gradle-codex"

./gradlew \
    --no-daemon \
    clean \
    assembleRelease

echo "gradle=PASS"

if [ ! -f "$APK" ]; then
    echo "FAIL: release APK not found"
    exit 1
fi

echo
echo "=== LOCATE APK ==="
echo "apk=$APK"

AAPT2="$UPSTREAM/out/host/linux-x86/bin/aapt2"

if [ ! -x "$AAPT2" ]; then
    AAPT2="$(command -v aapt2 || true)"
fi

if [ -z "$AAPT2" ] || [ ! -x "$AAPT2" ]; then
    echo "FAIL: aapt2 unavailable"
    exit 1
fi

echo "aapt2=$AAPT2"

echo
echo "=== VERIFY SIGNATURE ==="

if command -v apksigner >/dev/null 2>&1; then
    apksigner verify --verbose --print-certs "$APK"
elif [ -f "$APKSIG_JAR" ]; then
    cat >/tmp/VerifyApk.java <<'EOF'
import com.android.apksig.ApkVerifier;
import java.io.File;

public class VerifyApk {
    public static void main(String[] args) throws Exception {
        ApkVerifier.Result result = new ApkVerifier.Builder(new File(args[0])).build().verify();
        if (!result.isVerified()) {
            throw new IllegalStateException("APK signature verification failed");
        }
        System.out.println("verified=" + result.isVerified());
        System.out.println("verifiedUsingV2=" + result.isVerifiedUsingV2Scheme());
        System.out.println("signerCount=" + result.getSignerCertificates().size());
    }
}
EOF
    javac -cp "$APKSIG_JAR" /tmp/VerifyApk.java
    java -cp /tmp:"$APKSIG_JAR" VerifyApk "$APK"
else
    echo "FAIL: no APK signature verifier available"
    exit 1
fi

echo
echo "=== APK INFO ==="

BADGING="$("$AAPT2" dump badging "$APK")"

PACKAGE="$(
    printf '%s\n' "$BADGING" \
        | sed -n "s/^package: name='\([^']*\)'.*/\1/p" \
        | head -1
)"

if [ -z "$PACKAGE" ]; then
    echo "FAIL: unable to determine package"
    exit 1
fi

echo "package=$PACKAGE"

if [ "$PACKAGE" = "com.android.launcher3" ]; then
    echo "FAIL: worm conflicts with GrapheneOS Launcher3 package"
    exit 1
fi

MANIFEST_DUMP="$(
    "$AAPT2" dump xmltree         --file AndroidManifest.xml         "$APK"
)"

if ! printf '%s\n' "$MANIFEST_DUMP"     | grep -q "android.intent.category.HOME"
then
    echo "FAIL: APK does not advertise HOME"
    exit 1
fi

if ! printf '%s\n' "$MANIFEST_DUMP"     | grep -q "android.intent.category.DEFAULT"
then
    echo "FAIL: APK HOME activity lacks DEFAULT category"
    exit 1
fi

echo "home_intent=PASS"

echo
echo "=== INSTALL PREBUILT MODULE ==="

mkdir -p "$DEST/prebuilt"

cp -f "$APK" \
    "$DEST/prebuilt/WormLauncher.apk"

chown -R 1000:1000 "$UPSTREAM/vendor/worm"

cat > "$DEST/Android.bp" <<'BP'
android_app_import {
    name: "WormLauncher",
    product_specific: true,
    apk: "prebuilt/WormLauncher.apk",
    presigned: true,
    privileged: false,

    optional_uses_libs: [
        "androidx.window.extensions",
        "androidx.window.sidecar",
    ],
}
BP

chown 1000:1000 "$DEST/Android.bp"

echo "android_app_import=PASS"

echo
echo "=== FRANKEL PRODUCT ==="

cp "$FRANKEL" /tmp/frankel.worm.before

if ! grep -q 'PRODUCT_PACKAGES += WormLauncher' "$FRANKEL"; then
    cat >> "$FRANKEL" <<'MK'

# worm OS: preinstall worm launcher on Pixel 10 / frankel.
PRODUCT_PACKAGES += WormLauncher
MK
fi

chown 1000:1000 "$FRANKEL"

grep -n -A2 -B2 \
    'PRODUCT_PACKAGES += WormLauncher' \
    "$FRANKEL"

echo "frankel_package=PASS"

diff -u \
    /tmp/frankel.worm.before \
    "$FRANKEL" \
    > "$PATCHDIR/WOS-WORM-V00.1-frankel.patch" \
    || true

sha256sum \
    "$DEST/prebuilt/WormLauncher.apk" \
    > "$PATCHDIR/WOS-WORM-V00.1-apk.sha256"

cat > "$PATCHDIR/WOS-WORM-V00.1-info.txt" <<INFO
project=worm OS
milestone=WOS-WORM-V00.1
device=Pixel 10
codename=frankel

module=WormLauncher
package=$PACKAGE
source=$WORM
apk=$APK

preinstalled=true
default_home=not_forced_yet
Launcher3=fallback_kept

phone=not_touched
INFO

echo
echo "=== RESULT ==="
echo "package=$PACKAGE"
echo "preinstalled=PASS"
echo "Launcher3=KEPT_AS_FALLBACK"
echo "default_home=NOT_FORCED"
echo "phone=NOT_TOUCHED"
echo
echo "WOS_WORM_V00_1=PASS"
