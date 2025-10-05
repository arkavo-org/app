#!/usr/bin/env bash
set -euo pipefail

# Launch Arkavo on the simulator, tap "Get Started" via IDB, and capture a screenshot.
#
# Requirements:
#   - UDID env var set to simulator UDID
#   - IDB_BIN set to either the idb script path or "python3 -m idb"
#   - IDB_COMPANION_BIN optional (will auto-detect common brew paths)
#   - jq, bc installed
#
# Usage:
#   export UDID=98CA4156-9D14-4DFC-9E8B-21F21AA1BEC9
#   export IDB_BIN="/Users/paul/Library/Python/3.12/bin/idb"   # or: "python3 -m idb"
#   export IDB_COMPANION_BIN="/opt/homebrew/bin/idb_companion" # optional
#   automation/idb_get_started_flow.sh [--strict] [--label "Get Started"]
#
#   --strict  Fail if the button is not found/tapped.
#   --label   Override the button label (default: "Get Started").

STRICT=0
LABEL="Get Started"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict)
      STRICT=1; shift ;;
    --label)
      LABEL=${2:?}; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

: "${UDID:?UDID environment variable must be set}"
: "${IDB_BIN:?IDB_BIN must be set to idb path or 'python3 -m idb'}"

mkdir -p test_results
ts=$(date +%Y%m%d-%H%M%S)
LOGFILE="test_results/idb_flow-${ts}.log"
SHOT="test_results/idb-after-get-started-${ts}.png"

exec > >(tee -a "$LOGFILE") 2>&1
echo "[info] Starting IDB flow at $ts"
echo "[info] UDID=$UDID"
echo "[info] IDB_BIN=$IDB_BIN"
echo "[info] IDB_COMPANION_BIN=${IDB_COMPANION_BIN:-<auto>}"

# Source helpers (resolves IDB/companion, ensures connect, integer tap, etc.)
source "$(dirname "$0")/idb_automation_fix.sh"

echo "[step] Booting simulator (idempotent)"
xcrun simctl boot "$UDID" || true
sleep 2

echo "[step] Launching app com.arkavo.Arkavo"
xcrun simctl launch "$UDID" com.arkavo.Arkavo || true
sleep 1

echo "[step] Tapping button: $LABEL"
if tap_button "$LABEL"; then
  echo "[ok] Tap succeeded"
else
  echo "[warn] Button not found or tap failed: $LABEL"
  if [[ $STRICT -eq 1 ]]; then
    echo "[fail] Strict mode enabled; exiting with error" >&2
    exit 3
  fi
fi

echo "[step] Capturing screenshot to $SHOT"
IDB screenshot --udid "$UDID" "$SHOT"
echo "[done] Flow complete. Screenshot: $SHOT"
echo "[info] Log saved to: $LOGFILE"

