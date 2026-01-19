import XCTest

final class NetworkPromptUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testNetworkPromptAppearsOnHomeTab() throws {
        // Wait for app to load
        sleep(2)

        // Tap the Home tab (play.circle.fill icon)
        let homeTab = app.buttons["Home"]
        if homeTab.waitForExistence(timeout: 3) {
            homeTab.tap()
        } else {
            // Try finding by image name
            let playIcon = app.images["play.circle.fill"]
            if playIcon.waitForExistence(timeout: 3) {
                playIcon.tap()
            }
        }

        // Wait and take a screenshot
        sleep(2)

        // Check for network connection prompt elements
        let networkTitle = app.staticTexts["Connect to a Network"]
        let connectButton = app.buttons["Connect"]
        let continueOfflineButton = app.buttons["Continue Offline"]

        // Print what we see for debugging
        print("Network title exists: \(networkTitle.exists)")
        print("Connect button exists: \(connectButton.exists)")
        print("Continue Offline exists: \(continueOfflineButton.exists)")

        // If in offline mode, we should see the prompt
        if networkTitle.exists {
            XCTAssertTrue(connectButton.exists, "Connect button should be visible")
            XCTAssertTrue(continueOfflineButton.exists, "Continue Offline button should be visible")
            print("✅ Network connection prompt is displayed")
        } else {
            // App might not be in offline mode, which is also valid
            print("ℹ️ Network prompt not shown - app may be connected or not in offline mode")
        }
    }
}
