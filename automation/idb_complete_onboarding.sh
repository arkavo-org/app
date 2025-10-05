#!/usr/bin/env bash
set -euo pipefail

# Fully automated onboarding/registration flow using IDB.
# Tries to advance through ToS, intro, Face ID/passkeys, registration, and land on home.
# Saves screenshots and a log without requiring manual approval dialogs.
#
# Env:
#   UDID, IDB_BIN (required); IDB_COMPANION_BIN optional.
#   REG_EMAIL/REG_USERNAME/REG_PASSWORD optional; auto-generated if missing.
#
# Usage:
#   export UDID=...; export IDB_BIN="/Users/paul/Library/Python/3.12/bin/idb"
#   automation/idb_complete_onboarding.sh

: "${UDID:?UDID must be set}"
: "${IDB_BIN:?IDB_BIN must be set}"

ts=$(date +%Y%m%d-%H%M%S)
REG_EMAIL=${REG_EMAIL:-"test+${ts}@example.com"}
REG_USERNAME=${REG_USERNAME:-"testuser${ts}"}
REG_PASSWORD=${REG_PASSWORD:-"Password123!"}

mkdir -p test_results
LOG="test_results/idb_onboarding-${ts}.log"
exec > >(tee -a "$LOG") 2>&1

echo "[info] Onboarding start: $ts"
echo "[info] UDID=$UDID"
echo "[info] IDB_BIN=$IDB_BIN"
echo "[info] Using credentials: $REG_EMAIL / $REG_USERNAME"

source "$(dirname "$0")/idb_automation_fix.sh"

snap() {
  local tag=$1
  local p="test_results/onboard-${tag}-${ts}.png"
  IDB screenshot --udid "$UDID" "$p" || true
  echo "[snap] $p"
}

json_cache="/tmp/idb-ui-${ts}.json"
refresh_ui() {
  IDB ui describe-all --udid "$UDID" > "$json_cache" || true
}

has_button() {
  local lbl=$1
  jq -e --arg lbl "$lbl" '.[] | select(.type=="Button") | select(.AXLabel | tostring | contains($lbl))' "$json_cache" >/dev/null 2>&1
}

tap_btn() {
  local lbl=$1
  tap_button "$lbl" || true
}

has_text() {
  local re=$1
  rg -N "${re}" "$json_cache" >/dev/null 2>&1 || jq -e --arg re "$re" '.[] | select(.type=="StaticText") | select(.AXLabel | test($re; "i"))' "$json_cache" >/dev/null 2>&1
}

tap_field_if_exists() {
  local lbl=$1; shift
  if tap_field "$lbl" TextField; then
    type_text "$1"
    return 0
  fi
  return 1
}

echo "[step] Boot + launch"
xcrun simctl boot "$UDID" || true
LAUNCH_ARGS="${ARKAVO_LAUNCH_ARGS:-}"
if [[ -z "$LAUNCH_ARGS" && "${SKIP_PASSKEY:-}" == "1" ]]; then
  LAUNCH_ARGS="-ArkavoSkipPasskey"
fi
xcrun simctl launch "$UDID" com.arkavo.Arkavo ${LAUNCH_ARGS} || true
sleep 1
snap boot

# Iterate through screens
STRICT=${STRICT:-0}
completed=0
for i in $(seq 1 40); do
  refresh_ui
  echo "[loop] iteration=$i"

  # Accept EULA / ToS
  if has_text "Terms of Service|EULA" || has_button "EULA Agreement Checkbox"; then
    has_button "EULA Agreement Checkbox" && tap_btn "EULA Agreement Checkbox"
    has_button "Accept & Continue" && tap_btn "Accept & Continue"
    snap tos
    continue
  fi

  # Intro / Get Started
  if has_button "Get Started" || has_button "Continue"; then
    has_button "Get Started" && tap_btn "Get Started"
    has_button "Continue" && tap_btn "Continue"
    snap intro
    continue
  fi

  # Face ID / biometrics sheet
  if has_button "Enable Face ID" || has_text "Face ID"; then
    # Prefer skipping if Later is available
    if has_button "Later"; then
      tap_btn "Later"
    else
      tap_btn "Enable Face ID"
    fi
    snap faceid
    continue
  fi

  # Registration failure dialog
  if has_text "Failed to complete registration"; then
    has_button "Retry" && tap_btn "Retry"
    has_button "Later" && tap_btn "Later"
    snap regfail
    continue
  fi

  # Passkey prompt
  if has_button "Create Passkey" || has_text "passkey"; then
    if has_button "Later"; then
      tap_btn "Later"
    else
      tap_btn "Create Passkey"
    fi
    snap passkey
    continue
  fi

  # Open registration action if present
  if has_button "Create Account" || has_button "Sign Up" || has_button "Register"; then
    has_button "Create Account" && tap_btn "Create Account"
    has_button "Sign Up" && tap_btn "Sign Up"
    has_button "Register" && tap_btn "Register"
    snap openreg
    continue
  fi

  # Attempt to fill known fields (heuristic)
  if has_text "Email" || has_text "Username|Handle|Name" || has_text "Password"; then
    tap_field_if_exists "Email" "$REG_EMAIL" || true
    tap_field_if_exists "Username" "$REG_USERNAME" || tap_field_if_exists "Handle" "$REG_USERNAME" || tap_field_if_exists "Name" "$REG_USERNAME" || true
    if tap_field "Password" SecureTextField || tap_field "Password" TextField; then
      type_text "$REG_PASSWORD"
    fi
    snap filled
    # Submit
    has_button "Register" && tap_btn "Register"
    has_button "Sign Up" && tap_btn "Sign Up"
    has_button "Continue" && tap_btn "Continue"
    snap submitted
    continue
  fi

  # Detect potential home screen markers and finish
  if has_text "Inbox|Chat|Home|Welcome" || has_button "Compose|New Chat|Settings"; then
    snap complete
    echo "[done] Onboarding appears complete."
    completed=1
    exit 0
  fi

  # Fallback: try a generic Continue/Next if present
  if has_button "Continue" || has_button "Next"; then
    has_button "Continue" && tap_btn "Continue"
    has_button "Next" && tap_btn "Next"
    snap cont
    continue
  fi

  # Nothing matched; take a snapshot and break
  snap idle
  echo "[warn] No known elements matched at iteration $i; stopping."
  break
done

if [[ $completed -eq 0 && $STRICT -eq 1 ]]; then
  echo "[fail] Onboarding did not reach completion in time (strict mode)." >&2
  exit 1
fi

echo "[done] Onboarding flow ended. See screenshots and log: $LOG"
