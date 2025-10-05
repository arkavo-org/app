//
//  GetStartedUITests.swift
//  ArkavoUITests
//

import XCTest

final class GetStartedUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTapGetStartedAndScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        // Look for a button whose label contains "Get Started" (case-insensitive)
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "Get Started")
        let button = app.buttons.matching(predicate).firstMatch

        // Wait for up to 10s for the button; if not present, still capture a screenshot for debugging
        let found = button.waitForExistence(timeout: 10)
        if found {
            if button.isHittable {
                button.tap()
            } else {
                // Attempt coordinate tap at the element's frame center if not hittable
                let frame = button.frame
                let coord = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
                coord.tap()
            }
            // Allow brief UI settle
            sleep(1)
        }

        // Always attach a screenshot of the current UI state
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = found ? "After Get Started Tap" : "Launch Screen (Get Started not found)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

