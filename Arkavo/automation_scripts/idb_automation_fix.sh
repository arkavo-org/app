#!/bin/bash

# IDB Automation Fix for iOS Simulator Button Interactions
# This script demonstrates the working approach for IDB tap commands

UDID="132B1310-2AF5-45F4-BB8E-CA5A2FEB9481"

# Function to find button coordinates using accessibility labels
find_button() {
    local label="$1"
    idb ui describe-all --udid "$UDID" | jq -r ".[] | select(.type == \"Button\") | select(.AXLabel | contains(\"$label\")) | {x: .frame.x, y: .frame.y, width: .frame.width, height: .frame.height, label: .AXLabel}"
}

# Function to tap at center of element
tap_center() {
    local x=$1
    local y=$2
    local width=$3
    local height=$4
    local center_x=$(echo "$x + $width/2" | bc)
    local center_y=$(echo "$y + $height/2" | bc)
    
    echo "Tapping at ($center_x, $center_y)"
    idb ui tap "$center_x" "$center_y" --udid "$UDID"
}

# Function to find and tap button by label
tap_button() {
    local label="$1"
    echo "Looking for button: $label"
    
    local button_info=$(find_button "$label")
    if [ -z "$button_info" ]; then
        echo "Button '$label' not found"
        return 1
    fi
    
    local x=$(echo "$button_info" | jq -r '.x')
    local y=$(echo "$button_info" | jq -r '.y')
    local width=$(echo "$button_info" | jq -r '.width')
    local height=$(echo "$button_info" | jq -r '.height')
    
    tap_center "$x" "$y" "$width" "$height"
}

# Function to find and check toggle/checkbox
check_toggle() {
    local label="$1"
    echo "Looking for toggle: $label"
    
    local toggle_info=$(idb ui describe-all --udid "$UDID" | jq -r ".[] | select(.type == \"Switch\" or .type == \"Toggle\") | select(.AXLabel | contains(\"$label\")) | {x: .frame.x, y: .frame.y, width: .frame.width, height: .frame.height, label: .AXLabel, value: .AXValue}")
    
    if [ -z "$toggle_info" ]; then
        echo "Toggle '$label' not found"
        return 1
    fi
    
    local x=$(echo "$toggle_info" | jq -r '.x')
    local y=$(echo "$toggle_info" | jq -r '.y')
    local width=$(echo "$toggle_info" | jq -r '.width')
    local height=$(echo "$toggle_info" | jq -r '.height')
    local value=$(echo "$toggle_info" | jq -r '.value')
    
    if [ "$value" != "1" ]; then
        tap_center "$x" "$y" "$width" "$height"
        echo "Toggled checkbox"
    else
        echo "Checkbox already checked"
    fi
}

# Main automation flow
echo "Starting Arkavo registration automation..."

# Example usage:
# tap_button "Get Started"
# sleep 2
# check_toggle "I have read and agree"
# tap_button "Accept & Continue"

echo "Script ready for use. Call the functions as needed."