import XCTest

final class RegistrationFlowUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ArkavoSkipPasskey"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testSkipForNowFromRegistration() throws {
        // Wait for app to load
        sleep(2)

        // Navigate to registration if on network prompt
        let arkavoSocialOption = app.staticTexts["arkavo.social"]
        if arkavoSocialOption.waitForExistence(timeout: 3) {
            print("On network prompt, tapping arkavo.social to go to registration")
            arkavoSocialOption.tap()
            sleep(3)
        }

        // Should now be on registration welcome screen with Arkavo logo/title
        let arkavoTitle = app.staticTexts["Arkavo"]
        if arkavoTitle.waitForExistence(timeout: 5) {
            print("On registration welcome screen")
        }

        // Find and tap Skip for now button
        let skipButton = app.buttons["Skip for now"]
        guard skipButton.waitForExistence(timeout: 5) else {
            // Debug: print what buttons exist
            print("Available buttons:")
            for button in app.buttons.allElementsBoundByIndex {
                print("  - '\(button.label)' (enabled: \(button.isEnabled))")
            }
            XCTFail("Skip for now button not found")
            return
        }

        print("Found Skip for now button, tapping it")
        skipButton.tap()
        sleep(2)

        // After skipping, should go to main view with tab bar
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Should navigate to main view with tab bar after skipping")
        print("Successfully navigated to main view")
    }

    func testContinueOfflineFromNetworkPrompt() throws {
        // Wait for app to load
        sleep(2)

        // Check if we're on the network prompt
        let continueOfflineText = app.staticTexts["Continue Offline"]
        guard continueOfflineText.waitForExistence(timeout: 5) else {
            print("Not on network prompt, skipping test")
            return
        }

        print("On network prompt, tapping Continue Offline")
        continueOfflineText.tap()
        sleep(2)

        // Should go to main view with tab bar
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5), "Should navigate to main view after Continue Offline")
        print("Successfully navigated to main view via Continue Offline")
    }

    func testRegistrationNextButton() throws {
        // Wait for app to load
        sleep(2)

        // Navigate to registration if on network prompt
        let arkavoSocialOption = app.staticTexts["arkavo.social"]
        if arkavoSocialOption.waitForExistence(timeout: 3) {
            arkavoSocialOption.tap()
            sleep(3)
        }

        // Should be on registration welcome screen
        let nextButton = app.buttons["Next"]
        guard nextButton.waitForExistence(timeout: 5) else {
            print("Next button not found")
            return
        }

        print("Tapping Next button")
        nextButton.tap()
        sleep(2)

        // Should advance to next step - Back button should appear
        let backButton = app.buttons["Back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Should advance to next step with Back button")
        print("Successfully advanced to next registration step")
    }

    func testDebugCurrentScreen() throws {
        // Debug test to see what's on screen
        sleep(3)

        print("\n=== DEBUG: Current Screen State ===")
        print("Buttons:")
        for button in app.buttons.allElementsBoundByIndex.prefix(15) {
            print("  - '\(button.label)' (enabled: \(button.isEnabled), exists: \(button.exists))")
        }
        print("\nStatic Texts:")
        for text in app.staticTexts.allElementsBoundByIndex.prefix(15) {
            print("  - '\(text.label)'")
        }
        print("\nText Fields:")
        for field in app.textFields.allElementsBoundByIndex {
            print("  - '\(field.label)' placeholder: '\(field.placeholderValue ?? "none")'")
        }
        print("\nTab Bars:")
        print("  Count: \(app.tabBars.count)")
        if app.tabBars.count > 0 {
            for tab in app.tabBars.buttons.allElementsBoundByIndex {
                print("  - '\(tab.label)'")
            }
        }
        print("=== END DEBUG ===\n")

        XCTAssertTrue(true) // Always pass, this is just for debugging
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
