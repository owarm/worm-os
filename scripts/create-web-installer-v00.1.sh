#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
WEB="$ROOT/web-installer"

echo "=== worm OS Web Installer V00.1 ==="

mkdir -p \
    "$WEB/css" \
    "$WEB/js" \
    "$WEB/assets"

#
# index.html
#

cat > "$WEB/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta
    name="viewport"
    content="width=device-width,initial-scale=1,viewport-fit=cover"
  >

  <title>worm OS — Web Installer</title>

  <meta
    name="description"
    content="worm OS WebUSB installer"
  >

  <link rel="stylesheet" href="./css/main.css">
</head>

<body>
  <main class="shell">

    <header class="hero">
      <div class="brand">
        <div class="logo">w</div>

        <div>
          <h1>worm OS</h1>
          <p>Web Installer</p>
        </div>
      </div>

      <div class="version">
        WOS-INSTALLER-V00.1
      </div>
    </header>


    <section class="card">
      <div class="section-head">
        <div>
          <h2>Environment</h2>
          <p>Browser and WebUSB readiness.</p>
        </div>

        <span id="environment-status" class="badge neutral">
          CHECKING
        </span>
      </div>

      <div class="grid">
        <div class="item">
          <span class="label">Secure context</span>
          <span id="secure-context">—</span>
        </div>

        <div class="item">
          <span class="label">WebUSB</span>
          <span id="webusb-support">—</span>
        </div>

        <div class="item">
          <span class="label">Protocol</span>
          <span id="page-protocol">—</span>
        </div>

        <div class="item">
          <span class="label">Flash capability</span>
          <span class="danger-text">DISABLED</span>
        </div>
      </div>
    </section>


    <section class="card">
      <div class="section-head">
        <div>
          <h2>Device</h2>
          <p>
            Connect a Pixel through USB.
            No data will be written to it.
          </p>
        </div>

        <span id="device-status" class="badge neutral">
          NOT CONNECTED
        </span>
      </div>

      <div class="actions">
        <button id="connect-button" class="primary">
          Connect Pixel
        </button>

        <button id="disconnect-button" disabled>
          Disconnect
        </button>
      </div>

      <div id="device-panel" class="device-panel hidden">

        <div class="grid">

          <div class="item">
            <span class="label">Manufacturer</span>
            <span id="device-manufacturer">—</span>
          </div>

          <div class="item">
            <span class="label">Product</span>
            <span id="device-product">—</span>
          </div>

          <div class="item">
            <span class="label">Serial</span>
            <span id="device-serial">—</span>
          </div>

          <div class="item">
            <span class="label">Vendor ID</span>
            <span id="device-vendor">—</span>
          </div>

          <div class="item">
            <span class="label">Product ID</span>
            <span id="device-product-id">—</span>
          </div>

          <div class="item">
            <span class="label">USB mode</span>
            <span id="device-mode">—</span>
          </div>

        </div>

        <details>
          <summary>USB interfaces</summary>
          <pre id="interface-output"></pre>
        </details>

      </div>

      <div id="device-error" class="message error hidden"></div>
    </section>


    <section class="card">
      <div class="section-head">
        <div>
          <h2>Release</h2>
          <p>worm OS install image.</p>
        </div>

        <span class="badge warning">
          UNAVAILABLE
        </span>
      </div>

      <div class="grid">

        <div class="item">
          <span class="label">Channel</span>
          <span>development</span>
        </div>

        <div class="item">
          <span class="label">Build</span>
          <span>not published</span>
        </div>

        <div class="item">
          <span class="label">Signature</span>
          <span>not available</span>
        </div>

        <div class="item">
          <span class="label">Target</span>
          <span>not selected</span>
        </div>

      </div>
    </section>


    <section class="card locked">

      <div class="section-head">

        <div>
          <h2>Installation</h2>
          <p>
            Physical flashing is intentionally disabled
            in V00.1.
          </p>
        </div>

        <span class="badge danger">
          LOCKED
        </span>

      </div>

      <div class="install-flow">

        <div class="step">
          <span>01</span>
          Detect device
        </div>

        <div class="step disabled">
          <span>02</span>
          Verify release
        </div>

        <div class="step disabled">
          <span>03</span>
          Unlock
        </div>

        <div class="step disabled">
          <span>04</span>
          Flash
        </div>

        <div class="step disabled">
          <span>05</span>
          Verify
        </div>

        <div class="step disabled">
          <span>06</span>
          Lock
        </div>

      </div>

      <button
        id="flash-button"
        class="flash"
        disabled
      >
        Flash worm OS — disabled
      </button>

    </section>


    <section class="card log-card">

      <div class="section-head">

        <div>
          <h2>Session log</h2>
          <p>No USB transfers are performed in V00.1.</p>
        </div>

        <button id="clear-log">
          Clear
        </button>

      </div>

      <pre id="log"></pre>

    </section>


    <footer>
      worm OS · installer V00.1 · FLASH_ENABLED=false
    </footer>

  </main>

  <script type="module" src="./js/app.js"></script>
</body>
</html>
EOF


#
# CSS
#

cat > "$WEB/css/main.css" <<'EOF'
:root {
  color-scheme: dark;

  --bg: #090a0c;
  --panel: #111317;
  --panel-2: #171a20;
  --border: #282d36;
  --text: #f2f3f5;
  --muted: #949ba8;
  --accent: #e8eaed;

  --good: #75d99b;
  --warn: #e7c96c;
  --bad: #ed7c86;

  font-family:
    Inter,
    ui-sans-serif,
    system-ui,
    -apple-system,
    BlinkMacSystemFont,
    "Segoe UI",
    sans-serif;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;

  min-height: 100vh;

  background:
    radial-gradient(
      circle at 50% -20%,
      #242832 0,
      transparent 42%
    ),
    var(--bg);

  color: var(--text);
}

.shell {
  width: min(960px, calc(100% - 32px));
  margin: 0 auto;
  padding: 48px 0 64px;
}

.hero {
  display: flex;
  align-items: center;
  justify-content: space-between;

  margin-bottom: 28px;
}

.brand {
  display: flex;
  gap: 16px;
  align-items: center;
}

.logo {
  width: 52px;
  height: 52px;

  display: grid;
  place-items: center;

  background: var(--text);
  color: var(--bg);

  border-radius: 15px;

  font-size: 30px;
  font-weight: 800;
}

h1,
h2,
p {
  margin: 0;
}

h1 {
  font-size: 25px;
  letter-spacing: -0.04em;
}

.brand p {
  margin-top: 3px;
  color: var(--muted);
}

.version {
  color: var(--muted);
  font-family: ui-monospace, monospace;
  font-size: 12px;
}

.card {
  margin: 14px 0;
  padding: 22px;

  border: 1px solid var(--border);
  border-radius: 17px;

  background: color-mix(
    in srgb,
    var(--panel) 94%,
    transparent
  );
}

.section-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 24px;

  margin-bottom: 20px;
}

.section-head h2 {
  font-size: 17px;
  margin-bottom: 5px;
}

.section-head p {
  color: var(--muted);
  line-height: 1.45;
  font-size: 14px;
}

.badge {
  padding: 6px 9px;

  border-radius: 999px;
  border: 1px solid var(--border);

  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.04em;

  white-space: nowrap;
}

.badge.good {
  color: var(--good);
}

.badge.warning {
  color: var(--warn);
}

.badge.danger {
  color: var(--bad);
}

.badge.neutral {
  color: var(--muted);
}

.grid {
  display: grid;

  grid-template-columns:
    repeat(2, minmax(0, 1fr));

  gap: 10px;
}

.item {
  display: flex;
  flex-direction: column;

  gap: 5px;

  padding: 13px;

  background: var(--panel-2);

  border: 1px solid var(--border);
  border-radius: 11px;

  overflow-wrap: anywhere;
}

.label {
  color: var(--muted);
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.07em;
}

.danger-text {
  color: var(--bad);
  font-weight: 700;
}

.actions {
  display: flex;
  gap: 10px;
  margin-bottom: 17px;
}

button {
  appearance: none;

  padding: 10px 14px;

  border-radius: 10px;
  border: 1px solid var(--border);

  color: var(--text);
  background: var(--panel-2);

  font: inherit;
  font-size: 14px;

  cursor: pointer;
}

button.primary {
  color: #0b0c0e;
  background: var(--accent);
  border-color: var(--accent);
  font-weight: 700;
}

button:disabled {
  cursor: not-allowed;
  opacity: 0.38;
}

.device-panel {
  margin-top: 4px;
}

details {
  margin-top: 12px;

  padding: 13px;

  border: 1px solid var(--border);
  border-radius: 11px;

  background: var(--panel-2);
}

summary {
  cursor: pointer;
  color: var(--muted);
}

pre {
  overflow: auto;
  white-space: pre-wrap;
  word-break: break-word;
}

details pre {
  margin: 14px 0 0;
  font-size: 12px;
}

.install-flow {
  display: grid;
  gap: 8px;

  margin: 4px 0 17px;
}

.step {
  display: flex;
  align-items: center;
  gap: 13px;

  padding: 11px 13px;

  border: 1px solid var(--border);
  border-radius: 10px;

  background: var(--panel-2);
}

.step span {
  width: 25px;
  color: var(--muted);
  font-family: ui-monospace, monospace;
  font-size: 11px;
}

.step.disabled {
  color: var(--muted);
  opacity: 0.52;
}

.flash {
  width: 100%;
}

.message {
  margin-top: 12px;

  padding: 11px 13px;

  border-radius: 10px;

  font-size: 13px;
}

.message.error {
  border: 1px solid color-mix(
    in srgb,
    var(--bad) 45%,
    var(--border)
  );

  color: var(--bad);
  background: color-mix(
    in srgb,
    var(--bad) 8%,
    transparent
  );
}

.hidden {
  display: none;
}

.log-card pre {
  min-height: 130px;
  max-height: 300px;

  margin: 0;
  padding: 13px;

  border-radius: 11px;
  border: 1px solid var(--border);

  background: #08090b;

  color: #b9c0ca;

  font-family: ui-monospace, monospace;
  font-size: 12px;
  line-height: 1.5;
}

footer {
  margin-top: 25px;

  color: var(--muted);

  text-align: center;
  font-family: ui-monospace, monospace;
  font-size: 11px;
}

@media (max-width: 640px) {
  .shell {
    width: min(100% - 20px, 960px);
    padding-top: 24px;
  }

  .hero {
    align-items: flex-start;
    flex-direction: column;
    gap: 15px;
  }

  .grid {
    grid-template-columns: 1fr;
  }

  .section-head {
    flex-direction: column;
    gap: 10px;
  }
}
EOF


#
# config.js
#

cat > "$WEB/js/config.js" <<'EOF'
export const INSTALLER_VERSION = "WOS-INSTALLER-V00.1";

/*
 * HARD SAFETY SWITCH.
 *
 * V00.1 contains no flashing implementation.
 * This constant must remain false.
 */
export const FLASH_ENABLED = false;

/*
 * Google's USB vendor ID.
 *
 * The requestDevice filter intentionally restricts
 * the chooser to Google USB devices for V00.1.
 */
export const GOOGLE_VENDOR_ID = 0x18d1;
EOF


#
# device.js
#

cat > "$WEB/js/device.js" <<'EOF'
import {
  GOOGLE_VENDOR_ID,
} from "./config.js";


export function webUsbAvailable() {
  return (
    window.isSecureContext === true &&
    "usb" in navigator
  );
}


export async function requestPixel() {
  if (!webUsbAvailable()) {
    throw new Error(
      "WebUSB is unavailable. Use a supported Chromium-based browser over HTTPS or localhost."
    );
  }

  return navigator.usb.requestDevice({
    filters: [
      {
        vendorId: GOOGLE_VENDOR_ID,
      },
    ],
  });
}


function hex(value, width = 4) {
  if (typeof value !== "number") {
    return "—";
  }

  return (
    "0x" +
    value
      .toString(16)
      .padStart(width, "0")
      .toUpperCase()
  );
}


export function classifyInterface(
  interfaceClass,
  interfaceSubclass,
  interfaceProtocol
) {
  /*
   * Common Android USB interface values.
   *
   * This is classification only.
   * No USB interface is claimed and no transfers
   * are sent by V00.1.
   */

  if (
    interfaceClass === 0xff &&
    interfaceSubclass === 0x42 &&
    interfaceProtocol === 0x03
  ) {
    return "fastboot";
  }

  if (
    interfaceClass === 0xff &&
    interfaceSubclass === 0x42 &&
    interfaceProtocol === 0x01
  ) {
    return "adb";
  }

  return "unknown";
}


export function inspectDevice(device) {
  const interfaces = [];

  const configurations =
    device.configurations ?? [];

  for (const configuration of configurations) {

    for (const iface of configuration.interfaces) {

      for (
        const alternate
        of iface.alternates
      ) {
        interfaces.push({
          configurationValue:
            configuration.configurationValue,

          interfaceNumber:
            iface.interfaceNumber,

          alternateSetting:
            alternate.alternateSetting,

          interfaceClass:
            alternate.interfaceClass,

          interfaceSubclass:
            alternate.interfaceSubclass,

          interfaceProtocol:
            alternate.interfaceProtocol,

          interfaceName:
            alternate.interfaceName ?? null,

          mode: classifyInterface(
            alternate.interfaceClass,
            alternate.interfaceSubclass,
            alternate.interfaceProtocol
          ),
        });
      }
    }
  }

  const modes =
    [...new Set(
      interfaces.map(
        entry => entry.mode
      )
    )];

  let mode = "unknown";

  if (modes.includes("fastboot")) {
    mode = "fastboot";
  } else if (modes.includes("adb")) {
    mode = "adb";
  }

  return {
    manufacturer:
      device.manufacturerName ?? "—",

    product:
      device.productName ?? "—",

    serial:
      device.serialNumber ?? "—",

    vendorId:
      hex(device.vendorId),

    productId:
      hex(device.productId),

    mode,

    interfaces,
  };
}


export function formatInterfaces(entries) {
  if (!entries.length) {
    return "No USB interface descriptors available.";
  }

  return entries
    .map((entry, index) => {
      return [
        `#${index + 1}`,
        `configuration=${entry.configurationValue}`,
        `interface=${entry.interfaceNumber}`,
        `alternate=${entry.alternateSetting}`,
        `class=${hex(entry.interfaceClass, 2)}`,
        `subclass=${hex(entry.interfaceSubclass, 2)}`,
        `protocol=${hex(entry.interfaceProtocol, 2)}`,
        `mode=${entry.mode}`,
        `name=${entry.interfaceName ?? "—"}`,
      ].join(" ");
    })
    .join("\n");
}
EOF


#
# app.js
#

cat > "$WEB/js/app.js" <<'EOF'
import {
  FLASH_ENABLED,
  INSTALLER_VERSION,
} from "./config.js";

import {
  requestPixel,
  inspectDevice,
  formatInterfaces,
  webUsbAvailable,
} from "./device.js";


if (FLASH_ENABLED !== false) {
  throw new Error(
    "Safety invariant violated: FLASH_ENABLED must be false in V00.1."
  );
}


let currentDevice = null;


const $ = id =>
  document.getElementById(id);


const ui = {
  environmentStatus:
    $("environment-status"),

  secureContext:
    $("secure-context"),

  webUsbSupport:
    $("webusb-support"),

  pageProtocol:
    $("page-protocol"),

  deviceStatus:
    $("device-status"),

  connectButton:
    $("connect-button"),

  disconnectButton:
    $("disconnect-button"),

  devicePanel:
    $("device-panel"),

  deviceManufacturer:
    $("device-manufacturer"),

  deviceProduct:
    $("device-product"),

  deviceSerial:
    $("device-serial"),

  deviceVendor:
    $("device-vendor"),

  deviceProductId:
    $("device-product-id"),

  deviceMode:
    $("device-mode"),

  interfaceOutput:
    $("interface-output"),

  deviceError:
    $("device-error"),

  flashButton:
    $("flash-button"),

  log:
    $("log"),

  clearLog:
    $("clear-log"),
};


function timestamp() {
  return new Date()
    .toLocaleTimeString();
}


function log(message) {
  const line =
    `[${timestamp()}] ${message}`;

  if (ui.log.textContent) {
    ui.log.textContent += "\n";
  }

  ui.log.textContent += line;

  ui.log.scrollTop =
    ui.log.scrollHeight;
}


function setBadge(
  element,
  text,
  state
) {
  element.textContent = text;

  element.className =
    `badge ${state}`;
}


function showError(message) {
  ui.deviceError.textContent =
    message;

  ui.deviceError.classList
    .remove("hidden");
}


function clearError() {
  ui.deviceError.classList
    .add("hidden");

  ui.deviceError.textContent = "";
}


function initialiseEnvironment() {
  const secure =
    window.isSecureContext;

  const usb =
    "usb" in navigator;

  ui.secureContext.textContent =
    secure ? "PASS" : "FAIL";

  ui.webUsbSupport.textContent =
    usb ? "PASS" : "FAIL";

  ui.pageProtocol.textContent =
    location.protocol;

  if (webUsbAvailable()) {
    setBadge(
      ui.environmentStatus,
      "PASS",
      "good"
    );

    ui.connectButton.disabled = false;

    log(
      `${INSTALLER_VERSION} ready. WebUSB available.`
    );
  } else {
    setBadge(
      ui.environmentStatus,
      "FAIL",
      "danger"
    );

    ui.connectButton.disabled = true;

    log(
      "WebUSB environment unavailable."
    );
  }

  ui.flashButton.disabled = true;

  log(
    "FLASH_ENABLED=false"
  );
}


async function connect() {
  clearError();

  try {
    log(
      "Opening browser USB device chooser."
    );

    const device =
      await requestPixel();

    currentDevice = device;

    /*
     * Opening allows WebUSB to obtain descriptors.
     *
     * V00.1 DOES NOT:
     * - select a configuration
     * - claim an interface
     * - transferIn
     * - transferOut
     * - send control transfers
     */

    if (!device.opened) {
      await device.open();
    }

    const info =
      inspectDevice(device);

    ui.deviceManufacturer.textContent =
      info.manufacturer;

    ui.deviceProduct.textContent =
      info.product;

    ui.deviceSerial.textContent =
      info.serial;

    ui.deviceVendor.textContent =
      info.vendorId;

    ui.deviceProductId.textContent =
      info.productId;

    ui.deviceMode.textContent =
      info.mode;

    ui.interfaceOutput.textContent =
      formatInterfaces(
        info.interfaces
      );

    ui.devicePanel.classList
      .remove("hidden");

    setBadge(
      ui.deviceStatus,
      "CONNECTED",
      "good"
    );

    ui.connectButton.disabled =
      true;

    ui.disconnectButton.disabled =
      false;

    log(
      `Device connected: ${info.product}`
    );

    log(
      `USB mode classification: ${info.mode}`
    );

    log(
      "Read-only descriptor inspection complete."
    );

  } catch (error) {
    currentDevice = null;

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    showError(message);

    setBadge(
      ui.deviceStatus,
      "NOT CONNECTED",
      "neutral"
    );

    log(
      `Connection failed: ${message}`
    );
  }
}


async function disconnect() {
  clearError();

  if (!currentDevice) {
    return;
  }

  try {
    if (currentDevice.opened) {
      await currentDevice.close();
    }
  } catch (error) {
    log(
      `USB close warning: ${error}`
    );
  }

  currentDevice = null;

  ui.devicePanel.classList
    .add("hidden");

  setBadge(
    ui.deviceStatus,
    "NOT CONNECTED",
    "neutral"
  );

  ui.connectButton.disabled =
    !webUsbAvailable();

  ui.disconnectButton.disabled =
    true;

  log(
    "Device disconnected."
  );
}


ui.connectButton
  .addEventListener(
    "click",
    connect
  );


ui.disconnectButton
  .addEventListener(
    "click",
    disconnect
  );


ui.clearLog
  .addEventListener(
    "click",
    () => {
      ui.log.textContent = "";
    }
  );


if ("usb" in navigator) {

  navigator.usb
    .addEventListener(
      "disconnect",
      event => {
        if (
          currentDevice &&
          event.device === currentDevice
        ) {
          disconnect();
        }
      }
    );

}


initialiseEnvironment();
EOF


#
# README
#

cat > "$WEB/README.md" <<'EOF'
# worm OS Web Installer

Version:

    WOS-INSTALLER-V00.1

Status:

    WebUSB detection: enabled
    Google USB filter: enabled
    USB descriptor inspection: enabled

    Fastboot commands: disabled
    Unlock: disabled
    Download release: disabled
    Flash: disabled
    Relock: disabled

Safety invariant:

    FLASH_ENABLED=false

Run locally:

    cd /opt/Android/worm-os/web-installer
    python3 -m http.server 8080 --bind 127.0.0.1

Open:

    http://localhost:8080

WebUSB requires a secure context.
Browsers treat localhost as a potentially trustworthy origin.

V00.1 performs no USB transfer commands.
EOF


#
# Local dev launcher
#

cat > "$ROOT/scripts/run-web-installer.sh" <<'EOF'
#!/bin/bash

set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

cd "$WEB"

echo "=== worm OS Web Installer ==="
echo
echo "Version: WOS-INSTALLER-V00.1"
echo "URL:     http://localhost:8080"
echo
echo "FLASH_ENABLED=false"
echo

exec python3 \
    -m http.server \
    8080 \
    --bind 127.0.0.1
EOF

chmod +x \
  "$ROOT/scripts/run-web-installer.sh"


echo
echo "=== VERIFY ==="

test -f "$WEB/index.html"
test -f "$WEB/css/main.css"
test -f "$WEB/js/config.js"
test -f "$WEB/js/device.js"
test -f "$WEB/js/app.js"

grep -q \
  'FLASH_ENABLED = false' \
  "$WEB/js/config.js"

if grep -R -E \
  '\.(transferOut|transferIn|controlTransferOut|claimInterface|reset)[[:space:]]*\(' \
  "$WEB/js" >/dev/null
then
  echo "FAIL: active USB transfer API call found"
  exit 1
fi

echo "files=PASS"
echo "flash_guard=PASS"
echo "usb_transfer_code=NONE"
echo

find "$WEB" \
  -maxdepth 2 \
  -type f \
  -printf '%P\n' \
  | sort

echo
echo "WOS_INSTALLER_V00_1=PASS"
