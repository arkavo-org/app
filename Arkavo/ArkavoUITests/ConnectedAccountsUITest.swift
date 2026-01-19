import XCTest

final class ConnectedAccountsUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testNavigateToConnectedAccounts() throws {
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
            // Try static text
            let accountText = app.staticTexts["Account"]
            if accountText.waitForExistence(timeout: 3) {
                accountText.tap()
            }
        }

        sleep(1)

        // Verify Connected Accounts section exists
        let connectedAccountsLink = app.buttons["Manage Connected Accounts"]
        XCTAssertTrue(connectedAccountsLink.waitForExistence(timeout: 5), "Connected Accounts link should exist")

        // Tap to navigate to Connected Accounts
        connectedAccountsLink.tap()

        sleep(1)

        // Verify we're on the Connected Accounts view
        let navigationTitle = app.navigationBars["Connected Accounts"]
        XCTAssertTrue(navigationTitle.waitForExistence(timeout: 5), "Should navigate to Connected Accounts view")

        // Verify Apple account row exists
        let appleText = app.staticTexts["Apple"]
        XCTAssertTrue(appleText.waitForExistence(timeout: 3), "Apple account row should exist")

        // Verify Patreon account row exists
        let patreonText = app.staticTexts["Patreon"]
        XCTAssertTrue(patreonText.waitForExistence(timeout: 3), "Patreon account row should exist")

        // Verify Connect button for Apple exists (since not connected)
        let connectButton = app.buttons["Connect"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 3), "Connect button should exist for Apple")
    }
}
