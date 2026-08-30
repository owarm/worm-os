#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

echo "=== WOS-INSTALLER-V00.4 / UNLOCK ==="

test -f "$WEB/js/config.js"
test -f "$WEB/js/fastboot.js"
test -f "$WEB/js/app.js"
test -f "$WEB/index.html"

#
# config.js
#

cat > "$WEB/js/config.js" <<'EOF'
export const INSTALLER_VERSION = "WOS-INSTALLER-V00.4";

export const GOOGLE_VENDOR_ID = 0x18d1;
export const EXPECTED_PRODUCT = "frankel";

export const UNLOCK_ENABLED = true;
export const FLASH_ENABLED = false;
export const LOCK_ENABLED = false;

export const ALLOWED_FASTBOOT_COMMANDS = new Set([
  "getvar:product",
  "getvar:unlocked",
  "getvar:current-slot",
  "getvar:version-bootloader",
  "getvar:unlock_ability",
  "flashing unlock",
]);
EOF


#
# Patch fastboot.js
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/js/fastboot.js")
s = p.read_text()

s = s.replace(
'''import {
  ALLOWED_FASTBOOT_COMMANDS,
} from "./config.js";
''',
'''import {
  ALLOWED_FASTBOOT_COMMANDS,
  UNLOCK_ENABLED,
} from "./config.js";
'''
)

old = '''    if (
      !command.startsWith("getvar:")
    ) {
      throw new FastbootError(
        "Only fastboot getvar commands are allowed."
      );
    }
'''

new = '''    if (command.startsWith("getvar:")) {
      return;
    }

    if (
      command === "flashing unlock" &&
      UNLOCK_ENABLED === true
    ) {
      return;
    }

    throw new FastbootError(
      `Fastboot command blocked: ${command}`
    );
'''

if old not in s:
    raise SystemExit("PATCH=FAIL: assertAllowed block not found")

s = s.replace(old, new)

marker = '''  async getvar(name) {
    return this.command(
      `getvar:${name}`
    );
  }
'''

addition = '''  async getvar(name) {
    return this.command(
      `getvar:${name}`
    );
  }


  async unlockBootloader() {

    if (UNLOCK_ENABLED !== true) {
      throw new FastbootError(
        "Bootloader unlock is disabled."
      );
    }

    return this.command(
      "flashing unlock"
    );
  }
'''

if marker not in s:
    raise SystemExit("PATCH=FAIL: getvar block not found")

s = s.replace(marker, addition)

p.write_text(s)
print("FASTBOOT_PATCH=PASS")
PY


#
# Add unlock UI
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

s = s.replace(
    "WOS-INSTALLER-V00.3",
    "WOS-INSTALLER-V00.4"
)

needle = '''      <button
        id="flash-button"
        class="flash"
        disabled
      >
        Flash worm OS — disabled
      </button>
'''

replacement = '''      <div id="unlock-panel" class="unlock-panel">
        <div class="message error">
          Unlocking the bootloader erases all data on the Pixel 10.
          Flashing remains disabled in V00.4.
        </div>

        <label class="confirm-row">
          <input id="unlock-wipe-confirm" type="checkbox">
          I understand that unlocking performs a factory reset.
        </label>

        <label class="confirm-input">
          Type <strong>ERASE</strong> to enable the unlock button:
          <input
            id="unlock-confirm-text"
            type="text"
            autocomplete="off"
            spellcheck="false"
            placeholder="ERASE"
          >
        </label>

        <button
          id="unlock-button"
          class="primary"
          disabled
        >
          Unlock bootloader
        </button>
      </div>

      <button
        id="flash-button"
        class="flash"
        disabled
      >
        Flash worm OS — disabled
      </button>
'''

if needle not in s:
    raise SystemExit("PATCH=FAIL: flash button block not found")

s = s.replace(needle, replacement)

p.write_text(s)
print("HTML_PATCH=PASS")
PY


#
# CSS
#

cat >> "$WEB/css/main.css" <<'EOF'

.unlock-panel {
  display: grid;
  gap: 14px;
  margin-bottom: 18px;
}

.confirm-row {
  display: flex;
  gap: 10px;
  align-items: center;
  color: var(--text);
  font-size: 14px;
}

.confirm-input {
  display: grid;
  gap: 8px;
  color: var(--muted);
  font-size: 13px;
}

.confirm-input input {
  width: 100%;
  padding: 11px 12px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--panel-2);
  color: var(--text);
  font: inherit;
}
EOF


#
# Patch app.js
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/js/app.js")
s = p.read_text()

s = s.replace(
'''  FLASH_ENABLED,
  INSTALLER_VERSION,
  EXPECTED_PRODUCT,
} from "./config.js";
''',
'''  FLASH_ENABLED,
  UNLOCK_ENABLED,
  LOCK_ENABLED,
  INSTALLER_VERSION,
  EXPECTED_PRODUCT,
} from "./config.js";
'''
)

# State flags
s = s.replace(
'''let currentDevice = null;
let fastboot = null;
''',
'''let currentDevice = null;
let fastboot = null;

let deviceVerified = false;
let releaseVerified = false;
let bootloaderUnlocked = null;
'''
)

# Add UI refs
marker = '''  flashButton:
    $("flash-button"),

  log:
'''

replacement = '''  flashButton:
    $("flash-button"),

  unlockButton:
    $("unlock-button"),

  unlockWipeConfirm:
    $("unlock-wipe-confirm"),

  unlockConfirmText:
    $("unlock-confirm-text"),

  log:
'''

if marker not in s:
    raise SystemExit("PATCH=FAIL: UI flash marker missing")

s = s.replace(marker, replacement)


# Safety invariants
old = '''if (FLASH_ENABLED !== false) {
  throw new Error(
    "V00.2 safety invariant violated."
  );
}
'''

new = '''if (
  FLASH_ENABLED !== false ||
  LOCK_ENABLED !== false
) {
  throw new Error(
    "V00.4 safety invariant violated."
  );
}

if (UNLOCK_ENABLED !== true) {
  throw new Error(
    "V00.4 unlock invariant violated."
  );
}
'''

if old in s:
    s = s.replace(old, new)
else:
    # account for previous version text
    import re
    s = re.sub(
        r'if \(FLASH_ENABLED !== false\) \{.*?\n\}',
        new.strip(),
        s,
        count=1,
        flags=re.S
    )


# Set verified state in queryFastboot
needle = '''  log(`Pixel target verified: ${product}`);
  log(`Bootloader unlocked: ${unlocked}`);
  log(`Current slot: ${slot}`);

  setBadge(
'''

replacement = '''  deviceVerified = true;

  bootloaderUnlocked =
    String(unlocked).trim().toLowerCase() === "yes";

  log(`Pixel target verified: ${product}`);
  log(`Bootloader unlocked: ${unlocked}`);
  log(`Current slot: ${slot}`);

  updateUnlockButton();

  setBadge(
'''

if needle not in s:
    raise SystemExit("PATCH=FAIL: device verified marker missing")

s = s.replace(needle, replacement)


# Set releaseVerified on success/failure
needle = '''    ui.releaseVerification.textContent =
      "VERIFIED";

    log("RELEASE_VERIFY=PASS");
'''

replacement = '''    ui.releaseVerification.textContent =
      "VERIFIED";

    releaseVerified = true;
    updateUnlockButton();

    log("RELEASE_VERIFY=PASS");
'''

if needle not in s:
    raise SystemExit("PATCH=FAIL: release success marker missing")

s = s.replace(needle, replacement)

needle = '''    ui.releaseVerification.textContent =
      "FAILED";
'''

replacement = '''    releaseVerified = false;
    updateUnlockButton();

    ui.releaseVerification.textContent =
      "FAILED";
'''

s = s.replace(needle, replacement)


# Add unlock functions before connect()
marker = '''
async function connect() {
'''

unlock_code = r'''
function updateUnlockButton() {

  if (!ui.unlockButton) {
    return;
  }

  const acknowledged =
    ui.unlockWipeConfirm.checked === true;

  const typed =
    ui.unlockConfirmText.value.trim() === "ERASE";

  const ready =
    UNLOCK_ENABLED === true &&
    deviceVerified === true &&
    releaseVerified === true &&
    bootloaderUnlocked === false &&
    acknowledged &&
    typed;

  ui.unlockButton.disabled = !ready;
}


async function unlockBootloader() {

  if (!fastboot) {
    throw new Error(
      "Fastboot device is not connected."
    );
  }

  if (!deviceVerified) {
    throw new Error(
      "Pixel 10 device verification has not passed."
    );
  }

  if (!releaseVerified) {
    throw new Error(
      "Release verification has not passed."
    );
  }

  if (bootloaderUnlocked === true) {
    throw new Error(
      "Bootloader is already unlocked."
    );
  }

  if (
    ui.unlockWipeConfirm.checked !== true ||
    ui.unlockConfirmText.value.trim() !== "ERASE"
  ) {
    throw new Error(
      "Factory reset confirmation is incomplete."
    );
  }

  ui.unlockButton.disabled = true;

  log("UNLOCK REQUEST STARTED");
  log("This operation will erase all user data.");

  try {

    let ability = "unknown";

    try {
      ability =
        await fastboot.getvar(
          "unlock_ability"
        );

      log(
        `unlock_ability=${ability}`
      );

      if (
        ability !== "" &&
        ability !== "1"
      ) {
        throw new Error(
          "OEM unlocking is not enabled. Boot Android, enable Developer options > OEM unlocking, then return to Fastboot Mode."
        );
      }

    } catch (error) {

      /*
       * Some bootloaders do not expose unlock_ability.
       * If the query itself is unsupported, the actual
       * unlock command still provides the authoritative result.
       */
      log(
        `unlock_ability query: ${error.message}`
      );
    }

    log(
      "Sending fastboot flashing unlock."
    );

    log(
      "CONFIRM THE UNLOCK ON THE PIXEL 10 USING ITS PHYSICAL BUTTONS."
    );

    await fastboot.unlockBootloader();

    log(
      "Unlock command accepted by bootloader."
    );

    log(
      "The Pixel may wipe data, reboot or disconnect. Re-enter Fastboot Mode and reconnect to verify unlocked=yes."
    );

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    log(
      `UNLOCK=FAIL: ${message}`
    );

    ui.deviceError.textContent =
      message;

    ui.deviceError.classList.remove(
      "hidden"
    );

  } finally {

    updateUnlockButton();
  }
}


'''

if unlock_code not in s:
    if marker not in s:
        raise SystemExit("PATCH=FAIL: connect marker missing")

    s = s.replace(
        marker,
        unlock_code + marker
    )


# Reset state on disconnect
needle = '''  currentDevice = null;

  ui.devicePanel.classList.add("hidden");
'''

replacement = '''  currentDevice = null;

  deviceVerified = false;
  bootloaderUnlocked = null;
  updateUnlockButton();

  ui.devicePanel.classList.add("hidden");
'''

if needle not in s:
    raise SystemExit("PATCH=FAIL: disconnect marker missing")

s = s.replace(needle, replacement)


# Event listeners
listener_marker = '''
ui.connectButton
  .addEventListener(
'''

listener = '''
ui.unlockWipeConfirm
  .addEventListener(
    "change",
    updateUnlockButton
  );


ui.unlockConfirmText
  .addEventListener(
    "input",
    updateUnlockButton
  );


ui.unlockButton
  .addEventListener(
    "click",
    unlockBootloader
  );


'''

if listener not in s:
    if listener_marker not in s:
        raise SystemExit("PATCH=FAIL: listener marker missing")

    s = s.replace(
        listener_marker,
        listener + listener_marker
    )

p.write_text(s)
print("APP_PATCH=PASS")
PY


#
# Visible version strings
#

sed -i \
  's/WOS-INSTALLER-V00\.3/WOS-INSTALLER-V00.4/g' \
  "$WEB/index.html"

sed -i \
  's/disabled in V00\.1/disabled in V00.4/g' \
  "$WEB/index.html"

sed -i \
  's/permitted in V00\.2/permitted in V00.4/g' \
  "$WEB/index.html"


#
# Safety verification
#

echo
echo "=== SAFETY VERIFY ==="

grep -q \
  'UNLOCK_ENABLED = true' \
  "$WEB/js/config.js"

grep -q \
  'FLASH_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'LOCK_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  '"flashing unlock"' \
  "$WEB/js/config.js"

if grep -R -E \
  '["'\''](flash:|erase:|download:|flashing lock)' \
  "$WEB/js" >/dev/null
then
    echo "FAIL: flash/erase/lock capability detected"
    exit 1
fi

echo "unlock_command=flashing_unlock"
echo "unlock_requires=device+release+ERASE+checkbox"
echo "flash=DISABLED"
echo "lock=DISABLED"

echo
echo "WOS_INSTALLER_V00_4=PASS"
