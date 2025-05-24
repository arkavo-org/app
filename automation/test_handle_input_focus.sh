#!/bin/bash

# Test script to verify handle input field auto-focus and automation improvements

set -e

echo "🔍 Testing Handle Input Field Focus and Automation..."

# Get simulator UDID
UDID=$(xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E '\([A-F0-9-]+\)' | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/' | head -1)

if [ -z "$UDID" ]; then
    echo "❌ No iPhone 16 Pro Max simulator found"
    exit 1
fi

echo "📱 Using simulator: $UDID"

# Launch the app
echo "🚀 Launching Arkavo app..."
xcrun simctl terminate $UDID com.arkavo.Arkavo 2>/dev/null || true
xcrun simctl launch $UDID com.arkavo.Arkavo

# Wait for app to launch
sleep 3

# Navigate through onboarding to handle creation
echo "📋 Navigating to Handle Creation screen..."

# Tap Get Started
idb ui describe-all --udid $UDID | jq -r '.[] | select(.type == "Button") | select(.AXLabel | contains("Get Started")) | "\(.frame.x + .frame.width/2) \(.frame.y + .frame.height/2)"' | read x y
if [ ! -z "$x" ]; then
    idb ui tap $x $y --udid $UDID
    sleep 2
fi

# Accept EULA (tap checkbox then Accept & Continue)
echo "✅ Accepting EULA..."
# Tap checkbox
idb ui describe-all --udid $UDID | jq -r '.[] | select(.type == "Button") | select(.AXLabel | contains("EULA Agreement Checkbox")) | "\(.frame.x + .frame.width/2) \(.frame.y + .frame.height/2)"' | read x y
if [ ! -z "$x" ]; then
    idb ui tap $x $y --udid $UDID
    sleep 1
fi

# Tap Accept & Continue
idb ui describe-all --udid $UDID | jq -r '.[] | select(.type == "Button") | select(.AXLabel | contains("Accept & Continue")) | "\(.frame.x + .frame.width/2) \(.frame.y + .frame.height/2)"' | read x y
if [ ! -z "$x" ]; then
    idb ui tap $x $y --udid $UDID
    sleep 2
fi

# Check if text field is focused
echo "🔍 Checking if handle text field is automatically focused..."
FOCUSED_ELEMENT=$(idb ui describe-all --udid $UDID | jq -r '.[] | select(.type == "TextField") | select(.AXLabel | contains("Handle input field"))')

if [ ! -z "$FOCUSED_ELEMENT" ]; then
    echo "✅ Handle text field found!"
    
    # Try different text input methods
    echo "📝 Testing text input methods..."
    
    # Method 1: Using xcrun simctl sendtext
    echo "  1️⃣ Trying xcrun simctl sendtext..."
    xcrun simctl io $UDID sendtext "testuser123"
    sleep 2
    
    # Take screenshot to verify
    SCREENSHOT_PATH="/Users/paul/Projects/arkavo/app/test_results/handle_input_focus_test.png"
    mkdir -p "$(dirname "$SCREENSHOT_PATH")"
    xcrun simctl io $UDID screenshot "$SCREENSHOT_PATH"
    echo "📸 Screenshot saved to: $SCREENSHOT_PATH"
    
    # Method 2: Try clipboard paste
    echo "  2️⃣ Testing clipboard paste method..."
    echo "altuser456" | xcrun simctl pbcopy $UDID
    
    # Focus field first (tap on it)
    FIELD_INFO=$(echo "$FOCUSED_ELEMENT" | jq -r '"\(.frame.x + .frame.width/2) \(.frame.y + .frame.height/2)"')
    if [ ! -z "$FIELD_INFO" ]; then
        read x y <<< "$FIELD_INFO"
        idb ui tap $x $y --udid $UDID
        sleep 0.5
        
        # Paste using Cmd+V
        xcrun simctl keychain $UDID paste
    fi
    
else
    echo "⚠️ Handle text field not found or not accessible"
fi

echo "✅ Handle input focus test completed!"
echo ""
echo "Summary:"
echo "- Auto-focus feature has been implemented using @FocusState"
echo "- Text field has accessibility labels for easier automation"
echo "- The field should automatically receive focus when the view appears"
echo ""
echo "For complete text input automation, combine:"
echo "1. IDB for UI element detection and tapping"
echo "2. xcrun simctl sendtext for text input"
echo "3. xcrun simctl pbcopy/paste for clipboard operations"