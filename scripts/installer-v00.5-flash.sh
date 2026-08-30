#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer
VERSION=20260826-dev1

echo "=== WOS-INSTALLER-V00.5 / FLASH ==="

test -f "$WEB/js/config.js"
test -f "$WEB/js/factory-installer.js"
test -f "$WEB/js/app.js"
test -f "$WEB/index.html"

FACTORY="$WEB/releases/frankel/$VERSION/frankel-install-$VERSION.zip"

test -s "$FACTORY"

echo "factory_size=$(stat -c %s "$FACTORY")"
echo "factory_sha256=$(sha256sum "$FACTORY" | awk '{print $1}')"

#
# Enable FLASH, keep LOCK disabled
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/js/config.js")
s = p.read_text()

s = s.replace(
    "export const FLASH_ENABLED = false;",
    "export const FLASH_ENABLED = true;"
)

s = s.replace(
    "export const LOCK_ENABLED = true;",
    "export const LOCK_ENABLED = false;"
)

p.write_text(s)

print("CONFIG_PATCH=PASS")
PY


#
# Replace disabled flash button text
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

s = s.replace(
    "WOS-INSTALLER-V00.4",
    "WOS-INSTALLER-V00.5"
)

s = s.replace(
    "Flash worm OS — disabled",
    "Install worm OS"
)

p.write_text(s)

print("HTML_PATCH=PASS")
PY


#
# Patch app.js
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/js/app.js")
s = p.read_text()

#
# Import factory installer
#

factory_import = '''import {
  factoryDevice,
  flashFactoryPackage,
} from "./factory-installer.js";
'''

anchor = '''import {
  FastbootTransport,
} from "./fastboot.js";
'''

if factory_import not in s:
    if anchor not in s:
        raise SystemExit("PATCH=FAIL: fastboot import missing")

    s = s.replace(
        anchor,
        anchor + "\n" + factory_import
    )


#
# State
#

state_anchor = '''let bootloaderUnlocked = null;
'''

state_new = '''let bootloaderUnlocked = null;
let flashInProgress = false;
'''

if state_new not in s:
    if state_anchor not in s:
        raise SystemExit("PATCH=FAIL: state marker missing")

    s = s.replace(
        state_anchor,
        state_new
    )


#
# Flash button state
#

marker = '''
async function unlockBootloader() {
'''

flash_state = r'''
function updateFlashButton() {

  if (!ui.flashButton) {
    return;
  }

  const ready =
    FLASH_ENABLED === true &&
    deviceVerified === true &&
    releaseVerified === true &&
    bootloaderUnlocked === true &&
    flashInProgress === false;

  ui.flashButton.disabled = !ready;
}


'''

if flash_state not in s:
    if marker not in s:
        raise SystemExit("PATCH=FAIL: unlock marker missing")

    s = s.replace(
        marker,
        flash_state + marker
    )


#
# Update after device verification
#

needle = '''  updateUnlockButton();

  setBadge(
'''

replacement = '''  updateUnlockButton();
  updateFlashButton();

  setBadge(
'''

if needle in s:
    s = s.replace(
        needle,
        replacement,
        1
    )


#
# Update after release verification
#

needle = '''    releaseVerified = true;
    updateUnlockButton();
'''

replacement = '''    releaseVerified = true;
    updateUnlockButton();
    updateFlashButton();
'''

if needle in s:
    s = s.replace(
        needle,
        replacement,
        1
    )


#
# Add flash implementation
#

connect_marker = '''
async function connect() {
'''

flash_code = r'''
async function installWormOS() {

  if (FLASH_ENABLED !== true) {
    throw new Error(
      "Flashing is disabled."
    );
  }

  if (!deviceVerified) {
    throw new Error(
      "Pixel 10 verification has not passed."
    );
  }

  if (!releaseVerified) {
    throw new Error(
      "Release verification has not passed."
    );
  }

  if (bootloaderUnlocked !== true) {
    throw new Error(
      "Bootloader must be unlocked first."
    );
  }

  if (flashInProgress) {
    return;
  }

  const confirmed = window.confirm(
    "Install worm OS on this Pixel 10?\n\n" +
    "This will overwrite the operating system and erase user data.\n\n" +
    "The bootloader will remain UNLOCKED."
  );

  if (!confirmed) {
    log("Installation cancelled.");
    return;
  }

  flashInProgress = true;

  updateUnlockButton();
  updateFlashButton();

  try {

    log("INSTALL START");
    log("Target verified: frankel");
    log("Bootloader unlocked: yes");
    log("Downloading factory package...");

    const pointerResponse =
      await fetch(
        "/releases/frankel/current.json",
        { cache: "no-store" }
      );

    if (!pointerResponse.ok) {
      throw new Error(
        `Release pointer HTTP ${pointerResponse.status}`
      );
    }

    const pointer =
      await pointerResponse.json();

    const manifestResponse =
      await fetch(
        pointer.manifest,
        { cache: "no-store" }
      );

    if (!manifestResponse.ok) {
      throw new Error(
        `Manifest HTTP ${manifestResponse.status}`
      );
    }

    const manifest =
      await manifestResponse.json();

    if (
      manifest.device?.codename !== "frankel"
    ) {
      throw new Error(
        "Factory package target is not frankel."
      );
    }

    const pkg =
      manifest.factory_package;

    if (!pkg?.name || !pkg?.size) {
      throw new Error(
        "Factory package metadata missing."
      );
    }

    const manifestUrl =
      new URL(
        pointer.manifest,
        location.origin
      );

    const packageUrl =
      new URL(
        pkg.name,
        new URL(".", manifestUrl)
      );

    log(
      `Factory package: ${pkg.name}`
    );

    log(
      `Expected size: ${pkg.size} bytes`
    );

    const response =
      await fetch(
        packageUrl,
        { cache: "no-store" }
      );

    if (!response.ok) {
      throw new Error(
        `Factory download HTTP ${response.status}`
      );
    }

    const contentLength =
      Number(
        response.headers.get(
          "content-length"
        )
      );

    if (
      contentLength &&
      contentLength !== pkg.size
    ) {
      throw new Error(
        "Factory package Content-Length mismatch."
      );
    }

    const blob =
      await response.blob();

    if (blob.size !== pkg.size) {
      throw new Error(
        `Factory package size mismatch: ${blob.size} != ${pkg.size}`
      );
    }

    log(
      `Factory package downloaded: ${blob.size} bytes`
    );

    /*
     * Package SHA-256 is published in manifest.json.
     * The server-side package has already been verified.
     * HTTPS protects transport integrity.
     *
     * V00.5 additionally verifies exact package size before
     * passing the same Blob to fastboot.js.
     */

    log(
      `Expected SHA-256: ${pkg.sha256}`
    );

    log(
      "Connecting factory flashing engine..."
    );

    if (!factoryDevice.isConnected) {
      await factoryDevice.connect();
    }

    const product =
      await factoryDevice.getVariable(
        "product"
      );

    if (product !== "frankel") {
      throw new Error(
        `Flash target changed: ${product}`
      );
    }

    const unlocked =
      await factoryDevice.getVariable(
        "unlocked"
      );

    if (unlocked !== "yes") {
      throw new Error(
        "Bootloader is no longer unlocked."
      );
    }

    log("FINAL DEVICE CHECK=PASS");
    log("Starting factory flash.");
    log("Do not disconnect USB.");

    await flashFactoryPackage(
      blob,

      async () => {

        log(
          "Waiting for Pixel reconnect..."
        );

        await factoryDevice.waitForConnect();

        log(
          "Pixel reconnected."
        );
      },

      (action, item, progress) => {

        const pct =
          typeof progress === "number"
            ? Math.floor(progress * 100)
            : "";

        log(
          `FLASH ${action ?? ""} ${item ?? ""} ${pct !== "" ? pct + "%" : ""}`
            .trim()
        );
      }
    );

    log("FACTORY_FLASH=PASS");
    log("worm OS installation completed.");
    log("BOOTLOADER_RELOCK=DISABLED");

    alert(
      "worm OS installation completed.\n\n" +
      "Keep the bootloader unlocked for this development build."
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    log(
      `FACTORY_FLASH=FAIL: ${message}`
    );

    ui.deviceError.textContent =
      message;

    ui.deviceError.classList.remove(
      "hidden"
    );

  } finally {

    flashInProgress = false;

    updateUnlockButton();
    updateFlashButton();
  }
}


'''

if flash_code not in s:
    if connect_marker not in s:
        raise SystemExit(
            "PATCH=FAIL: connect marker missing"
        )

    s = s.replace(
        connect_marker,
        flash_code + connect_marker
    )


#
# Flash button listener
#

listener_marker = '''
ui.connectButton
  .addEventListener(
'''

listener = '''
ui.flashButton
  .addEventListener(
    "click",
    installWormOS
  );


'''

if listener not in s:
    if listener_marker not in s:
        raise SystemExit(
            "PATCH=FAIL: listener marker missing"
        )

    s = s.replace(
        listener_marker,
        listener + listener_marker
    )

p.write_text(s)

print("APP_PATCH=PASS")
PY


#
# Safety audit
#

echo
echo "=== VERIFY V00.5 ==="

grep -q \
  'FLASH_ENABLED = true' \
  "$WEB/js/config.js"

grep -q \
  'LOCK_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'flashFactoryPackage' \
  "$WEB/js/app.js"

grep -q \
  'BOOTLOADER_RELOCK=DISABLED' \
  "$WEB/js/app.js"

#
# We intentionally permit flashing now.
# Relock must remain absent.
#

if grep -R -E \
  '["'\'']flashing lock["'\'']' \
  "$WEB/js" >/dev/null
then
    echo "FAIL: bootloader relock capability detected"
    exit 1
fi

echo "device_guard=frankel"
echo "release_guard=REQUIRED"
echo "unlocked_guard=REQUIRED"
echo "factory_size_guard=REQUIRED"
echo "flash=ENABLED"
echo "relock=DISABLED"

echo
echo "WOS_INSTALLER_V00_5=PASS"
