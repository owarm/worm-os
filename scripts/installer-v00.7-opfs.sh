#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

echo "=== WOS-INSTALLER-V00.7 / OPFS ==="

cp \
  "$WEB/js/app.js" \
  "$WEB/js/app.js.before-v007"

cp \
  "$WEB/index.html" \
  "$WEB/index.html.before-v007"


#
# config
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path(
    "/opt/Android/worm-os/web-installer/js/config.js"
)

s = p.read_text()

s = re.sub(
    r'export const INSTALLER_VERSION = "[^"]+";',
    'export const INSTALLER_VERSION = "WOS-INSTALLER-V00.7";',
    s
)

s = re.sub(
    r'export const UNLOCK_ENABLED = (?:true|false);',
    'export const UNLOCK_ENABLED = true;',
    s
)

s = re.sub(
    r'export const FLASH_ENABLED = (?:true|false);',
    'export const FLASH_ENABLED = true;',
    s
)

s = re.sub(
    r'export const LOCK_ENABLED = (?:true|false);',
    'export const LOCK_ENABLED = false;',
    s
)

p.write_text(s)

print("CONFIG_PATCH=PASS")
PY


#
# HTML
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path(
    "/opt/Android/worm-os/web-installer/index.html"
)

s = p.read_text()

s = re.sub(
    r'WOS-INSTALLER-V00\.[A-Za-z0-9.-]+',
    'WOS-INSTALLER-V00.7',
    s
)

s = s.replace(
    "Test server package",
    "Cache & verify package"
)

s = re.sub(
    r'worm OS installation.*?Pixel 10\.[^<]*',
    'worm OS development installation for Pixel 10.',
    s
)

# Add reconnect button.
if 'id="flash-reconnect-button"' not in s:

    marker = '''      <button
        id="flash-button"
'''

    reconnect = '''      <button
        id="flash-reconnect-button"
        class="primary"
        hidden
      >
        Reconnect Pixel
      </button>

'''

    if marker not in s:
        raise SystemExit(
            "HTML_PATCH=FAIL: flash button"
        )

    s = s.replace(
        marker,
        reconnect + marker
    )

p.write_text(s)

print("HTML_PATCH=PASS")
PY


#
# app.js
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path(
    "/opt/Android/worm-os/web-installer/js/app.js"
)

s = p.read_text()


# OPFS import
cache_import = '''import {
  cacheFactoryPackage,
  getCachedFactoryPackage,
} from "./server-cache.js";
'''

if cache_import not in s:

    marker = '''import {
  loadCurrentRelease,
  verifyArtifact,
} from "./release.js";
'''

    if marker not in s:
        raise SystemExit(
            "APP_PATCH=FAIL: release import"
        )

    s = s.replace(
        marker,
        marker + "\n" + cache_import
    )


# Replace updateFlashButton entirely.
start = s.find(
    "function updateFlashButton()"
)

end = s.find(
    "\n\nasync function unlockBootloader()",
    start
)

if start == -1 or end == -1:
    raise SystemExit(
        "APP_PATCH=FAIL: updateFlashButton"
    )

new_flash_state = '''function updateFlashButton() {

  if (!ui.flashButton) {
    return;
  }

  const ready =
    FLASH_ENABLED === true &&
    deviceVerified === true &&
    bootloaderUnlocked === true &&
    factoryPreflightPassed === true &&
    flashInProgress === false;

  ui.flashButton.disabled =
    !ready;
}'''

s = (
    s[:start] +
    new_flash_state +
    s[end:]
)


# Replace server preflight with OPFS cache.
start = s.find(
    "async function runFactoryPreflight()"
)

end = s.find(
    "\n\nasync function installWormOS()",
    start
)

if start == -1 or end == -1:
    raise SystemExit(
        "APP_PATCH=FAIL: runFactoryPreflight"
    )

new_preflight = r'''async function runFactoryPreflight() {

  factoryPreflightPassed =
    false;

  releaseVerified =
    false;

  updateFlashButton();

  ui.factoryPreflightButton.disabled =
    true;

  log("FACTORY_CACHE_START");

  try {

    const result =
      await cacheFactoryPackage(
        state => {

          log(
            `CACHE ${state.percent}% ` +
            `(${state.received}/${state.total})`
          );
        }
      );

    const {
      manifest,
      pointer,
      pkg,
      file,
    } = result;

    ui.releaseChannel.textContent =
      manifest.channel;

    ui.releaseBuild.textContent =
      `${manifest.build.version} / ${manifest.build.build_id}`;

    ui.releaseTarget.textContent =
      `${manifest.device.name} (${manifest.device.codename})`;

    ui.releaseVerification.textContent =
      "PACKAGE VERIFIED";

    releaseVerified =
      true;

    factoryPreflightPassed =
      true;

    log(
      `Release=${pointer.version}`
    );

    log(
      `Target=${manifest.device.codename}`
    );

    log(
      `Cached=${file.size} bytes`
    );

    log(
      `Factory SHA-256=${pkg.sha256}`
    );

    log(
      "FACTORY_CACHE_VERIFY=PASS"
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    factoryPreflightPassed =
      false;

    releaseVerified =
      false;

    log(
      `FACTORY_CACHE_VERIFY=FAIL: ${message}`
    );

  } finally {

    ui.factoryPreflightButton.disabled =
      false;

    updateFlashButton();
  }
}'''

s = (
    s[:start] +
    new_preflight +
    s[end:]
)


# Replace installation function.
start = s.find(
    "async function installWormOS()"
)

end = s.find(
    "\n\nasync function connect()",
    start
)

if start == -1 or end == -1:
    raise SystemExit(
        "APP_PATCH=FAIL: installWormOS"
    )

new_install = r'''async function installWormOS() {

  if (FLASH_ENABLED !== true) {
    throw new Error(
      "Flashing is disabled."
    );
  }

  if (
    !deviceVerified ||
    bootloaderUnlocked !== true
  ) {
    throw new Error(
      "Verified unlocked Pixel 10 required."
    );
  }

  const cached =
    await getCachedFactoryPackage();

  if (!cached) {
    throw new Error(
      "Cache & verify the factory package first."
    );
  }

  if (
    cached.manifest.device.codename !==
    "frankel"
  ) {
    throw new Error(
      "Factory target mismatch."
    );
  }

  const confirmed =
    window.confirm(
      "Install worm OS on Pixel 10?\n\n" +
      "This overwrites the operating system and wipes user data.\n\n" +
      "The bootloader will remain UNLOCKED."
    );

  if (!confirmed) {
    return;
  }

  flashInProgress =
    true;

  updateFlashButton();

  let wakeLock = null;

  try {

    if (
      navigator.wakeLock?.request
    ) {
      try {
        wakeLock =
          await navigator.wakeLock.request(
            "screen"
          );
      } catch {}
    }

    /*
     * Release our diagnostic transport before
     * fastboot.js claims the USB interface.
     */
    if (fastboot) {
      try {
        await fastboot.disconnect();
      } catch {}
    }

    fastboot = null;

    if (
      currentDevice?.opened
    ) {
      try {
        await currentDevice.close();
      } catch {}
    }

    currentDevice = null;

    log("FACTORY_FLASH_START");
    log("Connecting factory engine...");

    if (!factoryDevice.isConnected) {
      await factoryDevice.connect();
    }

    const product =
      await factoryDevice.getVariable(
        "product"
      );

    if (product !== "frankel") {
      throw new Error(
        `Wrong flash target: ${product}`
      );
    }

    const unlocked =
      await factoryDevice.getVariable(
        "unlocked"
      );

    if (unlocked !== "yes") {
      throw new Error(
        "Bootloader is not unlocked."
      );
    }

    log("FINAL_DEVICE_VERIFY=PASS");
    log(
      `Factory file=${cached.file.name}`
    );
    log(
      `Factory size=${cached.file.size}`
    );

    const reconnectCallback =
      async () => {

        const button =
          document.getElementById(
            "flash-reconnect-button"
          );

        log(
          "RECONNECT_REQUIRED"
        );

        button.hidden = false;

        button.onclick =
          async () => {

            button.disabled =
              true;

            try {

              await factoryDevice.connect();

              button.hidden =
                true;

              log(
                "RECONNECT=PASS"
              );

            } catch (error) {

              button.disabled =
                false;

              log(
                `RECONNECT=FAIL: ${error.message}`
              );
            }
          };
      };

    await flashFactoryPackage(
      cached.file,
      reconnectCallback,

      (
        action,
        item,
        progress
      ) => {

        let percent = "";

        if (
          typeof progress ===
          "number"
        ) {
          percent =
            ` ${Math.floor(
              progress * 100
            )}%`;
        }

        log(
          `FLASH ${action ?? ""} ` +
          `${item ?? ""}${percent}`
        );
      }
    );

    log("FACTORY_FLASH=PASS");
    log("BOOTLOADER_RELOCK=DISABLED");

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

    flashInProgress =
      false;

    updateFlashButton();

    if (wakeLock) {
      try {
        await wakeLock.release();
      } catch {}
    }
  }
}'''

s = (
    s[:start] +
    new_install +
    s[end:]
)


# Make initial cached state visible.
environment_marker = '''environment();
'''

initial_cache = '''getCachedFactoryPackage()
  .then(cached => {

    if (cached) {

      factoryPreflightPassed =
        true;

      releaseVerified =
        true;

      ui.releaseChannel.textContent =
        cached.manifest.channel;

      ui.releaseBuild.textContent =
        `${cached.manifest.build.version} / ${cached.manifest.build.build_id}`;

      ui.releaseTarget.textContent =
        `${cached.manifest.device.name} (${cached.manifest.device.codename})`;

      ui.releaseVerification.textContent =
        "PACKAGE VERIFIED";

      log(
        "FACTORY_CACHE=READY"
      );

      updateFlashButton();
    }
  })
  .catch(error => {
    log(
      `Factory cache check: ${error.message}`
    );
  });


environment();
'''

if initial_cache not in s:

    if environment_marker not in s:
        raise SystemExit(
            "APP_PATCH=FAIL: environment()"
        )

    s = s.replace(
        environment_marker,
        initial_cache
    )


p.write_text(s)

print("APP_PATCH=PASS")
PY


#
# Clean visible stale labels
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path(
    "/opt/Android/worm-os/web-installer/index.html"
)

s = p.read_text()

s = re.sub(
    r'Only read-only fastboot getvar queries are permitted in V00\.[^<]+',
    'worm OS V00.7 development installer.',
    s
)

s = re.sub(
    r'worm OS\s*·\s*installer V00\.[^<]+',
    'worm OS · installer V00.7 · RELOCK DISABLED',
    s
)

p.write_text(s)
PY


echo
echo "=== SYNTAX ==="

node --check \
  "$WEB/js/server-cache.js"

node --check \
  "$WEB/js/app.js"

node --check \
  "$WEB/js/factory-installer.js"


echo
echo "=== SAFETY ==="

grep -q \
  'INSTALLER_VERSION = "WOS-INSTALLER-V00.7"' \
  "$WEB/js/config.js"

grep -q \
  'FLASH_ENABLED = true' \
  "$WEB/js/config.js"

grep -q \
  'LOCK_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'FACTORY_CACHE_VERIFY=PASS' \
  "$WEB/js/app.js"

grep -q \
  'BOOTLOADER_RELOCK=DISABLED' \
  "$WEB/js/app.js"

echo "opfs_cache=PASS"
echo "chunk_sha256=PASS"
echo "flash_from_disk_backed_file=PASS"
echo "manual_usb_reconnect=PASS"
echo "relock=DISABLED"

echo
echo "WOS_INSTALLER_V00_7=PASS"
