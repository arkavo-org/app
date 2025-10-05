import XCTest

final class RegistrationFlowUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ArkavoSkipPasskey"]
        app.launch()
    }

    func testCompleteRegistrationFlow() throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let testHandle = "testuser\(timestamp)"

        // Wait for Welcome screen
        let welcomeTitle = app.staticTexts["Welcome"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 5), "Welcome screen should appear")

        // Tap Get Started
        let getStartedButton = app.buttons["Get Started"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 3))
        getStartedButton.tap()

        // Wait for EULA screen
        let eulaTitle = app.staticTexts["Terms of Service"]
        XCTAssertTrue(eulaTitle.waitForExistence(timeout: 3), "EULA screen should appear")

        // Accept EULA
        let eulaCheckbox = app.buttons["EULA Agreement Checkbox"]
        XCTAssertTrue(eulaCheckbox.waitForExistence(timeout: 3))
        eulaCheckbox.tap()

        let acceptButton = app.buttons["Accept & Continue"]
        XCTAssertTrue(acceptButton.waitForExistence(timeout: 2))
        XCTAssertTrue(acceptButton.isEnabled, "Accept button should be enabled after checking box")
        acceptButton.tap()

        // Wait for handle screen
        let handleTitle = app.staticTexts["Create Handle"]
        XCTAssertTrue(handleTitle.waitForExistence(timeout: 3), "Handle screen should appear")

        // Enter handle
        let handleField = app.textFields["handleTextField"]
        XCTAssertTrue(handleField.waitForExistence(timeout: 3))
        handleField.tap()
        handleField.typeText(testHandle)

        // Wait for availability check
        let availableText = app.staticTexts["Available"]
        XCTAssertTrue(availableText.waitForExistence(timeout: 5), "Handle should be available")

        // Continue/Finish Registration
        let finishButton = app.buttons["Finish Registration"]
        XCTAssertTrue(finishButton.waitForExistence(timeout: 2))
        XCTAssertTrue(finishButton.isEnabled, "Finish button should be enabled")
        finishButton.tap()

        // Wait for registration to complete (app should navigate away from registration)
        let registrationComplete = welcomeTitle.waitForNonExistence(timeout: 10)
        XCTAssertTrue(registrationComplete, "Should exit registration flow")

        print("✅ Registration completed successfully with handle: \(testHandle)")
    }
}

extension XCUIElement {
    func waitForNonExistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
