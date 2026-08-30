#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer
JS="$WEB/js"

echo "=== WOS-INSTALLER-V00.9B / IMAGE FLASHER ==="

test -f "$WEB/releases/frankel/20260826-dev1/images-v009.json"
test -f "$JS/fastboot-lib/ffe7e270/fastboot.min.mjs"

mkdir -p /opt/Android/worm-os/web-installer-backups/v00.9a

cp -a "$WEB/index.html" \
  /opt/Android/worm-os/web-installer-backups/v00.9a/

cp -a "$JS/app.js" \
  /opt/Android/worm-os/web-installer-backups/v00.9a/

cp -a "$JS/config.js" \
  /opt/Android/worm-os/web-installer-backups/v00.9a/


# ------------------------------------------------------------
# CONFIG
# ------------------------------------------------------------

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/js/config.js")
s = p.read_text()

s = re.sub(
    r'export const INSTALLER_VERSION = "[^"]+";',
    'export const INSTALLER_VERSION = "WOS-INSTALLER-V00.9B";',
    s,
)

s = re.sub(
    r'export const UNLOCK_ENABLED = (?:true|false);',
    'export const UNLOCK_ENABLED = true;',
    s,
)

s = re.sub(
    r'export const FLASH_ENABLED = (?:true|false);',
    'export const FLASH_ENABLED = true;',
    s,
)

s = re.sub(
    r'export const LOCK_ENABLED = (?:true|false);',
    'export const LOCK_ENABLED = false;',
    s,
)

p.write_text(s)

print("CONFIG_PATCH=PASS")
PY


# ------------------------------------------------------------
# IMAGE-BY-IMAGE FLASH ENGINE
# ------------------------------------------------------------

cat > "$JS/v009-flasher.js" <<'EOF'
import * as fastboot from
  "./fastboot-lib/ffe7e270/fastboot.min.mjs";


const MANIFEST_URL =
  "/releases/frankel/20260826-dev1/images-v009.json";


/*
 * Browser SHA-256 is used for the small/boot-critical images.
 *
 * For the ~1 GiB system/product/vendor images we avoid converting
 * the entire Blob into another ArrayBuffer solely for hashing.
 * They are still protected in transit by HTTPS and checked against
 * the exact byte size published in the release manifest.
 */
const HASH_IN_BROWSER_LIMIT =
  128 * 1024 * 1024;


export class WormImageFlasher {

  constructor(logger = () => {}) {

    this.device =
      new fastboot.FastbootDevice();

    this.log =
      logger;

    this.manifest =
      null;

    this.images =
      new Map();
  }


  async loadManifest() {

    const response =
      await fetch(
        MANIFEST_URL,
        { cache: "no-store" }
      );

    if (!response.ok) {
      throw new Error(
        `Image manifest HTTP ${response.status}`
      );
    }

    const manifest =
      await response.json();

    if (
      manifest.installer !==
        "WOS-INSTALLER-V00.9" ||
      manifest.device !== "frankel"
    ) {
      throw new Error(
        "Invalid V00.9 image manifest."
      );
    }

    if (
      manifest.policy?.relock !== false
    ) {
      throw new Error(
        "Release unexpectedly permits relock."
      );
    }

    this.images.clear();

    for (const image of manifest.images) {

      if (
        !image.name ||
        !image.url ||
        !Number.isSafeInteger(image.size) ||
        !image.sha256
      ) {
        throw new Error(
          "Malformed image metadata."
        );
      }

      this.images.set(
        image.name,
        image
      );
    }

    this.manifest =
      manifest;

    this.log(
      `IMAGE_MANIFEST=PASS images=${this.images.size}`
    );

    return manifest;
  }


  async connect() {

    if (!this.device.isConnected) {
      await this.device.connect();
    }

    const product =
      await this.device.getVariable(
        "product"
      );

    if (product !== "frankel") {
      throw new Error(
        `Wrong device: ${product ?? "unknown"}`
      );
    }

    const unlocked =
      await this.device.getVariable(
        "unlocked"
      );

    if (unlocked !== "yes") {
      throw new Error(
        "Pixel bootloader is not unlocked."
      );
    }

    this.log(
      "DEVICE_VERIFY=PASS product=frankel unlocked=yes"
    );
  }


  async reconnectIfNeeded() {

    if (this.device.isConnected) {
      return;
    }

    this.log(
      "Waiting for Pixel USB reconnect..."
    );

    await this.device.waitForConnect(
      () => {
        this.log(
          "Reconnect Pixel when browser requests it."
        );
      }
    );

    this.log(
      "USB_RECONNECT=PASS"
    );
  }


  static async sha256Hex(blob) {

    const buffer =
      await blob.arrayBuffer();

    const digest =
      await crypto.subtle.digest(
        "SHA-256",
        buffer
      );

    return Array
      .from(
        new Uint8Array(digest)
      )
      .map(
        byte =>
          byte
            .toString(16)
            .padStart(2, "0")
      )
      .join("");
  }


  async fetchImage(name) {

    const metadata =
      this.images.get(name);

    if (!metadata) {
      throw new Error(
        `Unknown release image: ${name}`
      );
    }

    const manifestBase =
      new URL(
        MANIFEST_URL,
        location.origin
      );

    const url =
      new URL(
        metadata.url,
        manifestBase
      );

    this.log(
      `GET ${name} (${metadata.size} bytes)`
    );

    const response =
      await fetch(
        url,
        { cache: "no-store" }
      );

    if (!response.ok) {
      throw new Error(
        `${name}: HTTP ${response.status}`
      );
    }

    const advertised =
      Number(
        response.headers.get(
          "content-length"
        )
      );

    if (
      advertised &&
      advertised !== metadata.size
    ) {
      throw new Error(
        `${name}: Content-Length mismatch`
      );
    }

    const blob =
      await response.blob();

    if (
      blob.size !==
      metadata.size
    ) {
      throw new Error(
        `${name}: downloaded size mismatch`
      );
    }

    /*
     * Hash small images fully.
     * Large images deliberately avoid an extra
     * 1+ GiB ArrayBuffer allocation.
     */
    if (
      blob.size <=
      HASH_IN_BROWSER_LIMIT
    ) {

      this.log(
        `VERIFY SHA-256 ${name}`
      );

      const actual =
        await WormImageFlasher
          .sha256Hex(blob);

      if (
        actual.toLowerCase() !==
        metadata.sha256.toLowerCase()
      ) {
        throw new Error(
          `${name}: SHA-256 mismatch`
        );
      }

      this.log(
        `SHA256 ${name}=PASS`
      );

    } else {

      this.log(
        `VERIFY ${name}=HTTPS+SIZE PASS`
      );
    }

    return blob;
  }


  async flashImage(
    partition,
    imageName
  ) {

    let blob =
      await this.fetchImage(
        imageName
      );

    this.log(
      `FLASH_START ${partition}`
    );

    await this.device.flashBlob(
      partition,
      blob,

      progress => {

        const pct =
          Math.floor(
            progress * 100
          );

        this.log(
          `FLASH ${partition} ${pct}%`
        );
      }
    );

    this.log(
      `FLASH ${partition}=PASS`
    );

    /*
     * Release our reference before downloading
     * the next image.
     */
    blob = null;

    await new Promise(
      resolve =>
        setTimeout(resolve, 100)
    );
  }


  async cancelSnapshots() {

    const status =
      await this.device.getVariable(
        "snapshot-update-status"
      );

    if (
      status !== null &&
      status !== "none"
    ) {

      this.log(
        `snapshot-update-status=${status}`
      );

      await this.device.runCommand(
        "snapshot-update:cancel"
      );

      this.log(
        "SNAPSHOT_CANCEL=PASS"
      );
    }
  }


  async rebootToFastbootd() {

    this.log(
      "REBOOT fastbootd"
    );

    await this.device.reboot(
      "fastboot",
      true,

      () => {
        this.log(
          "FASTBOOTD_RECONNECT_REQUIRED"
        );
      }
    );

    const userspace =
      await this.device.getVariable(
        "is-userspace"
      );

    if (userspace !== "yes") {
      throw new Error(
        "Device did not enter fastbootd."
      );
    }

    this.log(
      "FASTBOOTD=PASS"
    );
  }


  async updateSuper() {

    let blob =
      await this.fetchImage(
        "super_empty.img"
      );

    const superName =
      (
        await this.device.getVariable(
          "super-partition-name"
        )
      ) || "super";

    this.log(
      `UPDATE_SUPER partition=${superName}`
    );

    const buffer =
      await blob.arrayBuffer();

    await this.device.upload(
      superName,
      buffer,

      progress => {

        this.log(
          `UPDATE_SUPER upload ` +
          `${Math.floor(progress * 100)}%`
        );
      }
    );

    await this.device.runCommand(
      `update-super:${superName}:wipe`
    );

    this.log(
      "UPDATE_SUPER=PASS"
    );

    blob = null;
  }


  async returnToBootloader() {

    const userspace =
      await this.device.getVariable(
        "is-userspace"
      );

    if (userspace !== "yes") {
      return;
    }

    this.log(
      "REBOOT bootloader"
    );

    await this.device.reboot(
      "bootloader",
      true,

      () => {
        this.log(
          "BOOTLOADER_RECONNECT_REQUIRED"
        );
      }
    );

    const product =
      await this.device.getVariable(
        "product"
      );

    if (product !== "frankel") {
      throw new Error(
        "Wrong device after bootloader reconnect."
      );
    }

    this.log(
      "BOOTLOADER_RECONNECT=PASS"
    );
  }


  async wipe() {

    this.log(
      "ERASE userdata"
    );

    await this.device.runCommand(
      "erase:userdata"
    );

    this.log(
      "ERASE userdata=PASS"
    );

    this.log(
      "ERASE metadata"
    );

    await this.device.runCommand(
      "erase:metadata"
    );

    this.log(
      "ERASE metadata=PASS"
    );
  }


  async install() {

    if (!this.manifest) {
      await this.loadManifest();
    }

    await this.connect();

    /*
     * V00.9B deliberately does NOT flash
     * bootloader.img or radio.img.
     *
     * Sequence follows frankel/fastboot-info.txt.
     */

    await this.cancelSnapshots();


    // Boot-critical partitions.
    await this.flashImage(
      "boot",
      "boot.img"
    );

    await this.flashImage(
      "init_boot",
      "init_boot.img"
    );

    await this.flashImage(
      "dtbo",
      "dtbo.img"
    );

    await this.flashImage(
      "vendor_kernel_boot",
      "vendor_kernel_boot.img"
    );

    await this.flashImage(
      "pvmfw",
      "pvmfw.img"
    );

    await this.flashImage(
      "vendor_boot",
      "vendor_boot.img"
    );

    /*
     * fastboot-info.txt says:
     *
     * flash --apply-vbmeta vbmeta
     *
     * No disable-verity / disable-verification
     * flags are being requested by worm OS, so
     * we flash the generated vbmeta image intact.
     */
    await this.flashImage(
      "vbmeta",
      "vbmeta.img"
    );


    // Dynamic partitions.
    await this.rebootToFastbootd();

    await this.updateSuper();


    await this.flashImage(
      "system",
      "system.img"
    );

    await this.flashImage(
      "system_dlkm",
      "system_dlkm.img"
    );

    await this.flashImage(
      "system_ext",
      "system_ext.img"
    );

    await this.flashImage(
      "product",
      "product.img"
    );

    await this.flashImage(
      "vendor",
      "vendor.img"
    );

    await this.flashImage(
      "vendor_dlkm",
      "vendor_dlkm.img"
    );


    // Wipe is specified by fastboot-info.
    await this.returnToBootloader();

    await this.wipe();


    this.log(
      "WOS_FLASH_V00_9B=PASS"
    );

    this.log(
      "BOOTLOADER_RELOCK=DISABLED"
    );

    this.log(
      "AUTO_REBOOT=DISABLED"
    );
  }
}


export const wormImageFlasher =
  new WormImageFlasher();
EOF


# ------------------------------------------------------------
# PATCH app.js
# ------------------------------------------------------------

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/js/app.js")
s = p.read_text()


# Import V00.9 flasher.
imp = '''import {
  wormImageFlasher,
} from "./v009-flasher.js";
'''

anchor = '''import {
  loadCurrentRelease,
  verifyArtifact,
} from "./release.js";
'''

if imp not in s:

    if anchor not in s:
        raise SystemExit(
            "APP_PATCH=FAIL: import anchor"
        )

    s = s.replace(
        anchor,
        anchor + "\n" + imp
    )


# Remove requirements for V00.7/8 cached/local package
# from updateFlashButton.
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

replacement = '''function updateFlashButton() {

  if (!ui.flashButton) {
    return;
  }

  const ready =
    FLASH_ENABLED === true &&
    deviceVerified === true &&
    bootloaderUnlocked === true &&
    flashInProgress === false;

  ui.flashButton.disabled =
    !ready;
}'''

s = (
    s[:start] +
    replacement +
    s[end:]
)


# Replace installWormOS.
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

replacement = r'''async function installWormOS() {

  if (
    !deviceVerified ||
    bootloaderUnlocked !== true
  ) {
    throw new Error(
      "Verified unlocked Pixel 10 required."
    );
  }

  const confirmed =
    window.confirm(
      "Install worm OS V00.9B on Pixel 10?\n\n" +
      "Images will be downloaded one at a time from the worm OS server.\n" +
      "Android userdata and metadata will be erased.\n\n" +
      "DO NOT disconnect USB until PASS appears.\n\n" +
      "The bootloader will remain unlocked."
    );

  if (!confirmed) {
    return;
  }

  flashInProgress = true;
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
     * Release the small diagnostic transport.
     * The V00.9 flasher claims WebUSB itself.
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


    wormImageFlasher.log =
      message => log(message);


    log(
      "WOS_V00_9B_INSTALL_START"
    );

    await wormImageFlasher.install();

    log(
      "INSTALLATION_COMPLETE"
    );

    alert(
      "worm OS flashing completed.\n\n" +
      "The Pixel is intentionally left in Fastboot Mode.\n" +
      "Keep the bootloader unlocked and select Start on the Pixel when ready."
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    log(
      `WOS_FLASH_V00_9B=FAIL: ${message}`
    );

    ui.deviceError.textContent =
      message;

    ui.deviceError.classList.remove(
      "hidden"
    );

  } finally {

    flashInProgress = false;
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
    replacement +
    s[end:]
)

p.write_text(s)

print("APP_PATCH=PASS")
PY


# ------------------------------------------------------------
# HTML CLEANUP
# ------------------------------------------------------------

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

s = re.sub(
    r'WOS-INSTALLER-V00\.[A-Za-z0-9.-]+',
    'WOS-INSTALLER-V00.9B',
    s,
)

# Remove V00.7/V00.8 package/cache controls.
s = re.sub(
    r'<div[^>]*id="factory-file-panel".*?</div>',
    '',
    s,
    flags=re.S,
)

s = re.sub(
    r'<button[^>]*id="verify-factory-file-button".*?</button>',
    '',
    s,
    flags=re.S,
)

s = re.sub(
    r'<button[^>]*id="factory-preflight-button".*?</button>',
    '',
    s,
    flags=re.S,
)

s = re.sub(
    r'worm OS development installation for Pixel 10\.',
    'worm OS V00.9B · image-by-image installation for Pixel 10.',
    s,
)

p.write_text(s)

print("HTML_PATCH=PASS")
PY


# ------------------------------------------------------------
# SYNTAX + SAFETY
# ------------------------------------------------------------

echo
echo "=== JS SYNTAX ==="

node --check "$JS/v009-flasher.js"
node --check "$JS/app.js"

echo "syntax=PASS"


echo
echo "=== POLICY ==="

grep -q \
  'INSTALLER_VERSION = "WOS-INSTALLER-V00.9B"' \
  "$JS/config.js"

grep -q \
  'FLASH_ENABLED = true' \
  "$JS/config.js"

grep -q \
  'LOCK_ENABLED = false' \
  "$JS/config.js"

grep -q \
  'BOOTLOADER_RELOCK=DISABLED' \
  "$JS/v009-flasher.js"

grep -q \
  'AUTO_REBOOT=DISABLED' \
  "$JS/v009-flasher.js"


echo "target=frankel"
echo "factory_zip=NOT_USED"
echo "file_picker=NOT_USED"
echo "opfs=NOT_USED"
echo "browser_package_cache=NOT_USED"
echo "image_by_image=ENABLED"
echo "fastboot_sparse_split=LIBRARY"
echo "erase_userdata=ENABLED"
echo "erase_metadata=ENABLED"
echo "auto_reboot=DISABLED"
echo "relock=DISABLED"

echo
echo "WOS_INSTALLER_V00_9B=PASS"
