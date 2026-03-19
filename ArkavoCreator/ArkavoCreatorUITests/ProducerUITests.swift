import XCTest

final class ProducerUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launch()
    }

    func testProducerToggleExistsInStudio() throws {
        // Navigate to Studio
        let sidebar = app.navigationBars.firstMatch
        let studioButton = app.buttons["Studio"].firstMatch
        if studioButton.waitForExistence(timeout: 5) {
            studioButton.tap()
        }

        // Look for Producer toggle button
        let producerToggle = app.buttons["Toggle_Producer"]
        XCTAssertTrue(producerToggle.waitForExistence(timeout: 5), "Producer panel toggle should exist in Studio")
    }

    func testProducerPanelOpensAndCloses() throws {
        // Navigate to Studio
        let studioButton = app.buttons["Studio"].firstMatch
        if studioButton.waitForExistence(timeout: 5) {
            studioButton.tap()
        }

        let producerToggle = app.buttons["Toggle_Producer"]
        guard producerToggle.waitForExistence(timeout: 5) else {
            XCTFail("Producer toggle not found")
            return
        }

        // Open
        producerToggle.tap()

        // Verify panel content appears
        let producerLabel = app.staticTexts["Producer"]
        XCTAssertTrue(producerLabel.waitForExistence(timeout: 3), "Producer panel should show 'Producer' label")

        // Close
        producerToggle.tap()
    }

    func testStreamHealthSectionVisible() throws {
        // Navigate to Studio
        let studioButton = app.buttons["Studio"].firstMatch
        if studioButton.waitForExistence(timeout: 5) {
            studioButton.tap()
        }

        let producerToggle = app.buttons["Toggle_Producer"]
        guard producerToggle.waitForExistence(timeout: 5) else {
            XCTFail("Producer toggle not found")
            return
        }

        producerToggle.tap()

        let streamHealth = app.staticTexts["Stream Health"]
        XCTAssertTrue(streamHealth.waitForExistence(timeout: 3), "Stream Health section should be visible")
    }

    func testQuickActionButtonsExist() throws {
        // Navigate to Studio
        let studioButton = app.buttons["Studio"].firstMatch
        if studioButton.waitForExistence(timeout: 5) {
            studioButton.tap()
        }

        let producerToggle = app.buttons["Toggle_Producer"]
        guard producerToggle.waitForExistence(timeout: 5) else {
            XCTFail("Producer toggle not found")
            return
        }

        producerToggle.tap()

        let quickActions = app.staticTexts["Quick Actions"]
        XCTAssertTrue(quickActions.waitForExistence(timeout: 3), "Quick Actions section should be visible")
    }
}
