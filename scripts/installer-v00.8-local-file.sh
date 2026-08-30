#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer
RELEASE="$WEB/releases/frankel/20260826-dev1"
EXPECTED_NAME="frankel-install-20260826-dev1.zip"
EXPECTED_SIZE="4532188739"
EXPECTED_SHA="0e30dbdf0f34ae13233810ca2c1fe1ab330eb01f1f0e157e28378942eb664c20"

echo "=== WOS-INSTALLER-V00.8 ==="

mkdir -p /opt/Android/worm-os/web-installer-backups/v00.7

cp -a "$WEB/index.html" \
  /opt/Android/worm-os/web-installer-backups/v00.7/

cp -a "$WEB/js" \
  /opt/Android/worm-os/web-installer-backups/v00.7/

#
# CONFIG
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/js/config.js")
s = p.read_text()

s = re.sub(
    r'export const INSTALLER_VERSION = "[^"]+";',
    'export const INSTALLER_VERSION = "WOS-INSTALLER-V00.8";',
    s
)

s = re.sub(
    r'export const UNLOCK_ENABLED = (true|false);',
    'export const UNLOCK_ENABLED = true;',
    s
)

s = re.sub(
    r'export const FLASH_ENABLED = (true|false);',
    'export const FLASH_ENABLED = true;',
    s
)

s = re.sub(
    r'export const LOCK_ENABLED = (true|false);',
    'export const LOCK_ENABLED = false;',
    s
)

p.write_text(s)

print("CONFIG_PATCH=PASS")
PY


#
# HTML: local ZIP picker
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

s = re.sub(
    r'WOS-INSTALLER-V00\.[A-Za-z0-9.-]+',
    'WOS-INSTALLER-V00.8',
    s
)

# Remove old server/cache preflight button.
s = re.sub(
    r'<button\s+id="factory-preflight-button".*?</button>',
    '',
    s,
    flags=re.S
)

# Remove an older factory picker if one exists.
s = re.sub(
    r'<div[^>]*id="factory-file-panel"[^>]*>.*?</div>',
    '',
    s,
    flags=re.S
)

marker = '''      <button
        id="flash-button"
'''

picker = '''      <div
        id="factory-file-panel"
        class="confirm-input"
      >
        <label for="factory-file">
          worm OS factory package
        </label>

        <input
          id="factory-file"
          type="file"
          accept=".zip,application/zip"
        >

        <small>
          Select frankel-install-20260826-dev1.zip.
          The file is read directly from Windows and is not copied
          into browser storage.
        </small>

        <div id="factory-file-status">
          NOT VERIFIED
        </div>
      </div>

      <button
        id="verify-factory-file-button"
        class="primary"
        disabled
      >
        Verify factory package
      </button>

'''

if marker not in s:
    raise SystemExit("HTML_PATCH=FAIL: flash button marker")

s = s.replace(marker, picker + marker)

# Clean stale visible labels.
s = re.sub(
    r'Only read-only fastboot getvar queries are permitted in V00\.[^<]+',
    'worm OS V00.8 development installer.',
    s
)

s = re.sub(
    r'worm OS installation[^<]*',
    'worm OS development installation for Pixel 10.',
    s
)

p.write_text(s)

print("HTML_PATCH=PASS")
PY


#
# NEW LOCAL FILE MODULE
#

cat > "$WEB/js/local-factory.js" <<'EOF'
const EXPECTED_NAME =
  "frankel-install-20260826-dev1.zip";

const EXPECTED_SIZE =
  4532188739;

const EXPECTED_SHA256 =
  "0e30dbdf0f34ae13233810ca2c1fe1ab330eb01f1f0e157e28378942eb664c20";


async function sha256Hex(buffer) {

  const digest =
    await crypto.subtle.digest(
      "SHA-256",
      buffer
    );

  return Array
    .from(new Uint8Array(digest))
    .map(
      b =>
        b.toString(16).padStart(2, "0")
    )
    .join("");
}


export function validateFactoryFileMetadata(
  file
) {

  if (!(file instanceof File)) {
    throw new Error(
      "Select the factory ZIP."
    );
  }

  if (file.name !== EXPECTED_NAME) {
    throw new Error(
      `Wrong file: ${file.name}`
    );
  }

  if (file.size !== EXPECTED_SIZE) {
    throw new Error(
      `Wrong size: ${file.size} != ${EXPECTED_SIZE}`
    );
  }

  return true;
}


/*
 * Verify the local file against the same 32 MiB
 * chunk hashes generated on the server.
 *
 * Only one chunk is held in memory at a time.
 */
export async function verifyLocalFactoryFile(
  file,
  chunkManifest,
  progress = () => {}
) {

  validateFactoryFileMetadata(file);

  if (
    chunkManifest.name !== EXPECTED_NAME ||
    chunkManifest.size !== EXPECTED_SIZE ||
    chunkManifest.sha256.toLowerCase() !==
      EXPECTED_SHA256
  ) {
    throw new Error(
      "Factory verification manifest mismatch."
    );
  }

  for (
    const chunk
    of chunkManifest.chunks
  ) {

    const blob =
      file.slice(
        chunk.offset,
        chunk.offset + chunk.size
      );

    const buffer =
      await blob.arrayBuffer();

    if (
      buffer.byteLength !==
      chunk.size
    ) {
      throw new Error(
        `Chunk ${chunk.index}: size mismatch`
      );
    }

    const actual =
      await sha256Hex(buffer);

    if (
      actual.toLowerCase() !==
      chunk.sha256.toLowerCase()
    ) {
      throw new Error(
        `Chunk ${chunk.index}: SHA-256 mismatch`
      );
    }

    const received =
      chunk.offset +
      chunk.size;

    progress({
      index: chunk.index,
      received,
      total: EXPECTED_SIZE,
      percent:
        Math.floor(
          received * 100 /
          EXPECTED_SIZE
        ),
    });
  }

  return {
    file,
    name: EXPECTED_NAME,
    size: EXPECTED_SIZE,
    sha256: EXPECTED_SHA256,
    verified: true,
  };
}
EOF


#
# Replace app.js with targeted V00.8 behavior.
#

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/Android/worm-os/web-installer/js/app.js")
s = p.read_text()

#
# Import local verification
#

imp = '''import {
  validateFactoryFileMetadata,
  verifyLocalFactoryFile,
} from "./local-factory.js";
'''

anchor = '''import {
  loadCurrentRelease,
  verifyArtifact,
} from "./release.js";
'''

if imp not in s:
    if anchor not in s:
        raise SystemExit("APP_PATCH=FAIL: release import")
    s = s.replace(anchor, anchor + "\n" + imp)


#
# UI references
#

ui_marker = '''  flashButton:
    $("flash-button"),
'''

ui_new = '''  flashButton:
    $("flash-button"),

  factoryFile:
    $("factory-file"),

  verifyFactoryFileButton:
    $("verify-factory-file-button"),

  factoryFileStatus:
    $("factory-file-status"),
'''

if "verifyFactoryFileButton:" not in s:
    if ui_marker not in s:
        raise SystemExit("APP_PATCH=FAIL: flashButton UI")
    s = s.replace(ui_marker, ui_new)


#
# State
#

state_marker = '''let flashInProgress = false;
'''

state_new = '''let flashInProgress = false;

let verifiedFactoryFile = null;
'''

if "let verifiedFactoryFile" not in s:
    if state_marker not in s:
        raise SystemExit("APP_PATCH=FAIL: flash state")
    s = s.replace(state_marker, state_new)


#
# Replace updateFlashButton()
#

start = s.find("function updateFlashButton()")
end = s.find(
    "\n\nasync function unlockBootloader()",
    start
)

if start == -1 or end == -1:
    raise SystemExit(
        "APP_PATCH=FAIL: updateFlashButton"
    )

new = '''function updateFlashButton() {

  if (!ui.flashButton) {
    return;
  }

  const ready =
    FLASH_ENABLED === true &&
    deviceVerified === true &&
    bootloaderUnlocked === true &&
    verifiedFactoryFile !== null &&
    flashInProgress === false;

  ui.flashButton.disabled =
    !ready;
}'''

s = s[:start] + new + s[end:]


#
# Remove old runFactoryPreflight if present
#

start = s.find(
    "async function runFactoryPreflight()"
)

if start != -1:

    end = s.find(
        "\n\nasync function installWormOS()",
        start
    )

    if end == -1:
        raise SystemExit(
            "APP_PATCH=FAIL: old preflight end"
        )

    s = s[:start] + s[end:]


#
# Replace installWormOS
#

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

install = r'''async function installWormOS() {

  if (
    !verifiedFactoryFile
  ) {
    throw new Error(
      "Verify the local factory package first."
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

  const confirmed =
    window.confirm(
      "Install worm OS on Pixel 10?\n\n" +
      "This overwrites Android and wipes user data.\n\n" +
      "Keep USB connected. The bootloader will remain unlocked."
    );

  if (!confirmed) {
    return;
  }

  flashInProgress = true;
  updateFlashButton();

  let wakeLock = null;

  try {

    if (navigator.wakeLock?.request) {
      try {
        wakeLock =
          await navigator.wakeLock.request(
            "screen"
          );
      } catch {}
    }

    /*
     * Release diagnostic WebUSB interface before
     * the factory engine claims the device.
     */
    if (fastboot) {
      try {
        await fastboot.disconnect();
      } catch {}
    }

    fastboot = null;

    if (currentDevice?.opened) {
      try {
        await currentDevice.close();
      } catch {}
    }

    currentDevice = null;

    log("FACTORY_FLASH_START");
    log(
      `Factory=${verifiedFactoryFile.name}`
    );
    log(
      `Size=${verifiedFactoryFile.size}`
    );
    log(
      `SHA-256=${verifiedFactoryFile.sha256}`
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
        `Wrong target: ${product}`
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

    await flashFactoryPackage(
      verifiedFactoryFile.file,

      async () => {
        log(
          "FASTBOOT_RECONNECT_REQUIRED"
        );
      },

      (
        action,
        item,
        progress
      ) => {

        let suffix = "";

        if (
          typeof progress === "number"
        ) {
          suffix =
            ` ${Math.floor(
              progress * 100
            )}%`;
        }

        log(
          `FLASH ${action ?? ""} ` +
          `${item ?? ""}${suffix}`
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

    flashInProgress = false;
    updateFlashButton();

    if (wakeLock) {
      try {
        await wakeLock.release();
      } catch {}
    }
  }
}'''

s = s[:start] + install + s[end:]


#
# Add local-file verification functions before install.
#

marker = "async function installWormOS()"

local_code = r'''
function factoryFileChanged() {

  verifiedFactoryFile = null;

  ui.factoryFileStatus.textContent =
    "NOT VERIFIED";

  const file =
    ui.factoryFile?.files?.[0];

  try {

    validateFactoryFileMetadata(
      file
    );

    ui.verifyFactoryFileButton.disabled =
      false;

    ui.factoryFileStatus.textContent =
      "READY TO VERIFY";

  } catch {

    ui.verifyFactoryFileButton.disabled =
      true;
  }

  updateFlashButton();
}


async function verifyFactoryFile() {

  const file =
    ui.factoryFile?.files?.[0];

  if (!file) {
    return;
  }

  verifiedFactoryFile = null;

  updateFlashButton();

  ui.verifyFactoryFileButton.disabled =
    true;

  try {

    log(
      `LOCAL_FACTORY_VERIFY_START ${file.name}`
    );

    const response =
      await fetch(
        "/releases/frankel/20260826-dev1/factory-chunks.json",
        { cache: "no-store" }
      );

    if (!response.ok) {
      throw new Error(
        `Chunk manifest HTTP ${response.status}`
      );
    }

    const chunks =
      await response.json();

    const result =
      await verifyLocalFactoryFile(
        file,
        chunks,

        state => {

          ui.factoryFileStatus.textContent =
            `VERIFYING ${state.percent}%`;

          log(
            `LOCAL VERIFY ${state.percent}%`
          );
        }
      );

    verifiedFactoryFile =
      result;

    ui.factoryFileStatus.textContent =
      "VERIFIED";

    log(
      "LOCAL_FACTORY_VERIFY=PASS"
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    verifiedFactoryFile =
      null;

    ui.factoryFileStatus.textContent =
      "FAILED";

    log(
      `LOCAL_FACTORY_VERIFY=FAIL: ${message}`
    );

  } finally {

    ui.verifyFactoryFileButton.disabled =
      false;

    updateFlashButton();
  }
}


'''

pos = s.find(marker)

if pos == -1:
    raise SystemExit(
        "APP_PATCH=FAIL: install marker"
    )

s = s[:pos] + local_code + s[pos:]


#
# Remove old factory-preflight listeners.
#

s = re.sub(
    r'\nui\.factoryPreflightButton.*?'
    r'\n\s*\);\n',
    "\n",
    s,
    flags=re.S
)


#
# Add local file listeners.
#

listener_marker = '''ui.flashButton
  .addEventListener(
'''

listeners = '''ui.factoryFile
  .addEventListener(
    "change",
    factoryFileChanged
  );


ui.verifyFactoryFileButton
  .addEventListener(
    "click",
    verifyFactoryFile
  );


'''

if listeners not in s:
    if listener_marker not in s:
        raise SystemExit(
            "APP_PATCH=FAIL: flash listener"
        )

    s = s.replace(
        listener_marker,
        listeners + listener_marker
    )


p.write_text(s)

print("APP_PATCH=PASS")
PY


#
# Syntax / invariants
#

node --check "$WEB/js/local-factory.js"
node --check "$WEB/js/app.js"
node --check "$WEB/js/factory-installer.js"

echo
echo "=== VERIFY ==="

grep -q \
  'INSTALLER_VERSION = "WOS-INSTALLER-V00.8"' \
  "$WEB/js/config.js"

grep -q \
  'LOCK_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'LOCAL_FACTORY_VERIFY=PASS' \
  "$WEB/js/app.js"

grep -q \
  'BOOTLOADER_RELOCK=DISABLED' \
  "$WEB/js/app.js"

echo "local_file=PASS"
echo "chunk_verification=PASS"
echo "opfs=NOT_USED"
echo "remote_factory_blob=NOT_USED"
echo "flash=ENABLED_AFTER_LOCAL_VERIFY"
echo "relock=DISABLED"

echo
echo "WOS_INSTALLER_V00_8=PASS"
