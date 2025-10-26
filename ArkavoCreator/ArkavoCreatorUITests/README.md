# ArkavoCreator UI Tests

Comprehensive UI tests for Epic #139 - OBS-Style Recording with C2PA Provenance

## Test Suites

### 1. RecordingWorkflowUITests
Tests the core recording functionality:
- Navigation to Record view
- UI elements visibility
- Camera position picker
- Start/Stop recording flow
- Pause/Resume functionality
- Library integration

### 2. C2PAProvenanceUITests
Tests C2PA provenance features:
- C2PA badge visibility on recordings
- "View Provenance" context menu
- ProvenanceView UI elements
- Manifest details display
- Copy manifest to clipboard
- End-to-end signing verification

## Prerequisites

### Screen Recording Permission (Required for Recording Tests)

Recording tests require Screen Recording permission to be granted to the test runner.

**To grant permission:**

1. Run any recording test once (it will fail)
2. Open **System Settings** → **Privacy & Security** → **Screen Recording**
3. Look for **ArkavoCreatorUITests-Runner** or **Xcode**
4. Enable the toggle
5. Re-run the tests

**Note**: Permission dialogs may appear during first test run. Grant permissions when prompted.

### c2patool (Required for C2PA Tests)

C2PA provenance tests require `c2patool` to be installed:

```bash
cargo install c2patool
```

Verify installation:
```bash
c2patool --help
```

## Running Tests

### Run All Tests

```bash
xcodebuild test -project ArkavoCreator.xcodeproj -scheme ArkavoCreator -destination 'platform=macOS'
```

### Run Specific Test Suite

```bash
# Recording workflow tests
xcodebuild test -project ArkavoCreator.xcodeproj -scheme ArkavoCreator \
  -destination 'platform=macOS' \
  -only-testing:ArkavoCreatorUITests/RecordingWorkflowUITests

# C2PA provenance tests
xcodebuild test -project ArkavoCreator.xcodeproj -scheme ArkavoCreator \
  -destination 'platform=macOS' \
  -only-testing:ArkavoCreatorUITests/C2PAProvenanceUITests
```

### Run Specific Test

```bash
xcodebuild test -project ArkavoCreator.xcodeproj -scheme ArkavoCreator \
  -destination 'platform=macOS' \
  -only-testing:ArkavoCreatorUITests/RecordingWorkflowUITests/testNavigateToRecordView
```

### Run in Xcode

1. Open `ArkavoCreator.xcodeproj` in Xcode
2. Select the **ArkavoCreator** scheme
3. Press **Cmd+U** to run all tests
4. Or click the diamond icon next to any test method to run individually

## Test Coverage

### UI Navigation ✅
- [x] Navigate to Record view
- [x] Navigate to Library view
- [x] UI elements exist and are accessible

### Recording Controls ✅
- [x] Start Recording button
- [x] Stop Recording button
- [x] Pause/Resume buttons
- [x] Camera toggle
- [x] Microphone toggle
- [x] Camera position picker

### Recording Flow ✅
- [x] Complete recording flow (2-3 seconds)
- [x] Pause and resume recording
- [x] Processing indicator
- [x] Return to ready state
- [x] Recording appears in library

### C2PA Integration ✅
- [x] C2PA badge on signed recordings
- [x] "View Provenance" menu item
- [x] ProvenanceView displays correctly
- [x] Verification status shown
- [x] Manifest details parsed
- [x] Copy manifest to clipboard
- [x] End-to-end signing workflow

## Expected Test Behavior

### When Screen Recording Permission is Denied

Tests will fail with message:
```
⚠️ No recording UI or error message appeared - likely permission denied
Recording did not start - check Screen Recording permission in System Settings
```

**Solution**: Grant Screen Recording permission (see Prerequisites above)

### When c2patool is Not Installed

C2PA tests will pass but report:
```
ℹ️ Recording is unsigned - c2patool may not be installed
Install c2patool for automatic signing: cargo install c2patool
```

Recording functionality works, but files won't have C2PA manifests.

### When Everything is Configured

All tests should pass with green checkmarks ✅:
- Navigation tests: ~2 seconds each
- Recording tests: ~10-30 seconds each (includes actual recording + processing)
- C2PA tests: ~5-10 seconds each

## Debugging Tests

### Enable Verbose Logging

Tests include emoji-based progress indicators:
- 🎬 Test starting
- 📝 Title modified
- 🔴 Recording started
- ⏹️ Recording stopped
- ⏳ Waiting for processing
- ✅ Step completed
- ❌ Error occurred
- ⚠️ Warning

Watch Xcode console for these indicators during test runs.

### Inspect Test Failures

When a test fails:
1. Check the error message in test results
2. Review console logs for emoji indicators
3. Check for permission dialogs
4. Verify c2patool installation for C2PA tests

### Interactive Test Debugging

1. Set breakpoint in test method
2. Run test with **Cmd+U**
3. When breakpoint hits, app is in test state
4. Inspect UI hierarchy with Xcode's View Debugger
5. Print element descriptions: `po app.debugDescription`

## Test Development

### Adding New Tests

1. Add test method to appropriate test class:
```swift
@MainActor
func testMyNewFeature() throws {
    // Arrange
    navigateToRecord()

    // Act
    let myButton = app.buttons["My Feature"]
    myButton.click()

    // Assert
    let result = app.staticTexts["Expected Result"]
    XCTAssertTrue(result.exists, "Expected result should appear")
}
```

2. Use helper methods:
   - `navigateToRecord()` - Navigate to Record view
   - `navigateToLibrary()` - Navigate to Library view
   - `getFirstRecordingCard()` - Get first recording from library

3. Add descriptive print statements with emojis for debugging

### Best Practices

- Use `waitForExistence(timeout:)` for async UI updates
- Check for permissions first with `XCTSkip` if needed
- Use descriptive assertion messages
- Add print statements for test flow visibility
- Handle expected errors gracefully (don't fail test for permission denied)

## Continuous Integration

### GitHub Actions Example

```yaml
- name: Grant Screen Recording Permission
  run: |
    # Automated permission grant requires tccutil or other workarounds
    # See: https://github.com/jacobsalmela/tccutil

- name: Run UI Tests
  run: |
    xcodebuild test \
      -project ArkavoCreator.xcodeproj \
      -scheme ArkavoCreator \
      -destination 'platform=macOS' \
      -resultBundlePath TestResults.xcresult

- name: Upload Test Results
  uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: TestResults.xcresult
```

## Troubleshooting

### Tests Hang or Timeout

- Check for unexpected permission dialogs
- Verify app launches successfully
- Check system resources (disk space, memory)
- Try running tests individually

### UI Elements Not Found

- Verify element identifiers in source code
- Use Xcode's Accessibility Inspector
- Check if UI has loaded (add wait time)
- Print `app.debugDescription` to inspect hierarchy

### Flaky Tests

- Increase timeouts if needed
- Add explicit waits for UI updates
- Check for race conditions
- Ensure tests are isolated (don't depend on each other)

## Support

For issues with tests:
1. Check this README
2. Review test logs and emoji indicators
3. Verify prerequisites (permissions, c2patool)
4. File issue at: https://github.com/arkavo-org/app/issues
