#!/usr/bin/env bash
set -euo pipefail

# Runs Arkavo on a simulator and captures a screenshot to test_results.
#
# Usage:
#   automation/sim_run_and_screenshot.sh [UDID]
#
# If UDID is not provided, selects the first iPhone 16 Pro Max on iOS 26.0.

UDID=${1:-}
NAME_TARGET="iPhone 16 Pro Max"
OS_TARGET="26.0"

if [[ -z "${UDID}" ]]; then
  # Try find a device matching name + OS 26.0
  UDID=$(xcrun simctl list devices | awk -F '[()]' -v name="$NAME_TARGET" -v os="$OS_TARGET" "\
    index(\$0, name) && index(\$0, \"(\" os \" )\") { print \$4; exit }") || true
fi

if [[ -z "${UDID}" ]]; then
  echo "No simulator found for ${NAME_TARGET} (${OS_TARGET})." >&2
  exit 1
fi

echo "Using simulator UDID: ${UDID}"

# Boot (idempotent)
xcrun simctl boot "${UDID}" || true
sleep 5

echo "Building Arkavo for ${NAME_TARGET} (iOS ${OS_TARGET})..."
xcodebuild -workspace Arkavo.xcworkspace \
  -scheme Arkavo \
  -destination "platform=iOS Simulator,name=${NAME_TARGET},OS=${OS_TARGET},arch=arm64" \
  -quiet build

# Locate built app
APP_PATH=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/Arkavo-*/Build/Products/Debug-iphonesimulator/Arkavo.app 2>/dev/null | head -n 1)
if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "Failed to locate built Arkavo.app" >&2
  exit 2
fi
echo "App path: ${APP_PATH}"

echo "Installing and launching..."
xcrun simctl install "${UDID}" "${APP_PATH}"
LAUNCH_ARGS="${ARKAVO_LAUNCH_ARGS:-}"
if [[ -z "$LAUNCH_ARGS" && "${SKIP_PASSKEY:-}" == "1" ]]; then
  LAUNCH_ARGS="-ArkavoSkipPasskey"
fi
xcrun simctl launch "${UDID}" com.arkavo.Arkavo ${LAUNCH_ARGS} >/dev/null

mkdir -p test_results
ts=$(date +%Y%m%d-%H%M%S)
shot="test_results/simshot-${UDID}-${ts}.png"
xcrun simctl io "${UDID}" screenshot "${shot}"
echo "Screenshot saved: ${shot}"
