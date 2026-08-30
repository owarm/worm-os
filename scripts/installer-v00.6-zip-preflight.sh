#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

echo "=== WOS-INSTALLER-V00.6 / ZIP PREFLIGHT ==="

test -f "$WEB/index.html"
test -f "$WEB/js/app.js"
test -f "$WEB/js/factory-installer.js"

#
# UI button
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

needle = '''      <button
        id="flash-button"
'''

insert = '''      <button
        id="factory-preflight-button"
        class="primary"
        disabled
      >
        Test factory package
      </button>

'''

if 'id="factory-preflight-button"' not in s:
    if needle not in s:
        raise SystemExit("HTML_PATCH=FAIL: flash button marker")

    s = s.replace(needle, insert + needle)

s = s.replace(
    "WOS-INSTALLER-V00.5",
    "WOS-INSTALLER-V00.6"
)

p.write_text(s)

print("HTML_PATCH=PASS")
PY


#
# Expose ZIP preflight from factory-installer
#

cat >> "$WEB/js/factory-installer.js" <<'EOF'


export async function preflightFactoryPackage(
  blob,
  progressCallback = () => {}
) {

  if (!(blob instanceof Blob)) {
    throw new Error(
      "Factory package is not a Blob/File."
    );
  }

  progressCallback(
    "package",
    0,
    blob.size
  );

  /*
   * Read the whole File through the browser filesystem/blob
   * implementation first. This is intentionally read-only.
   *
   * It detects the class of failure we saw before any
   * fastboot write is attempted.
   */

  const reader = blob.stream().getReader();

  let total = 0;
  let lastReport = 0;

  while (true) {

    const {
      done,
      value,
    } = await reader.read();

    if (done) {
      break;
    }

    total += value.byteLength;

    const now = performance.now();

    if (
      now - lastReport >= 500 ||
      total === blob.size
    ) {
      progressCallback(
        "package",
        total,
        blob.size
      );

      lastReport = now;
    }
  }

  if (total !== blob.size) {
    throw new Error(
      `Factory package read mismatch: ${total} != ${blob.size}`
    );
  }

  return {
    size: total,
    readable: true,
  };
}
EOF


#
# Patch app.js
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/js/app.js")
s = p.read_text()

# Import preflight.
old = '''import {
  factoryDevice,
  flashFactoryPackage,
} from "./factory-installer.js";
'''

new = '''import {
  factoryDevice,
  flashFactoryPackage,
  preflightFactoryPackage,
} from "./factory-installer.js";
'''

if old not in s:
    raise SystemExit("APP_PATCH=FAIL: factory import missing")

s = s.replace(old, new)

# UI reference.
needle = '''  factoryFile:
    $("factory-file"),
'''

replacement = '''  factoryFile:
    $("factory-file"),

  factoryPreflightButton:
    $("factory-preflight-button"),
'''

if 'factoryPreflightButton:' not in s:
    if needle not in s:
        raise SystemExit("APP_PATCH=FAIL: factoryFile marker")

    s = s.replace(needle, replacement)

# State.
needle = '''let flashInProgress = false;
'''

replacement = '''let flashInProgress = false;
let factoryPreflightPassed = false;
'''

if 'factoryPreflightPassed' not in s:
    if needle not in s:
        raise SystemExit("APP_PATCH=FAIL: flash state marker")

    s = s.replace(needle, replacement)

# Require preflight for flash.
needle = '''    bootloaderUnlocked === true &&
    flashInProgress === false;
'''

replacement = '''    bootloaderUnlocked === true &&
    factoryPreflightPassed === true &&
    flashInProgress === false;
'''

if needle not in s:
    raise SystemExit("APP_PATCH=FAIL: flash ready condition")

s = s.replace(needle, replacement, 1)

# Add preflight function.
marker = '''
async function installWormOS() {
'''

code = r'''
function updateFactoryPreflightButton() {

  const file =
    ui.factoryFile?.files?.[0];

  ui.factoryPreflightButton.disabled =
    !file;
}


async function runFactoryPreflight() {

  const file =
    ui.factoryFile?.files?.[0];

  if (!file) {
    throw new Error(
      "Select the factory ZIP first."
    );
  }

  factoryPreflightPassed = false;

  updateFlashButton();

  ui.factoryPreflightButton.disabled = true;

  log(
    `FACTORY_PREFLIGHT_START ${file.name}`
  );

  log(
    `Factory size: ${file.size} bytes`
  );

  const started =
    performance.now();

  try {

    const result =
      await preflightFactoryPackage(
        file,
        (stage, done, total) => {

          const pct =
            total > 0
              ? Math.floor(
                  done * 100 / total
                )
              : 0;

          log(
            `PREFLIGHT ${stage} ${pct}%`
          );
        }
      );

    const seconds =
      (
        (performance.now() - started)
        / 1000
      ).toFixed(1);

    log(
      `Factory readable: ${result.size} bytes`
    );

    log(
      `Factory read time: ${seconds}s`
    );

    factoryPreflightPassed = true;

    log(
      "FACTORY_PREFLIGHT=PASS"
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    log(
      `FACTORY_PREFLIGHT=FAIL: ${message}`
    );

  } finally {

    updateFactoryPreflightButton();
    updateFlashButton();
  }
}


'''

if code not in s:
    if marker not in s:
        raise SystemExit("APP_PATCH=FAIL: install marker")

    s = s.replace(
        marker,
        code + marker
    )

# Reset PASS whenever file changes.
listener_marker = '''
ui.flashButton
  .addEventListener(
'''

listeners = '''
ui.factoryFile
  .addEventListener(
    "change",
    () => {
      factoryPreflightPassed = false;
      updateFactoryPreflightButton();
      updateFlashButton();
    }
  );


ui.factoryPreflightButton
  .addEventListener(
    "click",
    runFactoryPreflight
  );


'''

if listeners not in s:
    if listener_marker not in s:
        raise SystemExit("APP_PATCH=FAIL: listener marker")

    s = s.replace(
        listener_marker,
        listeners + listener_marker
    )

p.write_text(s)

print("APP_PATCH=PASS")
PY


#
# Syntax
#

echo
echo "=== VERIFY ==="

node --check "$WEB/js/app.js"
node --check "$WEB/js/factory-installer.js"

grep -q \
  'factoryPreflightPassed === true' \
  "$WEB/js/app.js"

grep -q \
  'FACTORY_PREFLIGHT=PASS' \
  "$WEB/js/app.js"

echo "flash_requires_preflight=PASS"
echo "fastboot_write_test=NONE"
echo "phone_write=NONE"

echo
echo "WOS_INSTALLER_V00_6=PASS"
