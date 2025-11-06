import XCTest

final class HYPERforumUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launches successfully
        XCTAssertTrue(app.exists)
    }

    func testWelcomeScreen() throws {
        let app = XCUIApplication()
        app.launch()

        // Check if welcome screen elements are present
        let titleText = app.staticTexts["HYPΞRforum"]
        XCTAssertTrue(titleText.waitForExistence(timeout: 5))
    }
}
