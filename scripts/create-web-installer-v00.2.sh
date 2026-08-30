#!/bin/bash
set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

test -d "$WEB/js"
test -f "$WEB/index.html"

echo "=== WOS-INSTALLER-V00.2 ==="

#
# config.js
#

cat > "$WEB/js/config.js" <<'EOF'
export const INSTALLER_VERSION = "WOS-INSTALLER-V00.2";

export const FLASH_ENABLED = false;

export const GOOGLE_VENDOR_ID = 0x18d1;

export const EXPECTED_PRODUCT = "frankel";

/*
 * Only these fastboot commands are permitted in V00.2.
 */
export const ALLOWED_FASTBOOT_COMMANDS = new Set([
  "getvar:product",
  "getvar:unlocked",
  "getvar:current-slot",
  "getvar:version-bootloader",
]);
EOF


#
# fastboot.js
#

cat > "$WEB/js/fastboot.js" <<'EOF'
import {
  ALLOWED_FASTBOOT_COMMANDS,
} from "./config.js";


const FASTBOOT_CLASS = 0xff;
const FASTBOOT_SUBCLASS = 0x42;
const FASTBOOT_PROTOCOL = 0x03;

const MAX_PACKET = 64;

const encoder = new TextEncoder();
const decoder = new TextDecoder();


export class FastbootError extends Error {
  constructor(message) {
    super(message);
    this.name = "FastbootError";
  }
}


export class FastbootTransport {

  constructor(device, logger = () => {}) {
    this.device = device;
    this.logger = logger;

    this.interfaceNumber = null;
    this.alternateSetting = null;

    this.endpointIn = null;
    this.endpointOut = null;

    this.connected = false;
  }


  findInterface() {

    for (const config of this.device.configurations ?? []) {

      for (const iface of config.interfaces ?? []) {

        for (const alt of iface.alternates ?? []) {

          if (
            alt.interfaceClass === FASTBOOT_CLASS &&
            alt.interfaceSubclass === FASTBOOT_SUBCLASS &&
            alt.interfaceProtocol === FASTBOOT_PROTOCOL
          ) {

            const epIn = alt.endpoints.find(
              ep => ep.direction === "in"
            );

            const epOut = alt.endpoints.find(
              ep => ep.direction === "out"
            );

            if (!epIn || !epOut) {
              continue;
            }

            return {
              configurationValue: config.configurationValue,
              interfaceNumber: iface.interfaceNumber,
              alternateSetting: alt.alternateSetting,
              endpointIn: epIn.endpointNumber,
              endpointOut: epOut.endpointNumber,
            };
          }
        }
      }
    }

    throw new FastbootError(
      "Fastboot USB interface not found. Boot the Pixel into bootloader/fastboot mode."
    );
  }


  async connect() {

    if (!this.device.opened) {
      await this.device.open();
    }

    const found = this.findInterface();

    if (
      !this.device.configuration ||
      this.device.configuration.configurationValue !==
        found.configurationValue
    ) {
      await this.device.selectConfiguration(
        found.configurationValue
      );
    }

    this.interfaceNumber =
      found.interfaceNumber;

    this.alternateSetting =
      found.alternateSetting;

    this.endpointIn =
      found.endpointIn;

    this.endpointOut =
      found.endpointOut;

    await this.device.claimInterface(
      this.interfaceNumber
    );

    if (this.alternateSetting !== 0) {
      await this.device.selectAlternateInterface(
        this.interfaceNumber,
        this.alternateSetting
      );
    }

    this.connected = true;

    this.logger(
      `Fastboot interface claimed: interface=${this.interfaceNumber}, IN=${this.endpointIn}, OUT=${this.endpointOut}`
    );
  }


  assertAllowed(command) {

    if (!ALLOWED_FASTBOOT_COMMANDS.has(command)) {
      throw new FastbootError(
        `Command blocked by V00.2 safety policy: ${command}`
      );
    }

    if (
      !command.startsWith("getvar:")
    ) {
      throw new FastbootError(
        "Only fastboot getvar commands are allowed."
      );
    }
  }


  async writeCommand(command) {

    this.assertAllowed(command);

    const bytes = encoder.encode(command);

    if (bytes.byteLength > MAX_PACKET) {
      throw new FastbootError(
        "Fastboot command exceeds 64 bytes."
      );
    }

    const result =
      await this.device.transferOut(
        this.endpointOut,
        bytes
      );

    if (result.status !== "ok") {
      throw new FastbootError(
        `USB transferOut failed: ${result.status}`
      );
    }

    if (result.bytesWritten !== bytes.byteLength) {
      throw new FastbootError(
        "Incomplete fastboot command transfer."
      );
    }

    this.logger(`→ ${command}`);
  }


  async readPacket() {

    const result =
      await this.device.transferIn(
        this.endpointIn,
        MAX_PACKET
      );

    if (result.status !== "ok") {
      throw new FastbootError(
        `USB transferIn failed: ${result.status}`
      );
    }

    if (!result.data) {
      throw new FastbootError(
        "Fastboot returned no data."
      );
    }

    const bytes = new Uint8Array(
      result.data.buffer,
      result.data.byteOffset,
      result.data.byteLength
    );

    return decoder
      .decode(bytes)
      .replace(/\0+$/g, "");
  }


  async command(command) {

    this.assertAllowed(command);

    if (!this.connected) {
      throw new FastbootError(
        "Fastboot transport is not connected."
      );
    }

    await this.writeCommand(command);

    while (true) {

      const packet =
        await this.readPacket();

      if (packet.length < 4) {
        throw new FastbootError(
          `Malformed fastboot response: ${packet}`
        );
      }

      const status =
        packet.slice(0, 4);

      const payload =
        packet.slice(4);

      if (status === "INFO") {
        this.logger(`← INFO ${payload}`);
        continue;
      }

      if (status === "OKAY") {
        this.logger(`← OKAY ${payload}`);
        return payload;
      }

      if (status === "FAIL") {
        this.logger(`← FAIL ${payload}`);

        throw new FastbootError(
          payload || "Fastboot command failed."
        );
      }

      if (status === "DATA") {
        /*
         * V00.2 never issues commands which have a data phase.
         */
        throw new FastbootError(
          "Unexpected DATA response. Transfer aborted."
        );
      }

      throw new FastbootError(
        `Unknown fastboot status: ${status}`
      );
    }
  }


  async getvar(name) {
    return this.command(
      `getvar:${name}`
    );
  }


  async disconnect() {

    if (
      this.connected &&
      this.interfaceNumber !== null
    ) {
      try {
        await this.device.releaseInterface(
          this.interfaceNumber
        );
      } catch {
        // Ignore release errors during cleanup.
      }
    }

    this.connected = false;
  }
}
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
      "WebUSB unavailable. Use Chrome/Edge over HTTPS."
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


export function hex(value, width = 4) {

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


export function inspectDevice(device) {

  let fastboot = false;

  for (const config of device.configurations ?? []) {
    for (const iface of config.interfaces ?? []) {
      for (const alt of iface.alternates ?? []) {

        if (
          alt.interfaceClass === 0xff &&
          alt.interfaceSubclass === 0x42 &&
          alt.interfaceProtocol === 0x03
        ) {
          fastboot = true;
        }
      }
    }
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

    mode:
      fastboot ? "fastboot" : "unknown",
  };
}
EOF


#
# app.js
#

cat > "$WEB/js/app.js" <<'EOF'
import {
  FLASH_ENABLED,
  INSTALLER_VERSION,
  EXPECTED_PRODUCT,
} from "./config.js";

import {
  requestPixel,
  inspectDevice,
  webUsbAvailable,
} from "./device.js";

import {
  FastbootTransport,
} from "./fastboot.js";


if (FLASH_ENABLED !== false) {
  throw new Error(
    "V00.2 safety invariant violated."
  );
}


let currentDevice = null;
let fastboot = null;


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


function log(message) {

  const stamp =
    new Date().toLocaleTimeString();

  ui.log.textContent +=
    `${ui.log.textContent ? "\n" : ""}[${stamp}] ${message}`;

  ui.log.scrollTop =
    ui.log.scrollHeight;
}


function setBadge(
  element,
  text,
  state
) {
  element.textContent = text;
  element.className = `badge ${state}`;
}


function errorMessage(message) {
  ui.deviceError.textContent = message;
  ui.deviceError.classList.remove("hidden");
}


function clearError() {
  ui.deviceError.textContent = "";
  ui.deviceError.classList.add("hidden");
}


function environment() {

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

  } else {

    setBadge(
      ui.environmentStatus,
      "FAIL",
      "danger"
    );

    ui.connectButton.disabled = true;
  }

  ui.flashButton.disabled = true;

  log(`${INSTALLER_VERSION} ready`);
  log("FLASH_ENABLED=false");
  log("Allowed fastboot operation: getvar only");
}


async function queryFastboot() {

  const product =
    await fastboot.getvar("product");

  const unlocked =
    await fastboot.getvar("unlocked");

  const slot =
    await fastboot.getvar("current-slot");

  let bootloader = "unknown";

  try {
    bootloader =
      await fastboot.getvar(
        "version-bootloader"
      );
  } catch (error) {
    log(
      `version-bootloader unavailable: ${error.message}`
    );
  }

  ui.interfaceOutput.textContent =
`FASTBOOT READ-ONLY

product=${product}
unlocked=${unlocked}
current-slot=${slot}
version-bootloader=${bootloader}

FLASH_ENABLED=false`;

  if (product !== EXPECTED_PRODUCT) {

    setBadge(
      ui.deviceStatus,
      "WRONG DEVICE",
      "danger"
    );

    throw new Error(
      `Expected Pixel 10 (${EXPECTED_PRODUCT}), device reports ${product || "unknown"}.`
    );
  }

  log(`Pixel target verified: ${product}`);
  log(`Bootloader unlocked: ${unlocked}`);
  log(`Current slot: ${slot}`);

  setBadge(
    ui.deviceStatus,
    "PIXEL 10 VERIFIED",
    "good"
  );
}


async function connect() {

  clearError();

  try {

    log("Opening WebUSB chooser");

    const device =
      await requestPixel();

    currentDevice = device;

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

    ui.devicePanel.classList
      .remove("hidden");

    if (info.mode !== "fastboot") {
      throw new Error(
        "Google USB device detected, but it is not in fastboot/bootloader mode."
      );
    }

    fastboot =
      new FastbootTransport(
        device,
        log
      );

    await fastboot.connect();

    await queryFastboot();

    ui.connectButton.disabled = true;
    ui.disconnectButton.disabled = false;

  } catch (error) {

    const message =
      error instanceof Error
        ? error.message
        : String(error);

    errorMessage(message);
    log(`ERROR: ${message}`);

    if (fastboot) {
      await fastboot.disconnect();
    }

    fastboot = null;

    if (
      currentDevice &&
      currentDevice.opened
    ) {
      try {
        await currentDevice.close();
      } catch {}
    }

    currentDevice = null;

    ui.connectButton.disabled =
      !webUsbAvailable();
  }
}


async function disconnect() {

  clearError();

  if (fastboot) {
    await fastboot.disconnect();
  }

  fastboot = null;

  if (
    currentDevice &&
    currentDevice.opened
  ) {
    try {
      await currentDevice.close();
    } catch {}
  }

  currentDevice = null;

  ui.devicePanel.classList.add("hidden");

  setBadge(
    ui.deviceStatus,
    "NOT CONNECTED",
    "neutral"
  );

  ui.connectButton.disabled =
    !webUsbAvailable();

  ui.disconnectButton.disabled = true;

  log("Device disconnected");
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

  navigator.usb.addEventListener(
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


environment();
EOF


#
# Patch visible V00.1 labels in index.html
#

sed -i \
  's/WOS-INSTALLER-V00\.1/WOS-INSTALLER-V00.2/g' \
  "$WEB/index.html"

sed -i \
  's/No USB transfers are performed in V00\.1\./Only read-only fastboot getvar queries are permitted in V00.2./g' \
  "$WEB/index.html"

sed -i \
  's/Physical flashing is intentionally disabled[[:space:]]*in V00\.1\./Physical flashing is intentionally disabled in V00.2./g' \
  "$WEB/index.html"


#
# Verification
#

echo
echo "=== VERIFY ==="

grep -q \
  'FLASH_ENABLED = false' \
  "$WEB/js/config.js"

grep -q \
  'EXPECTED_PRODUCT = "frankel"' \
  "$WEB/js/config.js"

grep -q \
  '"getvar:product"' \
  "$WEB/js/config.js"

#
# These dangerous fastboot commands must not be present
# as executable protocol strings.
#

if grep -R -E \
  '["'\''](flash:|erase:|download:|boot$|reboot$|flashing unlock|flashing lock)' \
  "$WEB/js" >/dev/null
then
    echo "FAIL: write-capable fastboot command detected"
    exit 1
fi

echo "flash_guard=PASS"
echo "target_guard=frankel"
echo "allowed_fastboot=getvar_only"

echo
echo "WOS_INSTALLER_V00_2=PASS"
