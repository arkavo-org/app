import XCTest

/// Shared helper utilities for remote camera UI testing on macOS
enum RemoteCameraTestHelpers {

    /// Navigates to the Record view
    static func navigateToRecord(_ app: XCUIApplication) {
        print("🧭 Navigating to Record view...")
        let recordButton = app.buttons["Record"]
        if recordButton.waitForExistence(timeout: 5) {
            recordButton.click()
            sleep(1)
            print("✅ Navigated to Record view")
        } else {
            print("ℹ️ Already on Record view or button not found")
        }
    }

    /// Navigates to the Library view
    static func navigateToLibrary(_ app: XCUIApplication) {
        print("🧭 Navigating to Library view...")
        let libraryButton = app.buttons["Library"]
        if libraryButton.waitForExistence(timeout: 5) {
            libraryButton.click()
            sleep(1)
            print("✅ Navigated to Library view")
        }
    }

    /// Logs all visible buttons for debugging
    static func logVisibleButtons(_ app: XCUIApplication, prefix: String = "") {
        print("\(prefix)📋 Visible buttons:")
        app.buttons.allElementsBoundByIndex.forEach { button in
            print("\(prefix)  - \(button.label) [exists: \(button.exists), enabled: \(button.isEnabled)]")
        }
    }

    /// Logs all visible checkboxes for debugging
    static func logVisibleCheckboxes(_ app: XCUIApplication, prefix: String = "") {
        print("\(prefix)📋 Visible checkboxes:")
        app.checkBoxes.allElementsBoundByIndex.forEach { checkbox in
            let state = checkbox.value as? Int == 1 ? "ON" : "OFF"
            print("\(prefix)  - \(checkbox.label) [\(state)]")
        }
    }

    /// Logs all visible static texts for debugging
    static func logVisibleStaticTexts(_ app: XCUIApplication, prefix: String = "", limit: Int = 50) {
        print("\(prefix)📋 Visible static texts (first \(limit)):")
        let texts = app.staticTexts.allElementsBoundByIndex
        let count = min(texts.count, limit)
        for i in 0..<count {
            print("\(prefix)  - \(texts[i].label)")
        }
        if texts.count > limit {
            print("\(prefix)  ... and \(texts.count - limit) more")
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

    /// Waits for an element to exist
    static func waitForExistence(_ element: XCUIElement, timeout: TimeInterval = 5, description: String = "") -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        if exists {
            print("✅ Found: \(description.isEmpty ? element.label : description)")
        } else {
            print("⚠️ Not found: \(description.isEmpty ? element.label : description)")
        }
        return exists
    }

    /// Ensures a checkbox is in the desired state
    static func setCheckbox(_ checkbox: XCUIElement, to state: Bool) {
        let currentState = checkbox.value as? Int == 1
        if currentState != state {
            print("🔄 Toggling checkbox: \(checkbox.label) (\(currentState ? "ON" : "OFF") → \(state ? "ON" : "OFF"))")
            checkbox.click()
            sleep(1)
        } else {
            print("✅ Checkbox already in desired state: \(checkbox.label) (\(state ? "ON" : "OFF"))")
        }
    }

    /// Waits for app to be idle
    static func waitForIdle(seconds: TimeInterval = 1) {
        sleep(UInt32(seconds))
    }

    /// Monitors element count changes over time
    static func monitorElementCount(
        _ query: XCUIElementQuery,
        description: String,
        duration: TimeInterval = 10,
        interval: TimeInterval = 1,
        onChange: ((Int, Int) -> Void)? = nil
    ) -> Int {
        print("📊 Monitoring \(description) for \(Int(duration)) seconds...")
        var previousCount = query.count
        var totalChecks = 0

        for i in stride(from: interval, through: duration, by: interval) {
            sleep(UInt32(interval))
            totalChecks += 1

            let currentCount = query.count
            if currentCount != previousCount {
                print("🔄 Change detected at \(Int(i))s: \(previousCount) → \(currentCount)")
                onChange?(previousCount, currentCount)
                previousCount = currentCount
            }

            if Int(i) % 5 == 0 && currentCount == 0 {
                print("   Still monitoring... (\(Int(i))/\(Int(duration))s, \(currentCount) items)")
            }
        }

        print("📊 Monitoring complete: final count = \(previousCount) (\(totalChecks) checks)")
        return previousCount
    }
}
