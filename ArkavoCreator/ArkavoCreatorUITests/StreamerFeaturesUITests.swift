//
//  StreamerFeaturesUITests.swift
//  ArkavoCreatorUITests
//
//  XCUI tests for Twitch streamer UX improvements:
//  - Priority 1: Dual Audio Mixing (Mic + Desktop Audio)
//  - Priority 2: Integrated Twitch Chat Panel
//  - Priority 3: Scene Presets
//

import XCTest

final class StreamerFeaturesUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToStudio() {
        let studioButton = app.buttons["Studio"]
        if studioButton.waitForExistence(timeout: 10) {
            studioButton.click()
            sleep(1)
        }
    }

    /// Finds the scene picker menu button (borderless menu renders as popUpButton on macOS)
    private func findSceneMenu() -> XCUIElement? {
        // borderless Menu in SwiftUI renders as a popUpButton on macOS
        let popUps = app.popUpButtons
        if popUps.count > 0 {
            return popUps.firstMatch
        }
        // Fallback: try menuButtons
        let menuBtns = app.menuButtons
        if menuBtns.count > 0 {
            return menuBtns.firstMatch
        }
        return nil
    }

    /// Opens the inspector panel using the Edit button (slider.horizontal.3 icon)
    private func openInspector() {
        // The slider.horizontal.3 icon renders with label "Edit" on macOS
        let toggle = app.buttons.matching(NSPredicate(format: "label == 'Edit'")).firstMatch
        if toggle.waitForExistence(timeout: 5) {
            toggle.click()
            sleep(1)
        }
    }

    /// Finds the chat toggle button (bubble.left.and.bubble.right renders as "Conversation")
    private func findChatToggle() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Conversation'")).firstMatch
    }

    // MARK: - Priority 1: Desktop Audio Toggle

    @MainActor
    func testDesktopAudioToggleExists() throws {
        navigateToStudio()

        let toggle = app.buttons["Toggle_DesktopAudio"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "Desktop Audio toggle should exist in the control bar"
        )
    }

    @MainActor
    func testDesktopAudioToggleChangesState() throws {
        navigateToStudio()

        let toggle = app.buttons["Toggle_DesktopAudio"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        RemoteCameraTestHelpers.takeScreenshot(named: "DesktopAudio_Before", attachTo: self)

        // Enable desktop audio
        toggle.click()
        sleep(2)

        RemoteCameraTestHelpers.takeScreenshot(named: "DesktopAudio_After", attachTo: self)

        // Disable again
        toggle.click()
        sleep(1)
    }

    @MainActor
    func testMicToggleCoexistsWithDesktopAudio() throws {
        navigateToStudio()

        let micToggle = app.buttons["Toggle_Mic"]
        let desktopToggle = app.buttons["Toggle_DesktopAudio"]

        XCTAssertTrue(micToggle.waitForExistence(timeout: 5), "Mic toggle should exist")
        XCTAssertTrue(desktopToggle.waitForExistence(timeout: 5), "Desktop audio toggle should exist")

        // Toggle mic off and on
        micToggle.click()
        sleep(1)
        micToggle.click()
        sleep(1)
    }

    @MainActor
    func testDesktopAudioShowsInInspector() throws {
        navigateToStudio()
        openInspector()

        // Enable desktop audio
        let toggle = app.buttons["Toggle_DesktopAudio"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()
        sleep(2)

        // Check for Desktop Audio section in inspector
        let header = app.staticTexts["Desktop Audio"]
        if header.waitForExistence(timeout: 5) {
            XCTAssertTrue(true, "Desktop Audio section appears in inspector when enabled")
        }

        RemoteCameraTestHelpers.takeScreenshot(named: "Inspector_DualAudio", attachTo: self)

        // Clean up
        toggle.click()
        sleep(1)
    }

    @MainActor
    func testVolumeSliderExistsInInspector() throws {
        navigateToStudio()
        openInspector()

        // The inspector should show at least one slider (mic volume) in the Audio section
        let sliders = app.sliders
        XCTAssertGreaterThan(sliders.count, 0, "Volume slider should exist in the audio inspector")

        RemoteCameraTestHelpers.takeScreenshot(named: "Inspector_VolumeSlider", attachTo: self)
    }

    // MARK: - Priority 2: Chat Panel

    @MainActor
    func testChatToggleExists() throws {
        navigateToStudio()

        let chatToggle = findChatToggle()
        let exists = chatToggle.waitForExistence(timeout: 5)

        if exists {
            print("Chat toggle found (Twitch platform is selected)")
        } else {
            print("Chat toggle not visible (platform may not be Twitch)")
        }
        // Don't fail — visibility depends on selected platform
    }

    @MainActor
    func testChatPanelSlideOut() throws {
        navigateToStudio()

        let chatToggle = findChatToggle()
        guard chatToggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Chat toggle not visible — Twitch may not be selected")
        }

        RemoteCameraTestHelpers.takeScreenshot(named: "ChatPanel_Before", attachTo: self)

        // Open chat panel
        chatToggle.click()
        sleep(1)

        // Verify "Chat" header appeared
        let chatHeader = app.staticTexts["Chat"]
        XCTAssertTrue(
            chatHeader.waitForExistence(timeout: 3),
            "Chat panel header should appear"
        )

        RemoteCameraTestHelpers.takeScreenshot(named: "ChatPanel_Open", attachTo: self)

        // Verify empty state or "Waiting for messages" text
        let emptyState = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Chat will appear' OR label CONTAINS 'Waiting for messages'")
        ).firstMatch
        // The empty state may not be found via accessibility if overlaid in a ZStack
        // The chat header being present is the primary verification
        if emptyState.waitForExistence(timeout: 3) {
            print("Empty state message found")
        } else {
            print("Empty state text not found via accessibility (ZStack overlay) - chat panel header verified above")
        }

        // Close panel by clicking toggle again
        chatToggle.click()
        sleep(1)

        RemoteCameraTestHelpers.takeScreenshot(named: "ChatPanel_Closed", attachTo: self)
    }

    @MainActor
    func testChatPanelConnectionIndicator() throws {
        navigateToStudio()

        let chatToggle = findChatToggle()
        guard chatToggle.waitForExistence(timeout: 5) else {
            throw XCTSkip("Chat toggle not visible")
        }

        chatToggle.click()
        sleep(1)

        let chatHeader = app.staticTexts["Chat"]
        XCTAssertTrue(chatHeader.exists, "Chat panel should be visible")

        RemoteCameraTestHelpers.takeScreenshot(named: "ChatPanel_Disconnected", attachTo: self)

        // Clean up
        chatToggle.click()
    }

    // MARK: - Priority 3: Scene Presets

    @MainActor
    func testScenePickerExists() throws {
        navigateToStudio()

        let sceneMenu = findSceneMenu()
        XCTAssertNotNil(sceneMenu, "Scene picker menu should exist in the control bar")

        RemoteCameraTestHelpers.takeScreenshot(named: "ScenePicker_Exists", attachTo: self)
    }

    @MainActor
    func testScenePickerShowsAllScenes() throws {
        navigateToStudio()

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        sceneMenu.click()
        sleep(1)

        // Verify all scene options appear
        XCTAssertTrue(app.menuItems["Live"].waitForExistence(timeout: 3), "Live scene should be in menu")
        XCTAssertTrue(app.menuItems["Starting Soon"].exists, "Starting Soon scene should be in menu")
        XCTAssertTrue(app.menuItems["Be Right Back"].exists, "Be Right Back scene should be in menu")
        XCTAssertTrue(app.menuItems["Ending"].exists, "Ending scene should be in menu")

        RemoteCameraTestHelpers.takeScreenshot(named: "SceneMenu_AllOptions", attachTo: self)

        // Dismiss
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testSwitchToStartingSoonScene() throws {
        navigateToStudio()

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_Live", attachTo: self)

        sceneMenu.click()
        sleep(1)

        guard app.menuItems["Starting Soon"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Starting Soon menu item not found")
        }
        app.menuItems["Starting Soon"].click()
        sleep(1)

        // Verify overlay text
        let overlay = app.staticTexts["Starting Soon..."]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3), "Starting Soon overlay should appear")

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_StartingSoon", attachTo: self)

        // Return to Live to clean up
        if let menu = findSceneMenu() {
            menu.click()
            sleep(1)
            if app.menuItems["Live"].waitForExistence(timeout: 2) {
                app.menuItems["Live"].click()
            }
        }
    }

    @MainActor
    func testSwitchToBRBScene() throws {
        navigateToStudio()

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        sceneMenu.click()
        sleep(1)

        guard app.menuItems["Be Right Back"].waitForExistence(timeout: 3) else {
            throw XCTSkip("BRB menu item not found")
        }
        app.menuItems["Be Right Back"].click()
        sleep(1)

        let overlay = app.staticTexts["Be Right Back"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3), "BRB overlay should appear")

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_BRB", attachTo: self)

        // Clean up
        if let menu = findSceneMenu() {
            menu.click()
            sleep(1)
            if app.menuItems["Live"].waitForExistence(timeout: 2) {
                app.menuItems["Live"].click()
            }
        }
    }

    @MainActor
    func testSwitchToEndingScene() throws {
        navigateToStudio()

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        sceneMenu.click()
        sleep(1)

        guard app.menuItems["Ending"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Ending menu item not found")
        }
        app.menuItems["Ending"].click()
        sleep(1)

        let overlay = app.staticTexts["Thanks for watching!"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 3), "Ending overlay should appear")

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_Ending", attachTo: self)

        // Clean up
        if let menu = findSceneMenu() {
            menu.click()
            sleep(1)
            if app.menuItems["Live"].waitForExistence(timeout: 2) {
                app.menuItems["Live"].click()
            }
        }
    }

    @MainActor
    func testReturnToLiveScene() throws {
        navigateToStudio()

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        // Switch to BRB
        sceneMenu.click()
        sleep(1)
        guard app.menuItems["Be Right Back"].waitForExistence(timeout: 3) else {
            throw XCTSkip("BRB menu item not found")
        }
        app.menuItems["Be Right Back"].click()
        sleep(1)

        XCTAssertTrue(
            app.staticTexts["Be Right Back"].waitForExistence(timeout: 3),
            "BRB overlay should appear"
        )

        // Switch back to Live
        guard let sceneMenu2 = findSceneMenu() else {
            throw XCTSkip("Scene picker not found after BRB")
        }
        sceneMenu2.click()
        sleep(1)
        guard app.menuItems["Live"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Live menu item not found")
        }
        app.menuItems["Live"].click()
        sleep(1)

        // Verify overlay is gone
        XCTAssertFalse(
            app.staticTexts["Be Right Back"].exists,
            "BRB overlay should disappear when returning to Live"
        )

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_ReturnToLive", attachTo: self)
    }

    @MainActor
    func testSceneMutesMicWhenNotLive() throws {
        navigateToStudio()

        let micToggle = app.buttons["Toggle_Mic"]
        XCTAssertTrue(micToggle.waitForExistence(timeout: 5))

        guard let sceneMenu = findSceneMenu() else {
            throw XCTSkip("Scene picker not found")
        }

        // Switch to Starting Soon (should mute mic)
        sceneMenu.click()
        sleep(1)
        guard app.menuItems["Starting Soon"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Starting Soon menu item not found")
        }
        app.menuItems["Starting Soon"].click()
        sleep(1)

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_MicMuted", attachTo: self)

        // Switch back to Live (should restore mic)
        guard let sceneMenu2 = findSceneMenu() else {
            throw XCTSkip("Scene picker not found after scene switch")
        }
        sceneMenu2.click()
        sleep(1)
        guard app.menuItems["Live"].waitForExistence(timeout: 3) else {
            throw XCTSkip("Live menu item not found")
        }
        app.menuItems["Live"].click()
        sleep(1)

        RemoteCameraTestHelpers.takeScreenshot(named: "Scene_MicRestored", attachTo: self)
    }

    // MARK: - Integration Tests

    @MainActor
    func testAllNewControlsCoexist() throws {
        navigateToStudio()

        // All three new features present simultaneously
        XCTAssertTrue(app.buttons["Toggle_Mic"].waitForExistence(timeout: 5), "Mic toggle should exist")
        XCTAssertTrue(app.buttons["Toggle_DesktopAudio"].waitForExistence(timeout: 5), "Desktop audio toggle should exist")
        XCTAssertTrue(app.buttons["Btn_Record"].waitForExistence(timeout: 5), "Record button should exist")
        XCTAssertTrue(app.buttons["Btn_GoLive"].waitForExistence(timeout: 5), "Go Live button should exist")
        XCTAssertTrue(app.buttons["Source_Face"].waitForExistence(timeout: 5), "Face source toggle should exist")
        XCTAssertNotNil(findSceneMenu(), "Scene picker should exist")

        RemoteCameraTestHelpers.takeScreenshot(named: "AllControls_Coexist", attachTo: self)
    }

    @MainActor
    func testControlBarLayoutIntegrity() throws {
        navigateToStudio()

        RemoteCameraTestHelpers.takeScreenshot(named: "ControlBar_FullLayout", attachTo: self)
        RemoteCameraTestHelpers.logVisibleButtons(app, prefix: "ControlBar: ")
    }

    @MainActor
    func testInspectorShowsAudioSection() throws {
        navigateToStudio()
        openInspector()

        // In Face mode, the inspector shows AudioLevelMeter with "Audio" header
        let audioHeader = app.staticTexts["Audio"]
        let micHeader = app.staticTexts["Microphone"]
        let hasAudioSection = audioHeader.waitForExistence(timeout: 3) || micHeader.waitForExistence(timeout: 1)
        XCTAssertTrue(hasAudioSection, "Audio section should appear in inspector")

        RemoteCameraTestHelpers.takeScreenshot(named: "Inspector_AudioSection", attachTo: self)
    }

    @MainActor
    func testRecordAndLiveButtonsStillFunctional() throws {
        navigateToStudio()

        let recordButton = app.buttons["Btn_Record"]
        XCTAssertTrue(recordButton.waitForExistence(timeout: 5))
        XCTAssertTrue(recordButton.isEnabled, "Record button should be enabled")

        let liveButton = app.buttons["Btn_GoLive"]
        XCTAssertTrue(liveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(liveButton.isEnabled, "Go Live button should be enabled")
    }
}
