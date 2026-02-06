import XCTest

final class PatreonMembershipScreenshotUITests: XCTestCase {
    var app: XCUIApplication!
    let screenshotsDir = "/tmp/arkavo_screenshots"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        
        // Create screenshots directory
        try? FileManager.default.createDirectory(
            atPath: screenshotsDir,
            withIntermediateDirectories: true
        )
        
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Screenshot Helpers

    func takeScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let path = "\(screenshotsDir)/\(name).png"
        do {
            try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
            print("Screenshot saved: \(path)")
        } catch {
            print("Failed to save screenshot: \(error)")
        }
    }

    func saveTestScreenshot(name: String) {
        // Use XCTest's built-in screenshot attachment
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Navigation Helpers

    func navigateToConnectedAccounts() {
        // Wait for app to load
        sleep(2)

        // Tap "Continue Offline" if present
        let continueOfflineButton = app.buttons["Continue Offline"]
        if continueOfflineButton.waitForExistence(timeout: 5) {
            continueOfflineButton.tap()
        }

        sleep(2)

        // Navigate to Profile tab
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
        }

        sleep(1)

        // Tap on Account row
        let accountButton = app.buttons["Account"]
        if accountButton.waitForExistence(timeout: 5) {
            accountButton.tap()
        } else {
            let accountText = app.staticTexts["Account"]
            if accountText.waitForExistence(timeout: 3) {
                accountText.tap()
            }
        }

        sleep(1)

        // Tap Connected Accounts
        let connectedAccountsLink = app.buttons["Manage Connected Accounts"]
        if connectedAccountsLink.waitForExistence(timeout: 5) {
            connectedAccountsLink.tap()
        }

        sleep(1)
    }

    // MARK: - Screenshot Tests

    /// Captures screenshot of Connected Accounts screen with Patreon status
    func testScreenshot_ConnectedAccounts_PatreonLinked() throws {
        navigateToConnectedAccounts()

        // Verify we're on Connected Accounts
        let navigationTitle = app.navigationBars["Connected Accounts"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 5))

        // Take screenshot of Connected Accounts screen
        takeScreenshot(name: "01_connected_accounts")
        saveTestScreenshot(name: "Connected_Accounts_Screen")

        // Check if Patreon is connected
        let patreonConnected = app.staticTexts["Connected"].exists

        if patreonConnected {
            // Look for "Supported Creators" row with badge
            let supportedCreators = app.buttons["Supported Creators"]
            if supportedCreators.waitForExistence(timeout: 3) {
                // Take screenshot showing the badge
                takeScreenshot(name: "02_supported_creators_row_with_badge")
                saveTestScreenshot(name: "Supported_Creators_Row")

                // Tap to navigate to memberships list
                supportedCreators.tap()
                sleep(1)

                // Screenshot 3: Memberships list
                takeScreenshot(name: "03_memberships_list")
                saveTestScreenshot(name: "Memberships_List")

                // Tap first creator with "NEW" badge if exists
                let newPill = app.staticTexts["NEW"].firstMatch
                if newPill.waitForExistence(timeout: 3) {
                    newPill.tap()
                    sleep(1)

                    // Screenshot 4: Member content view
                    takeScreenshot(name: "04_member_content")
                    saveTestScreenshot(name: "Member_Content")
                } else {
                    // Tap any creator
                    let firstCreator = app.cells.firstMatch
                    if firstCreator.waitForExistence(timeout: 3) {
                        firstCreator.tap()
                        sleep(1)
                        takeScreenshot(name: "04_member_content_no_unread")
                        saveTestScreenshot(name: "Member_Content_No_Unread")
                    }
                }
            }
        } else {
            // Screenshot showing Patreon not connected
            takeScreenshot(name: "02_patreon_not_connected")
            saveTestScreenshot(name: "Patreon_Not_Connected")
        }
    }

    /// Captures screenshots of empty states
    func testScreenshot_EmptyStates() throws {
        navigateToConnectedAccounts()

        // Check if Patreon is connected
        let patreonConnected = app.staticTexts["Connected"].exists

        if patreonConnected {
            let supportedCreators = app.buttons["Supported Creators"]
            if supportedCreators.waitForExistence(timeout: 3) {
                supportedCreators.tap()
                sleep(1)

                // Check for empty state
                let emptyStateText = app.staticTexts["No Active Memberships"]
                if emptyStateText.waitForExistence(timeout: 3) {
                    takeScreenshot(name: "empty_memberships")
                    saveTestScreenshot(name: "Empty_Memberships")
                }
            }
        }
    }

    /// Captures screenshots of badge states
    func testScreenshot_BadgeStates() throws {
        navigateToConnectedAccounts()

        let patreonConnected = app.staticTexts["Connected"].exists

        if patreonConnected {
            // Check for badge on Supported Creators row
            let supportedCreators = app.buttons["Supported Creators"]
            if supportedCreators.waitForExistence(timeout: 3) {
                // Screenshot showing badge
                takeScreenshot(name: "badge_on_connected_accounts")
                saveTestScreenshot(name: "Badge_Connected_Accounts")

                supportedCreators.tap()
                sleep(1)

                // Screenshot showing multiple badges in list
                takeScreenshot(name: "badges_in_membership_list")
                saveTestScreenshot(name: "Badges_Membership_List")
            }
        }
    }

    /// Full flow screenshot capture
    func testScreenshot_FullPatreonFlow() throws {
        navigateToConnectedAccounts()

        // 1. Connected Accounts overview
        takeScreenshot(name: "flow_01_connected_accounts")

        let patreonConnected = app.staticTexts["Connected"].exists
        XCTAssertTrue(patreonConnected, "Patreon must be connected for this test")

        // 2. Tap Supported Creators
        let supportedCreators = app.buttons["Supported Creators"]
        XCTAssertTrue(supportedCreators.waitForExistence(timeout: 5), "Supported Creators button should exist")
        takeScreenshot(name: "flow_02_before_tap_supported_creators")

        supportedCreators.tap()
        sleep(1)
        takeScreenshot(name: "flow_03_memberships_list")

        // 3. Tap first membership
        let firstMembership = app.cells.firstMatch
        XCTAssertTrue(firstMembership.waitForExistence(timeout: 5), "Should have at least one membership")
        takeScreenshot(name: "flow_04_before_tap_membership")

        firstMembership.tap()
        sleep(1)
        takeScreenshot(name: "flow_05_member_content")

        // 4. Scroll content if exists
        let scrollView = app.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 3) {
            scrollView.swipeUp()
            sleep(0.5)
            takeScreenshot(name: "flow_06_scrolled_content")
        }
    }
}
