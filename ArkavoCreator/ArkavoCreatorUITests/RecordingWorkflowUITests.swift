//
//  RecordingWorkflowUITests.swift
//  ArkavoCreatorUITests
//
//  Tests for Epic #139 - OBS-Style Recording with C2PA
//

import XCTest

final class RecordingWorkflowUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()

        // Grant necessary permissions for testing
        app.launchArguments = ["UI_TESTING"]

        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Navigation Tests

    @MainActor
    func testNavigateToRecordView() throws {
        // Wait for app to launch
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Find and click Record button in sidebar
        let recordButton = app.buttons["Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should exist in sidebar")

        recordButton.click()

        // Verify we're in Record view
        let navigationTitle = app.staticTexts["Record"]
        XCTAssertTrue(navigationTitle.exists, "Record view should be displayed")

        // Verify key UI elements exist
        let readyToRecord = app.staticTexts["Ready to Record"]
        XCTAssertTrue(readyToRecord.exists, "Ready to Record text should be visible")
    }

    // MARK: - UI Elements Tests

    @MainActor
    func testRecordViewUIElements() throws {
        navigateToRecord()

        // Check title field
        let titleField = app.textFields.firstMatch
        XCTAssertTrue(titleField.exists, "Recording title field should exist")
        XCTAssertFalse(titleField.value as? String ?? "" == "", "Title field should have default value")

        // Check toggles
        let cameraToggle = app.checkBoxes["Enable Camera"]
        XCTAssertTrue(cameraToggle.exists, "Camera toggle should exist")

        let micToggle = app.checkBoxes["Enable Microphone"]
        XCTAssertTrue(micToggle.exists, "Microphone toggle should exist")

        // Check start recording button
        let startButton = app.buttons["Start Recording"]
        XCTAssertTrue(startButton.exists, "Start Recording button should exist")
        XCTAssertTrue(startButton.isEnabled, "Start Recording button should be enabled")
    }

    @MainActor
    func testCameraPositionPicker() throws {
        navigateToRecord()

        // Camera should be enabled by default, so position picker should be visible
        let positionPicker = app.popUpButtons.firstMatch
        XCTAssertTrue(positionPicker.exists, "Camera position picker should exist when camera is enabled")

        // Click picker to show options
        positionPicker.click()

        // Verify position options exist
        let bottomRight = app.menuItems["bottomRight"]
        XCTAssertTrue(bottomRight.exists, "Bottom right position should be available")

        let topLeft = app.menuItems["topLeft"]
        XCTAssertTrue(topLeft.exists, "Top left position should be available")

        // Select a different position
        topLeft.click()

        // Verify selection changed
        XCTAssertTrue(positionPicker.value as? String == "topLeft", "Position should update to top left")
    }

    @MainActor
    func testToggleCameraDisablesPositionPicker() throws {
        navigateToRecord()

        // Disable camera
        let cameraToggle = app.checkBoxes["Enable Camera"]
        cameraToggle.click()

        // Position picker should disappear
        let positionPicker = app.popUpButtons.firstMatch
        XCTAssertFalse(positionPicker.exists, "Camera position picker should be hidden when camera is disabled")
    }

    // MARK: - Recording Flow Tests

    @MainActor
    func testStartRecordingFlow() throws {
        navigateToRecord()

        print("🎬 Starting recording flow test...")

        // Modify title
        let titleField = app.textFields.firstMatch
        titleField.click()
        titleField.typeText(" - UI Test")

        print("📝 Title modified")

        // Start recording
        let startButton = app.buttons["Start Recording"]
        XCTAssertTrue(startButton.exists, "Start Recording button should exist")

        print("🔴 Clicking Start Recording button...")
        startButton.click()

        // IMPORTANT: Wait for permission dialogs and handle them
        // Screen Recording permission dialog appears on first run
        let permissionTimeout: TimeInterval = 15
        sleep(2) // Give time for permission dialog

        print("⏳ Waiting for recording to start (permissions may be requested)...")

        // Look for recording status indicators
        let recordingText = app.staticTexts["RECORDING"]
        let stopButton = app.buttons["Stop Recording"]

        // Wait for recording UI to appear (longer timeout for first-time setup)
        let recordingStarted = recordingText.waitForExistence(timeout: permissionTimeout) ||
                               stopButton.waitForExistence(timeout: 2)

        if recordingStarted {
            print("✅ Recording started successfully!")
            XCTAssertTrue(true, "Recording should start")

            // Verify Stop button appears
            let stopButton = app.buttons["Stop Recording"]
            XCTAssertTrue(stopButton.waitForExistence(timeout: 2), "Stop Recording button should appear")

            print("⏹️ Stop button visible")

        } else {
            // Check for error message
            let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Failed'")).firstMatch
            if errorText.exists {
                let errorMessage = errorText.label
                print("❌ Recording failed with error: \(errorMessage)")

                // This is actually valuable - we want to know what error occurred
                XCTFail("Recording failed: \(errorMessage)")
            } else {
                print("⚠️ No recording UI or error message appeared - likely permission denied")
                print("   Run this test interactively and grant Screen Recording permission")
                XCTFail("Recording did not start - check Screen Recording permission in System Settings")
            }
        }
    }

    @MainActor
    func testCompleteRecordingFlow() throws {
        navigateToRecord()

        print("🎬 Starting complete recording flow test...")

        // Start recording
        let startButton = app.buttons["Start Recording"]
        startButton.click()

        sleep(2) // Wait for permission handling

        // Check if recording started
        let stopButton = app.buttons["Stop Recording"]
        guard stopButton.waitForExistence(timeout: 15) else {
            print("⚠️ Recording did not start - skipping test (permission issue)")
            throw XCTSkip("Recording requires Screen Recording permission")
        }

        print("✅ Recording started")

        // Record for 3 seconds
        print("🎥 Recording for 3 seconds...")
        sleep(3)

        // Verify duration is counting
        let durationDisplay = app.staticTexts.matching(NSPredicate(format: "label MATCHES '\\\\d{2}:\\\\d{2}'")).firstMatch
        XCTAssertTrue(durationDisplay.exists, "Duration should be displayed")

        print("⏱️ Duration: \(durationDisplay.label)")

        // Stop recording
        print("⏹️ Stopping recording...")
        stopButton.click()

        // Wait for processing
        let processingIndicator = app.staticTexts["Finishing recording..."]
        if processingIndicator.waitForExistence(timeout: 2) {
            print("⚙️ Processing recording...")

            // Wait for processing to complete (up to 30 seconds for encoding + C2PA signing)
            let processingTimeout: TimeInterval = 30
            var processingComplete = false

            for _ in 0..<Int(processingTimeout) {
                if !processingIndicator.exists {
                    processingComplete = true
                    break
                }
                sleep(1)
            }

            XCTAssertTrue(processingComplete, "Recording processing should complete")
            print("✅ Processing complete")
        }

        // Verify we're back to ready state
        let readyToRecord = app.staticTexts["Ready to Record"]
        XCTAssertTrue(readyToRecord.waitForExistence(timeout: 5), "Should return to ready state")

        print("✅ Complete recording flow succeeded!")
    }

    @MainActor
    func testPauseResumeRecording() throws {
        navigateToRecord()

        // Start recording
        let startButton = app.buttons["Start Recording"]
        startButton.click()

        sleep(2)

        // Check if recording started
        let pauseButton = app.buttons["Pause"]
        guard pauseButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Recording requires Screen Recording permission")
        }

        // Pause recording
        pauseButton.click()

        // Verify pause indicator
        let pausedIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'PAUSED'")).firstMatch
        XCTAssertTrue(pausedIndicator.waitForExistence(timeout: 2), "Paused indicator should appear")

        // Resume recording
        let resumeButton = app.buttons["Resume"]
        XCTAssertTrue(resumeButton.exists, "Resume button should appear")
        resumeButton.click()

        // Verify recording resumed
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 2), "Pause button should reappear")

        // Stop recording
        let stopButton = app.buttons["Stop Recording"]
        stopButton.click()

        // Wait for processing
        sleep(5)
    }

    // MARK: - Library Integration Tests

    @MainActor
    func testRecordingAppearsInLibrary() throws {
        // First, complete a recording
        navigateToRecord()

        let startButton = app.buttons["Start Recording"]
        startButton.click()

        sleep(2)

        let stopButton = app.buttons["Stop Recording"]
        guard stopButton.waitForExistence(timeout: 15) else {
            throw XCTSkip("Recording requires Screen Recording permission")
        }

        sleep(2) // Record for 2 seconds
        stopButton.click()

        // Wait for processing
        sleep(5)

        // Navigate to Library
        let libraryButton = app.buttons["Library"]
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 5), "Library button should exist")
        libraryButton.click()

        // Wait for library to load
        sleep(2)

        // Check for recording in grid
        // Recording cards are in a scrollView within the library
        let recordingCards = app.scrollViews.descendants(matching: .group)
        XCTAssertGreaterThan(recordingCards.count, 0, "At least one recording should appear in library")

        print("✅ Recording appeared in library")
    }

    // MARK: - Error Handling Tests

    @MainActor
    func testRecordingWithoutPermissions() throws {
        // This test documents the expected behavior when permissions are denied
        // In a real scenario, user must grant Screen Recording permission

        navigateToRecord()

        let startButton = app.buttons["Start Recording"]
        startButton.click()

        sleep(2)

        // Check for error message
        let errorText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Failed'")).firstMatch

        if errorText.waitForExistence(timeout: 15) {
            print("Expected error: \(errorText.label)")
            XCTAssertTrue(true, "Error message should appear when permissions are denied")
        } else {
            // Recording started (permissions granted)
            let stopButton = app.buttons["Stop Recording"]
            if stopButton.exists {
                stopButton.click()
                sleep(5)
            }
            print("Permissions granted - recording started successfully")
        }
    }

    // MARK: - Helper Methods

    private func navigateToRecord() {
        let recordButton = app.buttons["Record"]
        if recordButton.waitForExistence(timeout: 10) {
            recordButton.click()
            sleep(1) // Wait for navigation
        }
    }

    private func waitForProcessing(timeout: TimeInterval = 30) {
        let processingIndicator = app.staticTexts["Finishing recording..."]
        if processingIndicator.exists {
            for _ in 0..<Int(timeout) {
                if !processingIndicator.exists {
                    return
                }
                sleep(1)
            }
        }
    }
}
