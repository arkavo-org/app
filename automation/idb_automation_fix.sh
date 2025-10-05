#!/usr/bin/env bash
set -euo pipefail

# IDB UI automation helpers for Arkavo
#
# Prerequisites:
#   - idb_companion (brew install facebook/fb/idb-companion)
#   - idb (pip/pipx install fb-idb) — PATH not required
#   - jq, bc
#
# Usage (no PATH changes needed):
#   export UDID=<simulator-udid>
#   export IDB_BIN="/Users/paul/Library/Python/3.12/bin/idb"   # or: IDB_BIN="python3 -m idb"
#   export IDB_COMPANION_BIN="/opt/homebrew/bin/idb_companion" # optional override
#   source automation/idb_automation_fix.sh
#   tap_button "Get Started"

# Resolve idb executable. Honors $IDB_BIN, else tries PATH, else python module.
resolve_idb_bin() {
  if [[ -n "${IDB_BIN:-}" ]]; then
    echo "$IDB_BIN"
    return 0
  fi
  if command -v idb >/dev/null 2>&1; then
    echo "idb"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1 && python3 - <<'PY'
import importlib.util, sys
sys.exit(0 if importlib.util.find_spec('idb') else 1)
PY
  then
    echo "python3 -m idb"
    return 0
  fi
  return 1
}

# Resolve idb_companion. Honors $IDB_COMPANION_BIN, else tries common Homebrew paths, else PATH.
resolve_idb_companion_bin() {
  if [[ -n "${IDB_COMPANION_BIN:-}" ]]; then
    echo "$IDB_COMPANION_BIN"
    return 0
  fi
  for p in /opt/homebrew/bin/idb_companion /usr/local/bin/idb_companion; do
    if [[ -x "$p" ]]; then
      echo "$p"
      return 0
    fi
  done
  if command -v idb_companion >/dev/null 2>&1; then
    command -v idb_companion
    return 0
  fi
  return 1
}

IDB_BIN_RESOLVED="$(resolve_idb_bin || true)"
IDB_COMPANION_BIN_RESOLVED="$(resolve_idb_companion_bin || true)"

# Thin wrappers to invoke the resolved tools correctly, including the python -m path.
IDB() {
  if [[ -z "${IDB_BIN_RESOLVED}" ]]; then
    echo "idb is not available; set IDB_BIN to '/Users/paul/Library/Python/3.12/bin/idb' or 'python3 -m idb'" >&2
    return 127
  fi
  if [[ "$IDB_BIN_RESOLVED" == "python3 -m idb" ]]; then
    python3 -m idb "$@"
  elif [[ "$IDB_BIN_RESOLVED" == *" -m idb" ]]; then
    # When IDB_BIN is like "/path/to/python3 -m idb"
    local py
    py="${IDB_BIN_RESOLVED% -m idb}"
    "$py" -m idb "$@"
  else
    "$IDB_BIN_RESOLVED" "$@"
  fi
}

IDB_COMPANION() {
  if [[ -z "${IDB_COMPANION_BIN_RESOLVED}" ]]; then
    echo "idb_companion is not available; set IDB_COMPANION_BIN to its full path (e.g. /opt/homebrew/bin/idb_companion)" >&2
    return 127
  fi
  "${IDB_COMPANION_BIN_RESOLVED}" "$@"
}

require_tools() {
  # Validate jq and bc
  for t in jq bc; do
    if ! command -v "$t" >/dev/null 2>&1; then
      echo "Missing tool: $t" >&2
      return 1
    fi
  done
  # Validate idb (resolved) and companion
  if [[ -z "$IDB_BIN_RESOLVED" ]]; then
    echo "Missing tool: idb (set IDB_BIN or ensure python3 -m idb works)" >&2
    return 1
  fi
  if [[ -z "$IDB_COMPANION_BIN_RESOLVED" ]]; then
    echo "Missing tool: idb_companion (set IDB_COMPANION_BIN or install via Homebrew)" >&2
    return 1
  fi
}

ensure_companion() {
  : "${UDID:?UDID environment variable must be set}"
  # Start companion if not already connected
  if ! IDB list-targets | grep -q "$UDID"; then
    nohup IDB_COMPANION --udid "$UDID" >/dev/null 2>&1 &
    sleep 1
    IDB connect "$UDID" >/dev/null
  fi
}

# Find a UI element by AXLabel containing the query (case-sensitive)
# Args: $1 = accessibility label substring, $2 = type (optional, defaults to Button)
find_element_json() {
  local label=${1:?}
  local type=${2:-Button}
  IDB ui describe-all --udid "$UDID" \
    | jq -r --arg t "$type" --arg lbl "$label" '.[] | select(.type == $t) | select(.AXLabel | tostring | contains($lbl))'
}

# Wait for an element to appear by label and type within timeout seconds
wait_for_element() {
  local label=${1:?}
  local type=${2:-Button}
  local timeout=${3:-10}
  local i=0
  while (( i < timeout )); do
    if find_element_json "$label" "$type" | grep -q '"type"'; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  return 1
}

# Tap element from a JSON blob (center)
tap_element_json_center() {
  local el_json=${1:?}
  local x y w h cx cy
  x=$(echo "$el_json" | jq -r '.frame.x')
  y=$(echo "$el_json" | jq -r '.frame.y')
  w=$(echo "$el_json" | jq -r '.frame.width')
  h=$(echo "$el_json" | jq -r '.frame.height')
  cx=$(printf '%.0f' "$(echo "$x + $w/2" | bc -l)")
  cy=$(printf '%.0f' "$(echo "$y + $h/2" | bc -l)")
  IDB ui tap "$cx" "$cy" --udid "$UDID"
}

# Tap a TextField/SecureTextField by label (substring)
tap_field() {
  require_tools || return 1
  ensure_companion
  local label=${1:?Field label required}
  local type=${2:-TextField}
  local el
  el=$(find_element_json "$label" "$type")
  if [[ -z "$el" && "$type" == "TextField" ]]; then
    # Try secure field as fallback
    el=$(find_element_json "$label" "SecureTextField")
  fi
  if [[ -z "$el" ]]; then
    echo "Field not found: $label" >&2
    return 2
  fi
  tap_element_json_center "$el"
}

# Type text into the currently focused field
type_text() {
  local text=${1:?}
  IDB ui text "$text" --udid "$UDID"
}

# Tap the center of an element with the given AXLabel (substring match)
tap_button() {
  require_tools || return 1
  ensure_companion

  local label=${1:?Button label required}
  local el
  el=$(find_element_json "$label" Button)
  if [[ -z "$el" ]]; then
    echo "Button not found: $label" >&2
    return 2
  fi

  local x y w h cx cy
  x=$(echo "$el" | jq -r '.frame.x')
  y=$(echo "$el" | jq -r '.frame.y')
  w=$(echo "$el" | jq -r '.frame.width')
  h=$(echo "$el" | jq -r '.frame.height')
  # Compute integer center coordinates (round to nearest)
  cx=$(printf '%.0f' "$(echo "$x + $w/2" | bc -l)")
  cy=$(printf '%.0f' "$(echo "$y + $h/2" | bc -l)")

  IDB ui tap "$cx" "$cy" --udid "$UDID"
}

# Toggle a switch/checkbox by label
check_toggle() {
  require_tools || return 1
  ensure_companion
  local label=${1:?Toggle label required}
  local el
  el=$(find_element_json "$label" "Switch")
  if [[ -z "$el" ]]; then
    echo "Toggle not found: $label" >&2
    return 2
  fi
  local x y w h cx cy
  x=$(echo "$el" | jq -r '.frame.x')
  y=$(echo "$el" | jq -r '.frame.y')
  w=$(echo "$el" | jq -r '.frame.width')
  h=$(echo "$el" | jq -r '.frame.height')
  cx=$(printf '%.0f' "$(echo "$x + $w/2" | bc -l)")
  cy=$(printf '%.0f' "$(echo "$y + $h/2" | bc -l)")
  IDB ui tap "$cx" "$cy" --udid "$UDID"
}

export -f tap_button
export -f check_toggle
