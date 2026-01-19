import XCTest

final class NetworkPromptUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testNetworkPromptOptions() throws {
        // Wait for app to load
        sleep(2)

        // Verify the three network options are displayed
        let arkavoOption = app.staticTexts["arkavo.social"]
        XCTAssertTrue(arkavoOption.waitForExistence(timeout: 5), "arkavo.social option should exist")

        let customServerOption = app.staticTexts["Custom Server"]
        XCTAssertTrue(customServerOption.waitForExistence(timeout: 3), "Custom Server option should exist")

        let continueOfflineOption = app.staticTexts["Continue Offline"]
        XCTAssertTrue(continueOfflineOption.waitForExistence(timeout: 3), "Continue Offline option should exist")
    }

    func testContinueOfflineFlow() throws {
        sleep(2)

        // Tap Continue Offline
        let continueOfflineOption = app.staticTexts["Continue Offline"]
        if continueOfflineOption.waitForExistence(timeout: 5) {
            continueOfflineOption.tap()
        }

        sleep(2)

        // Should navigate to main app - check for tab bar
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Should navigate to main app with tab bar")
    }

    func testCustomServerExpands() throws {
        sleep(2)

        // Tap Custom Server
        let customServerOption = app.staticTexts["Custom Server"]
        if customServerOption.waitForExistence(timeout: 5) {
            customServerOption.tap()
        }

        sleep(1)

        // Verify text field appears
        let textField = app.textFields["server.example.com"]
        XCTAssertTrue(textField.waitForExistence(timeout: 3), "Custom server text field should appear")

        // Verify Connect to Server button appears
        let connectButton = app.buttons["Connect to Server"]
        XCTAssertTrue(connectButton.waitForExistence(timeout: 3), "Connect to Server button should appear")
    }
}
