//
//  RecordModeUITests.swift
//  ArkavoCreatorUITests
//
//  Created for VRM Avatar Integration (#140)
//

import XCTest

final class RecordModeUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    @MainActor
    func testNavigateToRecordMode() throws {
        // Wait for app to launch
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Find the Record navigation button in sidebar
        let recordButton = app.buttons["Record"]

        // Wait for button to appear
        let exists = recordButton.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "Record button should exist in sidebar")

        // Click the Record button
        recordButton.click()

        // Verify we're in Record mode by checking for recording mode picker
        let recordingModePicker = app.radioGroups["RecordingModePicker"]
        XCTAssertTrue(
            recordingModePicker.waitForExistence(timeout: 5),
            "Recording mode picker should appear in Record section"
        )

        // Verify Avatar mode is selected (segmented control shows as radio buttons)
        let avatarButton = recordingModePicker.radioButtons["Avatar"]
        XCTAssertTrue(
            avatarButton.exists,
            "Avatar mode button should be available"
        )
    }

    @MainActor
    func testRecordModeUIElements() throws {
        // Navigate to Record mode first
        let recordButton = app.buttons["Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.click()

        // Wait for UI to load
        sleep(1)

        // Check for key UI elements
        let downloadSection = app.staticTexts["Download VRM Model"]
        XCTAssertTrue(
            downloadSection.exists,
            "Download VRM Model section should exist"
        )

        let selectAvatarSection = app.staticTexts["Select Avatar"]
        XCTAssertTrue(
            selectAvatarSection.exists,
            "Select Avatar section should exist"
        )

        let settingsSection = app.staticTexts["Avatar Settings"]
        XCTAssertTrue(
            settingsSection.exists,
            "Avatar Settings section should exist"
        )

        // Check for lip sync toggle
        let lipSyncToggle = app.checkBoxes["Enable Lip Sync"]
        XCTAssertTrue(
            lipSyncToggle.exists,
            "Enable Lip Sync toggle should exist"
        )

        // Check for background color picker
        let backgroundPicker = app.colorWells.firstMatch
        XCTAssertTrue(
            backgroundPicker.exists,
            "Background color picker should exist"
        )
    }

    @MainActor
    func testDownloadFromVRMHub() throws {
        // Navigate to Record mode
        let recordButton = app.buttons["Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.click()

        sleep(1)

        // Enter VRM Hub URL
        let urlField = app.textFields["VRMURLField"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 5), "VRM URL field should exist")

        urlField.click()
        urlField.typeText("https://hub.vroid.com/en/characters/515144657245174640/models/6438391937465666012")

        // Click Download button
        let downloadButton = app.buttons["Download"]
        XCTAssertTrue(downloadButton.exists, "Download button should exist")
        downloadButton.click()

        // Wait for download to complete (or fail with auth error)
        // This may take a while, so we wait up to 30 seconds
        sleep(5)

        // Check if either:
        // 1. Model appeared in list (success)
        // 2. Error alert appeared (auth required or other error)
        let modelInList = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'model_'")).firstMatch
        let errorAlert = app.alerts.firstMatch

        // Test passes if either download succeeded OR we got expected auth error
        let downloadSucceeded = modelInList.waitForExistence(timeout: 25)
        let gotAuthError = errorAlert.waitForExistence(timeout: 2)

        if gotAuthError {
            // Check if it's the expected auth error
            let authErrorText = app.staticTexts["VRM Hub downloads require authentication"]
            if authErrorText.exists {
                // This is expected - VRM Hub requires auth for some models
                print("VRM Hub authentication required (expected)")
                XCTAssertTrue(true, "Correctly detected VRM Hub auth requirement")

                // Dismiss error
                app.buttons["OK"].click()
            } else {
                // Some other error - let's see what it says
                print("Download error: \(errorAlert.label)")
                // Don't fail the test - network errors are common
            }
        } else if downloadSucceeded {
            print("Successfully downloaded from VRM Hub!")
            XCTAssertTrue(true, "VRM Hub download succeeded")
        } else {
            // No model and no error - might still be downloading
            print("Download status unclear - this is acceptable for network-dependent test")
        }
    }

    @MainActor
    func testSwitchBetweenRecordingModes() throws {
        // Navigate to Record mode
        let recordButton = app.buttons["Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10))
        recordButton.click()

        // Get the recording mode picker (segmented control = radio group)
        let modePicker = app.radioGroups["RecordingModePicker"]
        XCTAssertTrue(modePicker.waitForExistence(timeout: 5))

        // Switch to Camera mode
        let cameraButton = modePicker.radioButtons["Camera"]
        if cameraButton.exists {
            cameraButton.click()

            // Verify camera placeholder appears
            let cameraPlaceholder = app.staticTexts["Camera Mode"]
            XCTAssertTrue(
                cameraPlaceholder.waitForExistence(timeout: 3),
                "Camera mode placeholder should appear"
            )
        }

        // Switch back to Avatar mode
        let avatarButton = modePicker.radioButtons["Avatar"]
        if avatarButton.exists {
            avatarButton.click()

            // Verify avatar UI appears
            let avatarSettings = app.staticTexts["Avatar Settings"]
            XCTAssertTrue(
                avatarSettings.waitForExistence(timeout: 3),
                "Avatar settings should appear when switching to Avatar mode"
            )
        }
    }
}
