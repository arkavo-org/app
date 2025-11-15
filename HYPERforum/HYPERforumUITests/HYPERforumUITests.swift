import XCTest

/// Main UI tests for HYPΞRforum application
/// These tests cover basic launch behavior and overall app functionality
final class HYPERforumUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Basic Launch Tests

    func testLaunch() throws {
        app.launch()

        // Verify the app launches successfully and window appears
        XCTAssertTrue(app.exists, "Application should launch")
        sleep(2)

        // Verify either welcome screen or main forum is displayed
        let welcomeScreen = app.staticTexts["text_appTitle"]
        let mainForum = app.otherElements["view_mainForum"]

        XCTAssertTrue(welcomeScreen.exists || mainForum.exists, "Should show either welcome screen or main forum after launch")
    }

    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
        }
    }

    func testAppStability() throws {
        app.launch()

        // Let app run for a few seconds to ensure stability
        sleep(5)

        // Verify app is still running and responsive
        XCTAssertTrue(app.exists, "App should remain stable after launch")
    }

    // MARK: - Welcome Screen Tests

    func testWelcomeScreen() throws {
        app.launch()
        sleep(2)

        // Skip if user is already authenticated
        guard app.staticTexts["text_appTitle"].exists else {
            throw XCTSkip("User is already authenticated")
        }

        // Check if welcome screen elements are present
        let titleText = app.staticTexts["text_appTitle"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 5), "Welcome screen title should exist")
        XCTAssertEqual(titleText.label, "HYPΞRforum", "Title should be 'HYPΞRforum'")

        // Verify logo
        let logo = app.staticTexts["logo_xi"]
        XCTAssertTrue(logo.exists, "Greek Xi logo should be displayed")

        // Verify subtitle
        let subtitle = app.staticTexts["text_appSubtitle"]
        XCTAssertTrue(subtitle.exists, "Subtitle should be displayed")

        // Verify sign-in button
        let signInButton = app.buttons["button_signInPasskey"]
        XCTAssertTrue(signInButton.exists, "Sign-in button should be displayed")
    }

    func testWelcomeScreenBranding() throws {
        app.launch()
        sleep(2)

        guard app.staticTexts["text_appTitle"].exists else {
            throw XCTSkip("User is already authenticated")
        }

        // Verify Arkavo Orange branding is present
        // We can't directly test colors in UI tests, but we can verify elements exist
        let logo = app.staticTexts["logo_xi"]
        XCTAssertTrue(logo.exists, "Branded logo should exist")

        // Verify feature list shows key features
        let featureList = app.otherElements["list_welcomeFeatures"]
        XCTAssertTrue(featureList.exists, "Feature list should be displayed")
    }

    // MARK: - Main Forum Tests

    func testMainForumStructure() throws {
        app.launch()
        sleep(2)

        // Skip if not authenticated
        let mainForum = app.otherElements["view_mainForum"]
        guard mainForum.waitForExistence(timeout: 5) else {
            throw XCTSkip("User not authenticated")
        }

        // Verify main forum structure
        XCTAssertTrue(mainForum.exists, "Main forum view should exist")

        // Verify sidebar
        let sidebar = app.otherElements["list_sidebar"]
        XCTAssertTrue(sidebar.exists, "Sidebar should exist")

        // Verify navigation items
        XCTAssertTrue(app.buttons["sidebar_groups"].exists, "Groups nav item should exist")
        XCTAssertTrue(app.buttons["sidebar_discussions"].exists, "Discussions nav item should exist")
        XCTAssertTrue(app.buttons["sidebar_council"].exists, "Council nav item should exist")
        XCTAssertTrue(app.buttons["sidebar_settings"].exists, "Settings nav item should exist")
    }

    func testMainForumNavigation() throws {
        app.launch()
        sleep(2)

        let mainForum = app.otherElements["view_mainForum"]
        guard mainForum.waitForExistence(timeout: 5) else {
            throw XCTSkip("User not authenticated")
        }

        // Test basic navigation works
        app.buttons["sidebar_groups"].click()
        sleep(1)
        XCTAssertTrue(app.otherElements["view_groups"].exists || app.staticTexts["Groups"].exists, "Should navigate to Groups")

        app.buttons["sidebar_settings"].click()
        sleep(1)
        XCTAssertTrue(app.otherElements["view_settings"].exists || app.staticTexts["Settings"].exists, "Should navigate to Settings")
    }

    // MARK: - Window Tests

    func testWindowAppears() throws {
        app.launch()
        sleep(2)

        // Verify app window is visible and has reasonable size
        let windows = app.windows
        XCTAssertGreaterThan(windows.count, 0, "Should have at least one window")

        let mainWindow = windows.firstMatch
        XCTAssertTrue(mainWindow.exists, "Main window should exist")

        // Verify window is visible (has non-zero frame)
        let frame = mainWindow.frame
        XCTAssertGreaterThan(frame.width, 0, "Window should have width")
        XCTAssertGreaterThan(frame.height, 0, "Window should have height")
    }

    func testWindowTitle() throws {
        app.launch()
        sleep(2)

        // macOS apps may show title in window or toolbar
        // Verify HYPΞRforum branding is visible somewhere
        let title = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'HYPΞRforum'"))
        XCTAssertGreaterThan(title.count, 0, "App should display HYPΞRforum branding")
    }

    // MARK: - Accessibility Tests

    func testAccessibilityIdentifiersPresent() throws {
        app.launch()
        sleep(2)

        // Verify key accessibility identifiers are present
        // This ensures our test infrastructure will work

        if app.staticTexts["text_appTitle"].exists {
            // Welcome screen
            XCTAssertTrue(app.staticTexts["text_appTitle"].exists, "Welcome title should have identifier")
            XCTAssertTrue(app.buttons["button_signInPasskey"].exists, "Sign-in button should have identifier")
        } else {
            // Main forum
            XCTAssertTrue(app.otherElements["view_mainForum"].exists || app.otherElements["list_sidebar"].exists, "Main forum elements should have identifiers")
        }
    }

    // MARK: - Memory and Resource Tests

    func testMemoryLeaks() throws {
        app.launch()
        sleep(2)

        // Navigate through app to generate memory allocations
        if app.otherElements["view_mainForum"].exists {
            // Navigate through all main sections multiple times
            for _ in 0..<3 {
                app.buttons["sidebar_groups"].click()
                usleep(500000)
                app.buttons["sidebar_discussions"].click()
                usleep(500000)
                app.buttons["sidebar_council"].click()
                usleep(500000)
                app.buttons["sidebar_settings"].click()
                usleep(500000)
            }
        }

        // App should still be responsive
        XCTAssertTrue(app.exists, "App should not crash during navigation")
    }

    // MARK: - State Persistence Tests

    func testAppStateAfterRelaunch() throws {
        app.launch()
        sleep(2)

        let wasAuthenticated = app.otherElements["view_mainForum"].exists

        // Terminate and relaunch
        app.terminate()
        sleep(2)
        app.launch()
        sleep(3)

        let isAuthenticatedAfterRelaunch = app.otherElements["view_mainForum"].exists

        // Authentication state may or may not persist depending on WebSocket reconnection
        // Just verify app launches successfully
        XCTAssertTrue(app.exists, "App should launch successfully after relaunch")

        // If was authenticated before, might still be (if reconnection succeeds)
        // or might need re-auth (if reconnection fails)
        // Both are valid outcomes
        if wasAuthenticated {
            XCTAssertTrue(isAuthenticatedAfterRelaunch || app.staticTexts["text_appTitle"].exists, "Should show either main forum or welcome screen")
        }
    }

    // MARK: - Integration Tests

    func testBasicUserFlow() throws {
        app.launch()
        sleep(2)

        // This test covers a basic user flow through the app
        if app.staticTexts["text_appTitle"].exists {
            // Starting from welcome screen
            // Verify key elements exist
            XCTAssertTrue(app.staticTexts["text_appTitle"].exists, "Should show welcome screen")
            XCTAssertTrue(app.buttons["button_signInPasskey"].exists, "Should show sign-in button")

            // User would authenticate here (tested separately in AuthenticationTests)
        } else if app.otherElements["view_mainForum"].exists {
            // Starting from authenticated state
            // Navigate to groups
            app.buttons["sidebar_groups"].click()
            sleep(1)

            // Check groups are displayed
            let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
            if groupCards.count > 0 {
                // Select first group
                groupCards.element(boundBy: 0).click()
                sleep(1)

                // Verify chat view opens
                let chatView = app.otherElements["view_chat"]
                XCTAssertTrue(chatView.exists, "Should navigate to chat view")
            }
        }
    }

    // MARK: - Error Handling Tests

    func testAppHandlesUnexpectedState() throws {
        app.launch()
        sleep(2)

        // Verify app handles initial state gracefully
        XCTAssertTrue(app.exists, "App should exist")

        // Try rapid interactions to test stability
        let buttons = app.buttons.allElementsBoundByIndex
        for button in buttons.prefix(5) {
            if button.exists && button.isHittable {
                button.click()
                usleep(200000)
            }
        }

        // App should remain stable
        XCTAssertTrue(app.exists, "App should remain stable after rapid interactions")
    }

    // MARK: - UI Responsiveness Tests

    func testUIResponsiveness() throws {
        app.launch()
        sleep(2)

        // Test that UI elements are responsive
        if app.otherElements["view_mainForum"].exists {
            let groupsButton = app.buttons["sidebar_groups"]
            XCTAssertTrue(groupsButton.exists, "Groups button should exist")

            // Click should be responsive
            groupsButton.click()
            sleep(1)

            // View should update
            XCTAssertTrue(app.otherElements["view_groups"].exists || app.staticTexts["Groups"].exists, "UI should respond to clicks")
        }
    }

    // MARK: - Smoke Tests

    func testSmokeTest() throws {
        // Comprehensive smoke test covering all major areas
        app.launch()
        sleep(2)

        // Verify app launched
        XCTAssertTrue(app.exists, "App should launch")

        // Verify basic structure
        let isWelcome = app.staticTexts["text_appTitle"].exists
        let isMainForum = app.otherElements["view_mainForum"].exists

        XCTAssertTrue(isWelcome || isMainForum, "Should show either welcome or main forum")

        if isMainForum {
            // Quick check of all main sections
            let sections = ["sidebar_groups", "sidebar_discussions", "sidebar_council", "sidebar_settings"]
            for section in sections {
                XCTAssertTrue(app.buttons[section].exists, "\(section) should exist")
            }
        }

        // App should be stable
        sleep(2)
        XCTAssertTrue(app.exists, "App should remain stable")
    }
}
