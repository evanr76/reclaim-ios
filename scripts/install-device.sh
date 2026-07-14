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

if [ -n "${1:-}" ]; then
  DEVICE="$1"
else
  # Capture first (|| true), then parse via here-string so no pipeline can
  # SIGPIPE-fail under `set -o pipefail` before the empty-DEVICE check.
  DEVICE_LIST="$(xcrun devicectl list devices 2>/dev/null || true)"
  # Match iPhones that are reachable ("available (paired)" or "connected") and
  # NOT "unavailable" (note: /available/ alone also matches "unavailable").
  DEVICE="$(awk 'tolower($0) ~ /iphone/ && !/unavailable/ && (/available \(paired\)/ || /connected/) {
      for (i = 1; i <= NF; i++)
        if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/) { print $i; exit }
    }' <<< "${DEVICE_LIST}")"
fi
if [ -z "${DEVICE}" ]; then
  echo "No available iPhone found. Connect/unlock the device (or pass its UDID)." >&2
  exit 1
fi

echo "[3/4] Installing to ${DEVICE} (device must be unlocked)..."
xcrun devicectl device install app --device "${DEVICE}" "${APP}"
rm -rf build

echo "[4/4] Launching..."
# No `|| true`: a failed launch should surface (nonzero exit), not print "Done".
xcrun devicectl device process launch --device "${DEVICE}" io.github.evanr76.reclaimios
echo "Done."
