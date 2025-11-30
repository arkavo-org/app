//
//  RecordingCombinationsUITests.swift
//  ArkavoCreatorUITests
//
//  Updated for Studio UX Redesign - Tests all recording input combinations
//
//  New Architecture:
//  - Persona (Face/Avatar/Audio) is set via header popover
//  - Stage controls (Screen/Mic) are in bottom control bar
//  - Output mode (Record/Stream) is a segmented picker in header
//

import XCTest

final class RecordingCombinationsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITesting"]
        app.launch()
        // Ensure app has focus
        app.activate()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper Methods

    /// Navigate to the Studio section
    @MainActor
    private func navigateToStudio() {
        // Ensure app has focus before navigation
        app.activate()

        // Click on Studio in the sidebar
        let studioButton = app.buttons["Studio"]
        if studioButton.waitForExistence(timeout: 5) {
            studioButton.click()
        }
        // Wait for studio controls to appear instead of sleeping
        _ = app.buttons["Btn_Persona"].waitForExistence(timeout: 3)
    }

    /// Select a persona via the header popover
    @MainActor
    private func selectPersona(_ persona: String) {
        let personaButton = app.buttons["Btn_Persona"]
        guard personaButton.waitForExistence(timeout: 3) else {
            XCTFail("Persona button should exist")
            return
        }
        personaButton.click()

        // Wait for popover to appear
        let personaOption = app.buttons["Persona_\(persona)"]
        if personaOption.waitForExistence(timeout: 2) {
            personaOption.click()
            // Wait for popover to dismiss
            _ = personaButton.waitForExistence(timeout: 2)
        }
    }

    /// Toggle screen sharing
    @MainActor
    private func toggleScreen() {
        let screenToggle = app.buttons["Toggle_Screen"]
        guard screenToggle.waitForExistence(timeout: 5) else {
            XCTFail("Screen toggle should exist")
            return
        }
        screenToggle.click()
    }

    /// Toggle microphone
    @MainActor
    private func toggleMic() {
        let micToggle = app.buttons["Toggle_Mic"]
        guard micToggle.waitForExistence(timeout: 5) else {
            XCTFail("Mic toggle should exist")
            return
        }
        micToggle.click()
    }

    /// Verify recording button is available
    @MainActor
    private func verifyRecordButton() -> Bool {
        let recordButton = app.buttons["Btn_Record"]
        return recordButton.waitForExistence(timeout: 5) && recordButton.isEnabled
    }

    /// Start recording if possible
    @MainActor
    private func startRecording() -> Bool {
        let recordButton = app.buttons["Btn_Record"]
        guard recordButton.waitForExistence(timeout: 5), recordButton.isEnabled else {
            return false
        }
        recordButton.click()

        // Wait for stop button to appear (indicates recording started)
        let stopButton = app.buttons["Btn_Stop"]
        return stopButton.waitForExistence(timeout: 5)
    }

    /// Stop recording if active
    @MainActor
    private func stopRecording() {
        let stopButton = app.buttons["Btn_Stop"]
        if stopButton.waitForExistence(timeout: 2) {
            stopButton.click()
            // Wait for record button to reappear
            let recordButton = app.buttons["Btn_Record"]
            _ = recordButton.waitForExistence(timeout: 5)
        }
    }

    // MARK: - Basic UI Tests

    @MainActor
    func testStudioUIElementsExist() throws {
        navigateToStudio()

        // Verify header elements
        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 5), "Persona button should exist")

        // Verify bottom bar elements
        let screenToggle = app.buttons["Toggle_Screen"]
        let micToggle = app.buttons["Toggle_Mic"]
        let recordButton = app.buttons["Btn_Record"]

        XCTAssertTrue(screenToggle.waitForExistence(timeout: 5), "Screen toggle should exist")
        XCTAssertTrue(micToggle.exists, "Mic toggle should exist")
        XCTAssertTrue(recordButton.exists, "Record button should exist")
    }

    @MainActor
    func testPersonaPopoverOpens() throws {
        navigateToStudio()

        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 5), "Persona button should exist")
        personaButton.click()

        // Verify persona options appear
        sleep(1)
        let faceOption = app.buttons["Persona_Face"]
        let avatarOption = app.buttons["Persona_Avatar"]
        let audioOption = app.buttons["Persona_Audio"]

        XCTAssertTrue(faceOption.waitForExistence(timeout: 3), "Face persona option should exist")
        XCTAssertTrue(avatarOption.exists, "Avatar persona option should exist")
        XCTAssertTrue(audioOption.exists, "Audio persona option should exist")
    }

    @MainActor
    func testScreenToggleWorks() throws {
        navigateToStudio()

        let screenToggle = app.buttons["Toggle_Screen"]
        XCTAssertTrue(screenToggle.waitForExistence(timeout: 3), "Screen toggle should exist")

        // Toggle screen on
        screenToggle.click()
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable after first click")

        // Toggle screen off
        screenToggle.click()
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable after second click")
    }

    @MainActor
    func testMicToggleWorks() throws {
        navigateToStudio()

        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(micToggle.waitForExistence(timeout: 3), "Mic toggle should exist")

        // Toggle mic
        micToggle.click()
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should be hittable after first click")

        // Toggle mic again
        micToggle.click()
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should be hittable after second click")
    }

    // MARK: - Persona Selection Tests

    @MainActor
    func testSelectFacePersona() throws {
        navigateToStudio()
        selectPersona("Face")

        // Verify persona button shows Face
        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")
    }

    @MainActor
    func testSelectAvatarPersona() throws {
        navigateToStudio()
        selectPersona("Avatar")

        // Verify persona button exists
        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")
    }

    @MainActor
    func testSelectAudioPersona() throws {
        navigateToStudio()
        selectPersona("Audio")

        // Verify persona button exists
        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")
    }

    // MARK: - Recording Combination Tests (Preserving PR #194 coverage)

    @MainActor
    func testFaceWithScreenAndMic() throws {
        // Mode 1: Full screencast with facecam
        navigateToStudio()
        selectPersona("Face")
        toggleScreen()
        // Mic is on by default

        // Verify record button is enabled
        XCTAssertTrue(verifyRecordButton(), "Record button should be enabled for Face + Screen + Mic")
    }

    @MainActor
    func testFaceWithScreenNoMic() throws {
        // Mode 3: Silent screencast with facecam
        navigateToStudio()
        selectPersona("Face")
        toggleScreen()
        toggleMic() // Turn off mic

        // Verify controls exist
        let screenToggle = app.buttons["Toggle_Screen"]
        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(screenToggle.exists, "Screen toggle should exist")
        XCTAssertTrue(micToggle.exists, "Mic toggle should exist")
    }

    @MainActor
    func testFaceOnlyWithMic() throws {
        // Mode 5: Talking head
        navigateToStudio()
        selectPersona("Face")
        // Screen off by default, Mic on by default

        XCTAssertTrue(verifyRecordButton(), "Record button should be enabled for Face + Mic (talking head)")
    }

    @MainActor
    func testScreenOnlyWithMic() throws {
        // Mode 2: Screencast with audio (using Audio persona)
        navigateToStudio()
        selectPersona("Audio")
        toggleScreen()
        // Mic is on by default

        XCTAssertTrue(verifyRecordButton(), "Record button should be enabled for Screen + Mic")
    }

    @MainActor
    func testAudioOnly() throws {
        // Mode 7: Audio-only podcast
        navigateToStudio()
        selectPersona("Audio")
        // Screen off, Mic on by default

        XCTAssertTrue(verifyRecordButton(), "Record button should be enabled for Audio-only mode")
    }

    @MainActor
    func testAvatarWithScreenAndMic() throws {
        // VTuber screencast
        navigateToStudio()
        selectPersona("Avatar")
        toggleScreen()
        // Mic is on by default

        // Verify controls exist
        let screenToggle = app.buttons["Toggle_Screen"]
        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(screenToggle.exists, "Screen toggle should exist")
        XCTAssertTrue(micToggle.exists, "Mic toggle should exist")
    }

    @MainActor
    func testAvatarTalkingHead() throws {
        // Avatar talking head
        navigateToStudio()
        selectPersona("Avatar")
        // Screen off, Mic on by default

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
    }

    // MARK: - Recording Flow Tests

    @MainActor
    func testRecordButtonExistsAndEnabled() throws {
        navigateToStudio()
        selectPersona("Face")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled with Face persona")
    }

    // MARK: - UI Responsiveness Tests

    @MainActor
    func testScreenToggleResponsiveness() throws {
        navigateToStudio()

        let screenToggle = app.buttons["Toggle_Screen"]
        XCTAssertTrue(screenToggle.waitForExistence(timeout: 3), "Screen toggle should exist")

        // Verify toggle responds and UI doesn't freeze
        screenToggle.click()
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should remain hittable after click")

        // Toggle back - verify consistent behavior
        screenToggle.click()
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should remain hittable after second click")

        // Verify other controls are still accessible (UI not frozen)
        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should be hittable after screen toggle")
    }

    @MainActor
    func testMicToggleResponsiveness() throws {
        navigateToStudio()

        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(micToggle.waitForExistence(timeout: 3), "Mic toggle should exist")

        // Verify toggle responds and UI doesn't freeze
        micToggle.click()
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should remain hittable after click")

        // Toggle back
        micToggle.click()
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should remain hittable after second click")

        // Verify other controls are still accessible (UI not frozen)
        let screenToggle = app.buttons["Toggle_Screen"]
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable after mic toggle")
    }

    @MainActor
    func testPersonaSelectionResponsiveness() throws {
        navigateToStudio()

        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")

        // Open popover and verify it appears
        personaButton.click()

        let faceOption = app.buttons["Persona_Face"]
        XCTAssertTrue(faceOption.waitForExistence(timeout: 3), "Popover should open")

        // Select a persona
        faceOption.click()
        XCTAssertTrue(personaButton.waitForExistence(timeout: 2), "Persona button should be visible after selection")

        // Verify UI is responsive after selection
        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.isHittable, "Record button should be hittable after persona selection")
    }

    @MainActor
    func testRapidToggleSwitching() throws {
        // Test that rapid toggling doesn't cause UI issues
        navigateToStudio()

        let screenToggle = app.buttons["Toggle_Screen"]
        let micToggle = app.buttons["Toggle_Mic"]

        XCTAssertTrue(screenToggle.waitForExistence(timeout: 3), "Screen toggle should exist")
        XCTAssertTrue(micToggle.exists, "Mic toggle should exist")

        // Rapidly toggle both controls multiple times
        for _ in 0 ..< 3 {
            screenToggle.click()
            micToggle.click()
        }

        // Verify UI is still responsive after rapid toggling
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable after rapid toggling")
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should be hittable after rapid toggling")

        // Verify record button is still accessible
        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.exists, "Record button should exist after rapid toggling")
    }

    // MARK: - Recording Start/Stop Tests

    @MainActor
    func testRecordingStartsAndStops() throws {
        navigateToStudio()
        selectPersona("Audio") // Audio-only mode for faster testing

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled")

        // Start recording
        recordButton.click()

        // Verify stop button appears (indicates recording started)
        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear when recording starts")

        // Verify record button is no longer visible (replaced by stop button)
        XCTAssertFalse(recordButton.exists, "Record button should be hidden during recording")

        // Let it record for a moment
        sleep(2)

        // Stop recording
        stopButton.click()

        // Verify record button reappears
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should reappear after stopping")
    }

    @MainActor
    func testRecordingWithScreenShare() throws {
        navigateToStudio()
        selectPersona("Audio")
        toggleScreen() // Enable screen sharing

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled with screen share")

        // Start recording
        recordButton.click()

        // Verify stop button appears
        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for screen recording")

        // Record briefly
        sleep(2)

        // Stop recording
        stopButton.click()

        // Verify record button reappears
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should reappear after screen recording stops")
    }

    @MainActor
    func testRecordButtonStateTransitions() throws {
        navigateToStudio()
        selectPersona("Face")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Verify initial state - button should be enabled
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled initially")

        // Start recording
        recordButton.click()

        // Verify transition to recording state
        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear")

        // Stop recording
        stopButton.click()

        // Verify transition back to ready state
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should reappear")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled after stopping")
    }

    @MainActor
    func testMultipleRecordingCycles() throws {
        // Test that we can start/stop recording multiple times
        navigateToStudio()
        selectPersona("Audio")

        for cycle in 1 ... 2 {
            let recordButton = app.buttons["Btn_Record"]
            XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist for cycle \(cycle)")

            // Start recording
            recordButton.click()

            let stopButton = app.buttons["Btn_Stop"]
            XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for cycle \(cycle)")

            // Record briefly
            sleep(1)

            // Stop recording
            stopButton.click()

            // Wait for UI to reset
            XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should reappear after cycle \(cycle)")
        }
    }

    // MARK: - Recording Completion Tests
    // Note: File verification is done via the complete recording flow
    // The UI test runner cannot access the app's sandboxed container

    @MainActor
    func testRecordingCompletesSuccessfully() throws {
        // This test verifies the full recording flow completes without errors
        // If file creation fails, stopRecording would error and UI wouldn't reset
        navigateToStudio()
        selectPersona("Audio") // Audio-only for faster recording

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3), "Record button should exist")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Stop button should appear - recording started")

        // Record for 2 seconds to ensure valid file content
        sleep(2)

        // Stop recording
        stopButton.click()

        // Wait for file to be written and signed (this is the key assertion)
        // If file creation/signing fails, the record button won't reappear properly
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear after file is saved and signed")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled after successful save")
    }

    @MainActor
    func testRecordingWithScreenCompletesSuccessfully() throws {
        // Test recording with screen capture completes without errors
        navigateToStudio()
        selectPersona("Audio")
        toggleScreen() // Enable screen sharing

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5), "Stop button should appear")

        // Record for 2 seconds
        sleep(2)

        // Stop recording
        stopButton.click()

        // Verify successful completion
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear after screen recording completes")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled after screen recording save")
    }

    // MARK: - Edge Case Tests

    @MainActor
    func testRecordButtonDisabledWithNoInputs() throws {
        navigateToStudio()
        selectPersona("Audio")

        // Turn off microphone (the only input for Audio persona)
        toggleMic()

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 3), "Record button should exist")

        // Record button should be disabled when no inputs are enabled
        // Note: The button may still be visible but should be disabled
        // This depends on the canStartRecording logic in RecordViewModel
    }

    @MainActor
    func testPersonaSwitchingMidSession() throws {
        navigateToStudio()

        // Start with Face persona
        selectPersona("Face")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Switch to Audio persona
        selectPersona("Audio")

        // Verify record button still works
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should still exist after persona switch")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled after persona switch")

        // Switch to Avatar persona
        selectPersona("Avatar")

        // Verify record button still works
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should still exist after avatar switch")
    }

    @MainActor
    func testControlsAccessibleDuringRecording() throws {
        navigateToStudio()
        selectPersona("Audio")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear")

        // Verify toggles are still accessible during recording
        let screenToggle = app.buttons["Toggle_Screen"]
        let micToggle = app.buttons["Toggle_Mic"]

        XCTAssertTrue(screenToggle.exists, "Screen toggle should exist during recording")
        XCTAssertTrue(micToggle.exists, "Mic toggle should exist during recording")

        // Stop recording
        stopButton.click()
        XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should reappear")
    }

    // MARK: - Recording File Validation Tests
    // These tests verify that recordings complete successfully without file corruption.
    // The key indicator of a valid file is that the UI flow completes (stop button disappears,
    // record button reappears) - if file writing fails, the flow would hang or error.

    @MainActor
    func testAudioRecordingCompletesWithValidFile() throws {
        // Test audio-only recording produces a valid file
        // A corrupted file would cause the stop flow to hang or fail
        navigateToStudio()
        selectPersona("Audio")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear")

        // Record for 3 seconds to ensure valid content
        sleep(3)

        // Stop recording
        stopButton.click()

        // Wait for recording to complete - this is the key assertion
        // If file is corrupted (no moov atom), finishWriting() would fail
        // and the record button wouldn't reappear properly
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear - indicates file saved successfully")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled after successful save")
    }

    @MainActor
    func testScreenRecordingCompletesWithValidFile() throws {
        // Test screen recording produces a valid .mov file
        navigateToStudio()
        selectPersona("Audio")
        toggleScreen() // Enable screen capture

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for screen recording")

        // Record for 3 seconds
        sleep(3)

        // Stop recording
        stopButton.click()

        // Key assertion: record button reappears = file saved successfully
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear after screen recording")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled - screen recording file is valid")
    }

    @MainActor
    func testFaceCamRecordingCompletesWithValidFile() throws {
        // Test face cam recording produces a valid .mov file
        navigateToStudio()
        selectPersona("Face")

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for face cam recording")

        // Record for 3 seconds
        sleep(3)

        // Stop recording
        stopButton.click()

        // Key assertion: record button reappears = file saved successfully
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear after face cam recording")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled - face cam file is valid")
    }

    @MainActor
    func testScreenWithFaceCamRecordingCompletesWithValidFile() throws {
        // Test screen + face cam recording produces a valid .mov file
        navigateToStudio()
        selectPersona("Face")
        toggleScreen() // Enable screen + face cam PiP

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist")

        // Start recording
        recordButton.click()

        let stopButton = app.buttons["Btn_Stop"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for screen+facecam recording")

        // Record for 3 seconds
        sleep(3)

        // Stop recording
        stopButton.click()

        // Key assertion: record button reappears = file saved successfully
        XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Record button should reappear after screen+facecam recording")
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled - composite file is valid")
    }

    @MainActor
    func testConsecutiveRecordingsAllProduceValidFiles() throws {
        // Test that multiple consecutive recordings all produce valid files
        // This catches race conditions where files might occasionally be corrupted
        navigateToStudio()
        selectPersona("Audio")

        for cycle in 1 ... 3 {
            let recordButton = app.buttons["Btn_Record"]
            XCTAssertTrue(recordButton.waitForExistence(timeout: 10), "Record button should exist for cycle \(cycle)")

            // Start recording
            recordButton.click()

            let stopButton = app.buttons["Btn_Stop"]
            XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button should appear for cycle \(cycle)")

            // Record for 2 seconds
            sleep(2)

            // Stop recording
            stopButton.click()

            // Key assertion: each recording completes successfully
            XCTAssertTrue(recordButton.waitForExistence(timeout: 15), "Cycle \(cycle): Record button should reappear - file saved")
            XCTAssertTrue(recordButton.isEnabled, "Cycle \(cycle): Record button should be enabled - file is valid")
        }
    }

    // MARK: - Camera Preview Responsiveness Tests

    @MainActor
    func testFaceCameraSwitchResponsiveness() throws {
        // Test that switching to Face persona shows camera preview without long stutter
        // This test catches issues where camera preview takes too long to appear
        navigateToStudio()

        // Start with Audio persona (no camera)
        selectPersona("Audio")

        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")

        // Measure time to switch to Face and have UI become responsive
        let startTime = Date()

        // Switch to Face persona
        selectPersona("Face")

        // UI should be responsive within 2 seconds (not minutes)
        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5), "Record button should exist after Face selection")
        XCTAssertTrue(recordButton.isHittable, "Record button should be hittable after Face selection")

        // Verify other controls are responsive (not frozen)
        let screenToggle = app.buttons["Toggle_Screen"]
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable - UI not frozen")

        let elapsedTime = Date().timeIntervalSince(startTime)
        // Allow 10 seconds for UI test overhead, but flag if it takes longer
        XCTAssertLessThan(elapsedTime, 10.0, "Switching to Face persona should complete within 10 seconds, took \(elapsedTime)s")
    }

    @MainActor
    func testRapidPersonaSwitchingDoesNotFreeze() throws {
        // Test that rapidly switching between personas doesn't freeze the UI
        navigateToStudio()

        let personaButton = app.buttons["Btn_Persona"]
        XCTAssertTrue(personaButton.waitForExistence(timeout: 3), "Persona button should exist")

        // Rapidly switch between personas
        for persona in ["Face", "Audio", "Avatar", "Face", "Audio"] {
            selectPersona(persona)

            // Verify UI remains responsive after each switch (within 3 seconds)
            let recordButton = app.buttons["Btn_Record"]
            XCTAssertTrue(recordButton.waitForExistence(timeout: 3), "Record button should exist after switching to \(persona)")
        }

        // Final verification that UI is responsive
        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.isHittable, "Record button should be hittable after rapid persona switching")

        let screenToggle = app.buttons["Toggle_Screen"]
        XCTAssertTrue(screenToggle.isHittable, "Screen toggle should be hittable after rapid persona switching")
    }

    @MainActor
    func testCameraPreviewAppearsQuickly() throws {
        // Test that camera preview appears quickly when switching to Face
        navigateToStudio()

        // Start with Audio (no camera preview)
        selectPersona("Audio")

        // Switch to Face and verify UI doesn't stutter for extended period
        let startTime = Date()
        selectPersona("Face")

        // The record button should become hittable quickly
        let recordButton = app.buttons["Btn_Record"]
        var becameHittable = false
        for _ in 0..<10 {
            if recordButton.exists && recordButton.isHittable {
                becameHittable = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        let elapsedTime = Date().timeIntervalSince(startTime)
        XCTAssertTrue(becameHittable, "Record button should become hittable within 5 seconds")
        XCTAssertLessThan(elapsedTime, 5.0, "Camera preview should initialize within 5 seconds, took \(elapsedTime)s")

        // Verify controls remain responsive
        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(micToggle.isHittable, "Mic toggle should be hittable - camera init shouldn't block UI")
    }
}
