import XCTest

final class PublicistUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testPublicistSectionExistsInSidebar() throws {
        // Look for the Publicist section in sidebar
        let publicistButton = app.buttons["Publicist"].firstMatch
        XCTAssertTrue(publicistButton.waitForExistence(timeout: 5), "Publicist section should exist in sidebar")
    }

    func testNavigateToPublicistView() throws {
        let publicistButton = app.buttons["Publicist"].firstMatch
        guard publicistButton.waitForExistence(timeout: 5) else {
            XCTFail("Publicist button not found")
            return
        }

        publicistButton.tap()

        // Platform selector should be visible
        let platformLabel = app.staticTexts["Platform"]
        XCTAssertTrue(platformLabel.waitForExistence(timeout: 3), "Platform label should be visible")
    }

    func testPlatformSelectorVisible() throws {
        let publicistButton = app.buttons["Publicist"].firstMatch
        guard publicistButton.waitForExistence(timeout: 5) else {
            XCTFail("Publicist button not found")
            return
        }

        publicistButton.tap()

        // Check that platform buttons exist
        let blueskyButton = app.buttons["Platform_Bluesky"]
        XCTAssertTrue(blueskyButton.waitForExistence(timeout: 3), "Bluesky platform button should exist")
    }

    func testContentTypeButtonsExist() throws {
        let publicistButton = app.buttons["Publicist"].firstMatch
        guard publicistButton.waitForExistence(timeout: 5) else {
            XCTFail("Publicist button not found")
            return
        }

        publicistButton.tap()

        let draftButton = app.buttons["ContentType_Draft Post"]
        XCTAssertTrue(draftButton.waitForExistence(timeout: 3), "Draft Post content type should exist")
    }

    func testGenerateButtonExists() throws {
        let publicistButton = app.buttons["Publicist"].firstMatch
        guard publicistButton.waitForExistence(timeout: 5) else {
            XCTFail("Publicist button not found")
            return
        }

        publicistButton.tap()

        let generateButton = app.buttons["Btn_Generate"]
        XCTAssertTrue(generateButton.waitForExistence(timeout: 3), "Generate button should exist")
    }
}
