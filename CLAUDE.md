# CLAUDE.md - Arkavo Project Guide

## Build/Test Commands
- Open workspace: `open Arkavo.xcworkspace`
- Build main app: `xcodebuild -workspace Arkavo.xcworkspace -scheme Arkavo -destination "platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64" -quiet build`
- Test all: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64'`
- Test single class: `xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max,OS=18.4,arch=arm64' -only-testing:ArkavoTests/ArkavoTests`
- Format code: `swiftformat --swiftversion 6.0 .`
- Package tests: `cd ArkavoSocial && swift test`

## iOS Simulator Testing Setup

### Prerequisites for MCP iOS Simulator Tools
- Install Facebook IDB companion: `brew install facebook/fb/idb-companion`
- IDB Python client should be installed (check with `which idb`)

### Running Tests with iOS Simulator
1. Boot simulator: `xcrun simctl boot "iPhone 16 Pro Max"`
2. Build app: Use build command above
3. Install app: `xcrun simctl install booted /Users/paul/Library/Developer/Xcode/DerivedData/Arkavo-*/Build/Products/Debug-iphonesimulator/Arkavo.app`
4. Launch app: `xcrun simctl launch booted com.arkavo.Arkavo`

### Using MCP iOS Simulator Tools
- The `mcp-ios-simulator` tool requires IDB companion to be installed
- If MCP tools fail with "undefined" errors, ensure IDB companion is installed
- Screenshot: `mcp__ios-simulator__screenshot` with `output_path` and `udid` parameters
- UI interaction tools may require additional setup

### Simulator Screenshot Management
- Screenshots taken with the mcp simulator should be in the test_results directory not Downloads

### Troubleshooting MCP iOS Simulator Tools
If MCP tools fail with "undefined" error:
1. Start IDB companion manually: `idb_companion --udid [SIMULATOR_UDID] > /dev/null 2>&1 &`
2. Connect IDB to simulator: `idb connect [SIMULATOR_UDID]`
3. Verify connection: `idb list-targets | grep [SIMULATOR_UDID]`
4. Use IDB directly as fallback (see below)

### Fallback Commands (if MCP tools fail)
- Screenshot: `xcrun simctl io [UDID] screenshot [path]` OR `idb screenshot --udid [UDID] [path]`
- Get simulator UDID: `xcrun simctl list devices | grep "iPhone 16 Pro Max" | grep -E '\([A-F0-9-]+\)' | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'`
- List booted devices: `xcrun simctl list devices booted`
- UI interaction with IDB:
  - Describe all UI elements: `idb ui describe-all --udid [UDID]`
  - Tap at coordinates: `idb ui tap [x] [y] --udid [UDID]`
  - Type text: `idb ui type "[text]" --udid [UDID]`
  - Swipe: `idb ui swipe [x1] [y1] [x2] [y2] --udid [UDID]`

### IDB Button Interaction Solution (IMPORTANT)
When using IDB for button taps, especially with multiple monitors:
1. **Always tap at element centers**: Buttons require taps at their exact center for reliable interaction
2. **Use accessibility data**: Find elements via `idb ui describe-all` and filter by AXLabel
3. **Calculate center coordinates**: `center_x = x + width/2`, `center_y = y + height/2`
4. **Automation script available**: `Arkavo/automation_scripts/idb_automation_fix.sh` provides reusable functions:
   - `tap_button "Button Label"` - Find and tap button by accessibility label
   - `check_toggle "Toggle Label"` - Handle checkboxes and toggles
5. **Example working tap**: 
   ```bash
   # Get button info
   button=$(idb ui describe-all --udid $UDID | jq -r '.[] | select(.type == "Button") | select(.AXLabel | contains("Get Started"))')
   # Extract and calculate center
   x=$(echo "$button" | jq -r '.frame.x')
   y=$(echo "$button" | jq -r '.frame.y')
   width=$(echo "$button" | jq -r '.frame.width')
   height=$(echo "$button" | jq -r '.frame.height')
   center_x=$(echo "$x + $width/2" | bc)
   center_y=$(echo "$y + $height/2" | bc)
   # Tap at center
   idb ui tap $center_x $center_y --udid $UDID
   ```

### P2P Testing Setup
- Create second simulator: `xcrun simctl create "iPhone 16 Pro Max Clone" "iPhone 16 Pro Max" iOS18.4`
- Boot, install, and launch app on both simulators for P2P testing

## Workflow Practices
- When create a issue that has a related screenshot, add it to the issue