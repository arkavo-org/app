#!/usr/bin/env bash
set -euo pipefail

# Drives Arkavo registration via IDB. Best-effort, adaptive labels.
# Steps:
#  - Launch app
#  - Tap Get Started / Continue
#  - Tap Create Account / Sign Up / Register
#  - Fill Email, Username, Password
#  - Accept Terms (if present)
#  - Submit registration
#  - Capture screenshots along the way
#
# Env:
#   UDID                  - simulator UDID (required)
#   IDB_BIN               - path to idb or "python3 -m idb" (required)
#   IDB_COMPANION_BIN     - optional, companion path
#   REG_EMAIL             - email to use (default: test+<ts>@example.com)
#   REG_USERNAME          - username to use (default: testuser<ts>)
#   REG_PASSWORD          - password to use (default: Password123!)
#
# Usage:
#   export UDID=...
#   export IDB_BIN="/Users/paul/Library/Python/3.12/bin/idb"
#   export IDB_COMPANION_BIN="/opt/homebrew/bin/idb_companion"
#   automation/idb_registration_flow.sh

: "${UDID:?UDID must be set}"
: "${IDB_BIN:?IDB_BIN must be set}"

ts=$(date +%Y%m%d-%H%M%S)
REG_EMAIL=${REG_EMAIL:-"test+${ts}@example.com"}
REG_USERNAME=${REG_USERNAME:-"testuser${ts}"}
REG_PASSWORD=${REG_PASSWORD:-"Password123!"}

mkdir -p test_results
LOG="test_results/idb_registration-${ts}.log"
exec > >(tee -a "$LOG") 2>&1

echo "[info] Registration flow starting: $ts"
echo "[info] UDID=$UDID"
echo "[info] IDB_BIN=${IDB_BIN}"
echo "[info] Using credentials: $REG_EMAIL / $REG_USERNAME"

source "$(dirname "$0")/idb_automation_fix.sh"

screenshot() {
  local name=$1; shift
  local path="test_results/${name}-${ts}.png"
  IDB screenshot --udid "$UDID" "$path" || true
  echo "[snap] $path"
}

echo "[step] Ensure simulator boot + app launched"
xcrun simctl boot "$UDID" || true
LAUNCH_ARGS="${ARKAVO_LAUNCH_ARGS:-}"
if [[ -z "$LAUNCH_ARGS" && "${SKIP_PASSKEY:-}" == "1" ]]; then
  LAUNCH_ARGS="-ArkavoSkipPasskey"
fi
xcrun simctl launch "$UDID" com.arkavo.Arkavo ${LAUNCH_ARGS} || true
sleep 1
screenshot "00-launch"

echo "[step] Accept Terms of Service if present"
if wait_for_element "EULA Agreement Checkbox" Button 3; then
  tap_button "EULA Agreement Checkbox" || true
fi
if wait_for_element "Accept & Continue" Button 3; then
  tap_button "Accept & Continue" || true
fi
screenshot "00b-after-accept-tos"

tap_first() {
  local labels=("$@")
  for lbl in "${labels[@]}"; do
    if wait_for_element "$lbl" Button 2 && tap_button "$lbl"; then
      echo "[ok] Tapped: $lbl"
      return 0
    fi
  done
  echo "[warn] None of the labels found: ${labels[*]}"
  return 1
}

echo "[step] Navigate from intro"
tap_first "Get Started" "Continue" || true
screenshot "01-after-get-started"

echo "[step] Handle Face ID setup if present"
tap_first "Enable Face ID" "Use Face ID" || true
screenshot "01b-after-faceid"

echo "[step] Open registration"
tap_first "Create Account" "Sign Up" "Register" || true
screenshot "02-after-open-registration"

echo "[step] Fill Email"
if tap_field "Email" TextField; then
  type_text "$REG_EMAIL"
  echo "[ok] Entered email"
else
  echo "[warn] Email field not found"
fi
screenshot "03-after-email"

echo "[step] Fill Username"
if tap_field "Username" TextField || tap_field "Handle" TextField || tap_field "Name" TextField; then
  type_text "$REG_USERNAME"
  echo "[ok] Entered username"
else
  echo "[warn] Username field not found"
fi
screenshot "04-after-username"

echo "[step] Fill Password"
if tap_field "Password" SecureTextField || tap_field "Password" TextField; then
  type_text "$REG_PASSWORD"
  echo "[ok] Entered password"
else
  echo "[warn] Password field not found"
fi
screenshot "05-after-password"

echo "[step] Accept Terms if present"
if check_toggle "Terms" || check_toggle "Privacy" || tap_first "I Agree" "Accept"; then
  echo "[ok] Terms handled"
else
  echo "[info] No terms toggle/button detected"
fi
screenshot "06-after-terms"

echo "[step] Submit registration"
tap_first "Register" "Sign Up" "Create Account" "Continue" "Next" || true
screenshot "07-after-submit"

echo "[done] Registration flow complete. Log: $LOG"
