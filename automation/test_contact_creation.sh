#!/bin/bash

# Arkavo Contact Creation Test Script
# This script tests the ContactsCreateView functionality

UDID="${UDID:-132B1310-2AF5-45F4-BB8E-CA5A2FEB9481}"
IDB="${IDB:-idb}"
SCREENSHOT_DIR="test_results/contact_creation"

# Create screenshot directory
mkdir -p "$SCREENSHOT_DIR"

# Function to take screenshot
take_screenshot() {
    local name="$1"
    local filename="$SCREENSHOT_DIR/${name}.png"
    xcrun simctl io "$UDID" screenshot "$filename"
    echo "Screenshot saved: $filename"
}

# Function to tap at coordinates
tap() {
    local x="$1"
    local y="$2"
    $IDB ui tap "$x" "$y" --udid "$UDID"
    sleep 0.5
}

# Function to expand menu and tap contacts
navigate_to_contacts() {
    echo "Navigating to Contacts tab..."
    # Tap menu button
    tap 361 1447
    sleep 0.2
    # Tap contacts icon (third from left)
    tap 368 1447
    sleep 2
}

# Function to test Connect Nearby
test_connect_nearby() {
    echo "Testing Connect Nearby..."
    take_screenshot "contacts_view"
    
    # Tap + button to create contact
    tap 52 131
    sleep 2
    take_screenshot "create_contact_view"
    
    # Tap "Connect Nearby" option
    # Coordinates would need to be determined from UI
    # tap X Y
    sleep 2
    take_screenshot "connect_nearby_view"
}

# Function to test Invite Remotely
test_invite_remotely() {
    echo "Testing Invite Remotely..."
    # Navigate back if needed
    # tap back_button_x back_button_y
    
    # Tap "Invite Remotely" option
    # Coordinates would need to be determined from UI
    # tap X Y
    sleep 2
    take_screenshot "invite_remotely_view"
}

# Main test flow
echo "Starting Arkavo Contact Creation Test"
echo "UDID: $UDID"

# Launch app if not already running
echo "Launching Arkavo app..."
xcrun simctl launch "$UDID" com.arkavo.Arkavo
sleep 3

# Take initial screenshot
take_screenshot "01_initial"

# Navigate to contacts
navigate_to_contacts
take_screenshot "02_contacts_tab"

# Test contact creation options
test_connect_nearby
test_invite_remotely

echo "Test completed. Screenshots saved in: $SCREENSHOT_DIR"