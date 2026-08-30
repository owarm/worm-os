#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

echo "=== WOS-INSTALLER-V00.3 UI ==="

test -f "$WEB/index.html"
test -f "$WEB/js/app.js"
test -f "$WEB/js/release.js"

#
# Add button + release status area
#

python3 - <<'PY'
from pathlib import Path

p = Path("/opt/Android/worm-os/web-installer/index.html")
s = p.read_text()

s = s.replace(
    "WOS-INSTALLER-V00.2",
    "WOS-INSTALLER-V00.3"
)

needle = '''
      <div class="grid">

        <div class="item">
          <span class="label">Channel</span>
          <span>development</span>
        </div>
'''

replacement = '''
      <div class="actions">
        <button id="verify-release-button" class="primary">
          Verify release
        </button>
      </div>

      <div id="release-error" class="message error hidden"></div>

      <div class="grid">

        <div class="item">
          <span class="label">Channel</span>
          <span id="release-channel">development</span>
        </div>
'''

if needle not in s:
    raise SystemExit("PATCH=FAIL: release grid not found")

s = s.replace(needle, replacement)

s = s.replace(
'''          <span class="label">Build</span>
          <span>not published</span>''',
'''          <span class="label">Build</span>
          <span id="release-build">not loaded</span>'''
)

s = s.replace(
'''          <span class="label">Signature</span>
          <span>not available</span>''',
'''          <span class="label">Verification</span>
          <span id="release-verification">NOT VERIFIED</span>'''
)

s = s.replace(
'''          <span class="label">Target</span>
          <span>not selected</span>''',
'''          <span class="label">Target</span>
          <span id="release-target">not loaded</span>'''
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

import_marker = '''import {
  FastbootTransport,
} from "./fastboot.js";
'''

release_import = '''import {
  loadCurrentRelease,
  verifyArtifact,
} from "./release.js";
'''

if release_import not in s:
    s = s.replace(
        import_marker,
        import_marker + "\n" + release_import
    )


ui_marker = '''  clearLog:
    $("clear-log"),
};
'''

ui_new = '''  clearLog:
    $("clear-log"),

  verifyReleaseButton:
    $("verify-release-button"),

  releaseChannel:
    $("release-channel"),

  releaseBuild:
    $("release-build"),

  releaseVerification:
    $("release-verification"),

  releaseTarget:
    $("release-target"),

  releaseError:
    $("release-error"),
};
'''

if ui_marker not in s:
    raise SystemExit("PATCH=FAIL: UI marker missing")

s = s.replace(ui_marker, ui_new)


insert_before = '''
async function connect() {
'''

verify_code = r'''
async function verifyRelease() {

  ui.releaseError.classList.add("hidden");
  ui.releaseError.textContent = "";

  ui.verifyReleaseButton.disabled = true;

  ui.releaseVerification.textContent =
    "VERIFYING...";

  try {

    log("Loading current frankel release");

    const {
      pointer,
      manifest,
    } = await loadCurrentRelease();

    ui.releaseChannel.textContent =
      manifest.channel;

    ui.releaseBuild.textContent =
      `${manifest.build.version} / ${manifest.build.build_id}`;

    ui.releaseTarget.textContent =
      `${manifest.device.name} (${manifest.device.codename})`;

    log(
      `Release manifest loaded: ${pointer.version}`
    );

    log(
      `Target: ${manifest.device.codename}`
    );

    log(
      "Safety policy: unlock=false flash=false lock=false"
    );

    const verifyNames =
      new Set([
        "boot.img",
        "vendor_boot.img",
        "vbmeta.img",
      ]);

    const selected =
      manifest.artifacts.filter(
        artifact =>
          verifyNames.has(artifact.name)
      );

    if (selected.length !== 3) {
      throw new Error(
        "Verification artifact set incomplete."
      );
    }

    for (const artifact of selected) {

      log(
        `Verifying ${artifact.name} (${artifact.size} bytes)`
      );

      await verifyArtifact(
        new URL(
          pointer.manifest,
          location.origin
        ).href,
        artifact,
        (name, received, total) => {

          const percent =
            total > 0
              ? Math.floor(
                  received * 100 / total
                )
              : 0;

          ui.releaseVerification.textContent =
            `${name} ${percent}%`;
        }
      );

      log(
        `${artifact.name}: SHA-256 PASS`
      );
    }

    ui.releaseVerification.textContent =
      "VERIFIED";

    log("RELEASE_VERIFY=PASS");

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    ui.releaseVerification.textContent =
      "FAILED";

    ui.releaseError.textContent =
      message;

    ui.releaseError.classList.remove(
      "hidden"
    );

    log(
      `RELEASE_VERIFY=FAIL: ${message}`
    );

  } finally {

    ui.verifyReleaseButton.disabled =
      false;
  }
}

'''

if verify_code not in s:
    if insert_before not in s:
        raise SystemExit(
            "PATCH=FAIL: connect marker missing"
        )

    s = s.replace(
        insert_before,
        verify_code + insert_before
    )


listener_marker = '''
ui.connectButton
  .addEventListener(
'''

listener = '''
ui.verifyReleaseButton
  .addEventListener(
    "click",
    verifyRelease
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
# Verify hard safety invariants
#

echo
echo "=== SAFETY VERIFY ==="

grep -q \
  'FLASH_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'EXPECTED_PRODUCT = "frankel"' \
  "$WEB/js/config.js"

grep -q \
  'verify-release-button' \
  "$WEB/index.html"

grep -q \
  'RELEASE_VERIFY=PASS' \
  "$WEB/js/app.js"

if grep -R -E \
  '["'\''](flash:|erase:|download:|flashing unlock|flashing lock)' \
  "$WEB/js" >/dev/null
then
    echo "FAIL: write-capable fastboot command found"
    exit 1
fi

echo "release_ui=PASS"
echo "sha256_verification=boot,vendor_boot,vbmeta"
echo "unlock=DISABLED"
echo "flash=DISABLED"
echo "lock=DISABLED"

echo
echo "WOS_INSTALLER_V00_3_UI=PASS"
