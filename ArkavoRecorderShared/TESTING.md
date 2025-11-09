# Continuity Camera Multicamera - Automated Testing Guide

## Overview

This guide explains how to run automated UI tests for the Continuity Camera multicamera feature. These tests help debug discovery issues and verify the remote camera streaming functionality.

## Test Structure

### iOS Tests (Arkavo/ArkavoUITests)
- **RemoteCameraConnectionTests.swift** - Connection and Bonjour discovery tests
- **RemoteCameraTestHelpers.swift** - Shared utilities

### macOS Tests (ArkavoCreator/ArkavoCreatorUITests)
- **RemoteCameraDiscoveryTests.swift** - Server-side discovery and source detection
- **RemoteCameraRecordingTests.swift** - Recording with remote cameras
- **RemoteCameraTestHelpers.swift** - Shared utilities

## Prerequisites

### Physical Devices Required
- ✅ **1 iPhone or iPad** (for iOS tests) - ARKit face/body tracking requires physical device
- ✅ **1 Mac** (for macOS tests)
- ✅ **Devices on same local network** (for Bonjour discovery)

### Simulator Limitations
- ❌ Bonjour discovery between simulators doesn't work reliably
- ❌ ARKit not available in iOS simulator
- ✅ Can test UI layout and manual localhost connections only

## Running Tests

### Option 1: Xcode UI (Recommended for Debugging)

#### iOS Tests (on Physical Device):
1. Open `Arkavo/Arkavo.xcodeproj` in Xcode
2. Select your physical iPhone/iPad as the run destination
3. Press `Cmd+U` or go to Product → Test
4. Alternatively, open Test Navigator (`Cmd+6`) and run specific tests:
   - `testNavigateToRemoteCameraView` - Quick UI check
   - `testBonjourDiscoveryListVisible` - Bonjour discovery (10s wait)
   - `testManualServerEntry` - Manual host/port entry
   - `testStartRemoteCameraWithManualHost` - Connection test
   - `testConnectionErrorHandling` - Error state handling

#### macOS Tests:
1. Open `ArkavoCreator/ArkavoCreator.xcodeproj` in Xcode
2. Press `Cmd+U` or go to Product → Test
3. Key tests to run:
   - `testRemoteCameraServerToggleExists` - UI verification
   - `testRemoteCameraServerInfo` - Server info display
   - `testWaitForRemoteCameraConnection` - **Main discovery test** (30s wait)
   - `testRemoteSourceUpdateFlow` - Monitors source updates (20s)
   - `testRecordWithRemoteCamera` - Full recording workflow

### Option 2: Command Line

#### Build and Test iOS:
```bash
cd /Users/paul/Projects/arkavo/app

# Build for iOS device
xcodebuild -project Arkavo/Arkavo.xcodeproj \
  -scheme Arkavo \
  -sdk iphoneos \
  -destination 'platform=iOS,name=YOUR_DEVICE_NAME' \
  build-for-testing

# Run specific test
xcodebuild -project Arkavo/Arkavo.xcodeproj \
  -scheme Arkavo \
  -sdk iphoneos \
  -destination 'platform=iOS,name=YOUR_DEVICE_NAME' \
  -only-testing:ArkavoUITests/RemoteCameraConnectionTests/testBonjourDiscoveryListVisible \
  test-without-building
```

#### Build and Test macOS:
```bash
cd /Users/paul/Projects/arkavo/app

# Run macOS tests
xcodebuild -project ArkavoCreator/ArkavoCreator.xcodeproj \
  -scheme ArkavoCreator \
  -destination 'platform=macOS' \
  test
```

## Test Execution Workflow for Discovery Debugging

### Step 1: Verify Server Setup (macOS)
```bash
# Run server toggle test
xcodebuild test \
  -only-testing:ArkavoCreatorUITests/RemoteCameraDiscoveryTests/testRemoteCameraServerToggleExists
```
**Expected**: Test passes, logs show "Allow Remote Cameras" toggle found

### Step 2: Verify Bonjour Publishing (macOS)
```bash
# Run Bonjour service test
xcodebuild test \
  -only-testing:ArkavoCreatorUITests/RemoteCameraDiscoveryTests/testBonjourServicePublishing
```
**Expected**: Test passes, server enabled

**Manual verification**:
```bash
# In separate terminal, verify Bonjour service is visible
dns-sd -B _arkavo-remote._tcp local.
```
Should output: `_arkavo-remote._tcp  local.`

### Step 3: Test iOS Discovery (iOS Device)
```bash
# Run Bonjour discovery test on iOS
xcodebuild test \
  -destination 'platform=iOS,name=YOUR_DEVICE_NAME' \
  -only-testing:ArkavoUITests/RemoteCameraConnectionTests/testBonjourDiscoveryListVisible
```
**Expected**:
- Test waits 10 seconds for discovery
- Logs show: "Discovered X nearby Mac(s)"
- If 0 discovered, logs suggest troubleshooting steps

### Step 4: Test Connection Flow (iOS + macOS)

**On macOS** (run first):
```bash
# Start waiting for remote camera
xcodebuild test \
  -only-testing:ArkavoCreatorUITests/RemoteCameraDiscoveryTests/testWaitForRemoteCameraConnection
```
This test waits 30 seconds for an iOS device to connect.

**On iOS** (run while macOS test is waiting):
```bash
# Start remote camera streaming
xcodebuild test \
  -destination 'platform=iOS,name=YOUR_DEVICE_NAME' \
  -only-testing:ArkavoUITests/RemoteCameraConnectionTests/testStartRemoteCameraWithManualHost
```

**Expected**:
- iOS connects to Mac
- macOS test detects remote camera within 30 seconds
- Logs show: "Remote camera detected after X seconds!"

## Reading Test Output

### Success Indicators:
- ✅ `"Remote camera detected after X seconds!"`
- ✅ `"Discovered X nearby Mac(s)"`
- ✅ `"Found remote source: DeviceName-face"`
- ✅ `"Remote camera successfully detected!"`

### Failure Indicators:
- ⚠️ `"No servers discovered via Bonjour"`
- ⚠️ `"No remote camera detected after 30 seconds"`
- ⚠️ `"Remote cameras toggle not found"`
- ⚠️ `"Could not find remote camera UI element"`

### Debug Information:
Tests log extensive debug info:
- 📋 Available UI elements (buttons, text fields, etc.)
- 📊 Discovery status updates every 5 seconds
- 🔄 Source count changes in real-time
- 💡 Troubleshooting suggestions when failures occur

## Common Issues & Solutions

### Issue: "No servers discovered via Bonjour"

**Possible causes:**
1. Mac not running ArkavoCreator
2. Remote cameras toggle OFF on Mac
3. Devices on different networks/VLANs
4. Firewall blocking Bonjour (port 5353 UDP)

**Solutions:**
- Verify Mac test `testRemoteCameraServerInfo` passes
- Check both devices on same Wi-Fi network
- Disable firewall temporarily for testing
- Run `dns-sd -B _arkavo-remote._tcp local.` to verify service

### Issue: "No remote camera detected after 30 seconds"

**Possible causes:**
1. Handshake message not being sent from iOS
2. TCP connection failing (port 5757 blocked)
3. Data reaching server but not propagating to UI
4. RecordViewModel.handleRemoteSourceUpdate not being called

**Debug steps:**
1. Run `testRemoteSourceUpdateFlow` on macOS - monitors UI updates
2. Check macOS Console.app for logs containing "remote camera" or "Bonjour"
3. Verify iOS logs show "Streaming" status
4. Add breakpoints in:
   - `RemoteCameraServer.swift:410` (didUpdateSources)
   - `RecordViewModel.swift:424` (handleRemoteSourceUpdate)
   - `RecordViewModel.swift:435` (setCameraSources)

### Issue: "Remote camera UI element not found"

**Possible causes:**
- UI layout changed
- Test running on wrong screen
- Accessibility identifiers missing

**Solutions:**
- Check test logs for "📋 Available buttons:" output
- Update test predicates to match current UI labels
- Add accessibility identifiers to UI elements

## Test Output Artifacts

### Screenshots
- Automatically captured on test failure
- Saved to Xcode test results (`Cmd+9` → Latest test run → Attachments)
- Named: "Failed Test Screenshot" or test-specific names

### Console Logs
- All tests use emoji prefixes for easy scanning:
  - 🧪 Test start
  - ✅ Success
  - ⚠️ Warning
  - 🔴 Recording start
  - ⏹️ Stop
  - 📱 Device/source info
  - 🔍 Discovery info
  - 💡 Troubleshooting hints

## Manual Testing Complement

While automated tests are running:

### Verify Bonjour Service:
```bash
dns-sd -B _arkavo-remote._tcp local.
# Should show: ADD ... _arkavo-remote._tcp. local.

dns-sd -L "MacName" _arkavo-remote._tcp local.
# Should show: port 5757
```

### Test TCP Connection:
```bash
# From iOS device (in terminal app or Mac):
nc -zv MAC_HOSTNAME 5757
# Should show: Connection to MAC_HOSTNAME port 5757 [tcp/*] succeeded!
```

### Monitor Server Logs:
```bash
# On Mac, open Console.app
# Filter by: process:ArkavoCreator AND category:remote
```

## Next Steps After Testing

If tests reveal issues:

1. **Discovery failing** → Check `RemoteCameraServer.swift:81-89` (Bonjour publishing)
2. **Connection failing** → Check `RemoteCameraStreamer.swift:168` (handshake)
3. **UI not updating** → Check `RecordViewModel.swift:424` (handleRemoteSourceUpdate)
4. **Sources not appearing** → Add logging to `RecordViewModel.swift:435` (setCameraSources)

## Test Maintenance

As UI evolves, update:
- `NSPredicate` patterns in tests to match new labels
- Accessibility identifiers in SwiftUI views
- Wait timeouts if network conditions change
- Helper methods in `RemoteCameraTestHelpers.swift`

## Contributing

When adding new remote camera features:
1. Add corresponding UI tests
2. Use helper methods from `RemoteCameraTestHelpers`
3. Include debug logging (🧪 ✅ ⚠️ prefixes)
4. Update this guide with new test scenarios
