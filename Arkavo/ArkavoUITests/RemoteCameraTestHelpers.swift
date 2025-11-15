import XCTest

/// Shared helper utilities for remote camera UI testing
enum RemoteCameraTestHelpers {

    /// Waits for an element to not exist
    /// - Parameters:
    ///   - element: The element to check
    ///   - timeout: Maximum time to wait
    /// - Returns: True if element disappeared within timeout
    static func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Logs all visible buttons for debugging
    static func logVisibleButtons(_ app: XCUIApplication, prefix: String = "") {
        print("\(prefix)📋 Visible buttons:")
        app.buttons.allElementsBoundByIndex.forEach { button in
            print("\(prefix)  - \(button.label) [exists: \(button.exists), hittable: \(button.isHittable)]")
        }
    }

    /// Logs all visible text fields for debugging
    static func logVisibleTextFields(_ app: XCUIApplication, prefix: String = "") {
        print("\(prefix)📋 Visible text fields:")
        app.textFields.allElementsBoundByIndex.forEach { field in
            if let placeholder = field.placeholderValue {
                print("\(prefix)  - Placeholder: \(placeholder)")
            }
            if let value = field.value as? String {
                print("\(prefix)    Value: \(value)")
            }
        }
    }

    /// Logs all visible static texts for debugging
    static func logVisibleStaticTexts(_ app: XCUIApplication, prefix: String = "") {
        print("\(prefix)📋 Visible static texts:")
        app.staticTexts.allElementsBoundByIndex.forEach { text in
            print("\(prefix)  - \(text.label)")
        }
    }

    /// Takes a labeled screenshot for debugging
    static func takeScreenshot(named name: String, attachTo test: XCTestCase) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
        print("📸 Screenshot taken: \(name)")
    }

    /// Waits for app to settle and be idle
    static func waitForIdle(_ app: XCUIApplication, seconds: TimeInterval = 1) {
        sleep(UInt32(seconds))
    }

    /// Clears a text field completely
    static func clearTextField(_ textField: XCUIElement) {
        textField.tap()
        textField.doubleTap() // Select all

        // Try delete key
        if let app = textField.application {
            let deleteKey = app.keys["delete"]
            if deleteKey.exists {
                deleteKey.tap()
                return
            }
        }

        // Fallback: type empty string
        textField.typeText("")
    }

    /// Enters text into a field, clearing it first
    static func enterText(_ text: String, into textField: XCUIElement) {
        clearTextField(textField)
        textField.typeText(text)
    }
}

/// Extension to make XCUIElement navigation easier
extension XCUIElement {
    var application: XCUIApplication? {
        var current: XCUIElement? = self
        while let element = current {
            if let app = element as? XCUIApplication {
                return app
            }
            current = nil // In UI testing, we can't traverse up easily
        }
        return nil
    }
}
