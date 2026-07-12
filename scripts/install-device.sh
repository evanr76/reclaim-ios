#!/usr/bin/env bash
# Build a signed device build and install it on a connected iPhone.
#
# Usage:
#   ./scripts/install-device.sh                 # auto-pick first available iPhone
#   ./scripts/install-device.sh <device-udid>   # target a specific device
#
# Requirements (one-time): Developer Mode enabled on the device, the device
# trusted + UNLOCKED, and a signing team set in project.yml (DEVELOPMENT_TEAM).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/4] Generating project..."
xcodegen generate >/dev/null

echo "[2/4] Building signed device build..."
xcodebuild -project ReclaimIOS.xcodeproj -scheme ReclaimIOS \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  -derivedDataPath build build >/dev/null
APP="build/Build/Products/Debug-iphoneos/ReclaimIOS.app"

DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null \
  | grep -i available | grep -i iphone \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}' | head -1)}"
if [ -z "${DEVICE}" ]; then
  echo "No available iPhone found. Connect/unlock the device (or pass its UDID)." >&2
  exit 1
fi

echo "[3/4] Installing to ${DEVICE} (device must be unlocked)..."
xcrun devicectl device install app --device "${DEVICE}" "${APP}"

echo "[4/4] Launching..."
xcrun devicectl device process launch --device "${DEVICE}" io.github.evanr76.reclaimios || true
rm -rf build
echo "Done."
