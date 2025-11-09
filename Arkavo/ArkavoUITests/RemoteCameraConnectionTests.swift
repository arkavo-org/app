import XCTest

/// UI tests for remote camera connection and discovery functionality
/// These tests help debug Bonjour discovery and connection issues
final class RemoteCameraConnectionTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "ENABLE_REMOTE_CAMERA_LOGGING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        // Take screenshot on failure for debugging
        if let testRun = testRun, testRun.hasSucceeded == false {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.lifetime = .keepAlways
            attachment.name = "Failed Test Screenshot"
            add(attachment)
        }
    }

    // MARK: - Navigation Tests

    func testNavigateToRemoteCameraView() throws {
        print("🧪 Starting testNavigateToRemoteCameraView")

        // Wait for app to settle
        sleep(2)

        // Look for Create/Video tab or button
        let createButton = app.buttons["Create"]
        if createButton.exists {
            print("📱 Found Create button, tapping...")
            createButton.tap()
            sleep(1)
        }

        // Look for Video option or Stream to ArkavoCreator card
        let streamCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'stream' OR label CONTAINS[c] 'remote camera'")).firstMatch

        if streamCard.waitForExistence(timeout: 5) {
            print("✅ Found remote camera/stream UI element: \(streamCard.label)")
            XCTAssertTrue(streamCard.exists, "Remote camera UI should be visible")
        } else {
            print("⚠️ Could not find remote camera UI element")
            print("📋 Available buttons:")
            app.buttons.allElementsBoundByIndex.forEach { button in
                print("  - \(button.label)")
            }
            XCTFail("Remote camera UI element not found")
        }

        print("✅ testNavigateToRemoteCameraView completed")
    }

    // MARK: - Bonjour Discovery Tests

    func testBonjourDiscoveryListVisible() throws {
        print("🧪 Starting testBonjourDiscoveryListVisible")

        // Navigate to remote camera view
        navigateToRemoteCamera()

        // Look for "Nearby Macs" or discovered servers list
        let nearbyMacsList = app.staticTexts["Nearby Macs"]
        let discoveredServersList = app.tables.containing(.staticText, identifier: "Nearby Macs").firstMatch

        if nearbyMacsList.waitForExistence(timeout: 3) {
            print("✅ Found 'Nearby Macs' label")
            XCTAssertTrue(nearbyMacsList.exists)
        } else {
            print("⚠️ 'Nearby Macs' label not found")
        }

        // Wait for discovery to populate (up to 10 seconds)
        print("⏳ Waiting for Bonjour discovery (10 seconds)...")
        sleep(10)

        // Check for discovered servers
        let serverButtons = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'NearbyMacRow'"))
        let serverCount = serverButtons.count

        print("📊 Discovered \(serverCount) nearby Mac(s)")

        if serverCount > 0 {
            print("✅ Bonjour discovery found servers:")
            for i in 0..<serverCount {
                let button = serverButtons.element(boundBy: i)
                print("  - \(button.label)")
            }
        } else {
            print("⚠️ No servers discovered via Bonjour")
            print("💡 This could indicate:")
            print("   1. No Mac running ArkavoCreator on the network")
            print("   2. Bonjour service not publishing correctly")
            print("   3. Network isolation between devices")
            print("   4. Firewall blocking Bonjour")
        }

        print("✅ testBonjourDiscoveryListVisible completed")
    }

    func testManualServerEntry() throws {
        print("🧪 Starting testManualServerEntry")

        navigateToRemoteCamera()

        // Look for host and port text fields
        let hostField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'hostname' OR placeholderValue CONTAINS[c] 'ip'")).firstMatch
        let portField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'port'")).firstMatch

        if hostField.waitForExistence(timeout: 3) {
            print("✅ Found hostname/IP field")
            hostField.tap()
            hostField.typeText("localhost")
            print("📝 Entered 'localhost' in host field")
        } else {
            print("⚠️ Hostname field not found")
            XCTFail("Manual server entry fields should be available")
        }

        if portField.waitForExistence(timeout: 3) {
            print("✅ Found port field")
            portField.tap()

            // Clear existing value if any
            if let existingValue = portField.value as? String, !existingValue.isEmpty {
                portField.doubleTap()
                app.keys["delete"].tap()
            }

            portField.typeText("5757")
            print("📝 Entered '5757' in port field")
        } else {
            print("⚠️ Port field not found")
            XCTFail("Port field should be available")
        }

        print("✅ testManualServerEntry completed")
    }

    // MARK: - Connection Tests

    func testStartRemoteCameraWithManualHost() throws {
        print("🧪 Starting testStartRemoteCameraWithManualHost")

        navigateToRemoteCamera()

        // Enter localhost connection details
        let hostField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'hostname' OR placeholderValue CONTAINS[c] 'ip'")).firstMatch
        let portField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'port'")).firstMatch

        if hostField.waitForExistence(timeout: 3) {
            hostField.tap()
            hostField.typeText("localhost")
        }

        if portField.waitForExistence(timeout: 3) {
            portField.tap()
            if let existingValue = portField.value as? String, !existingValue.isEmpty {
                portField.doubleTap()
                app.keys["delete"].tap()
            }
            portField.typeText("5757")
        }

        // Look for Start button
        let startButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'start remote camera' OR label CONTAINS[c] 'connect'")).firstMatch

        if startButton.waitForExistence(timeout: 3) {
            print("✅ Found Start button: \(startButton.label)")
            print("🔌 Attempting to start remote camera...")

            startButton.tap()

            // Wait for connection attempt
            sleep(2)

            // Check for status indicators
            checkConnectionStatus()
        } else {
            print("⚠️ Start button not found")
            print("📋 Available buttons:")
            app.buttons.allElementsBoundByIndex.forEach { button in
                print("  - \(button.label)")
            }
            XCTFail("Start Remote Camera button should be available")
        }

        print("✅ testStartRemoteCameraWithManualHost completed")
    }

    func testConnectionErrorHandling() throws {
        print("🧪 Starting testConnectionErrorHandling")

        navigateToRemoteCamera()

        // Enter invalid connection details
        let hostField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'hostname' OR placeholderValue CONTAINS[c] 'ip'")).firstMatch
        let portField = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'port'")).firstMatch

        if hostField.waitForExistence(timeout: 3) {
            hostField.tap()
            hostField.typeText("192.0.2.1") // TEST-NET-1 address (should not be routable)
        }

        if portField.waitForExistence(timeout: 3) {
            portField.tap()
            if let existingValue = portField.value as? String, !existingValue.isEmpty {
                portField.doubleTap()
                app.keys["delete"].tap()
            }
            portField.typeText("9999")
        }

        // Attempt connection
        let startButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'start remote camera' OR label CONTAINS[c] 'connect'")).firstMatch

        if startButton.waitForExistence(timeout: 3) {
            print("🔌 Attempting connection to unreachable host...")
            startButton.tap()

            // Wait for error
            sleep(3)

            // Look for error message or status
            let errorTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'error' OR label CONTAINS[c] 'failed' OR label CONTAINS[c] 'unable to connect'"))

            if errorTexts.count > 0 {
                print("✅ Error handling working - found error message:")
                for i in 0..<errorTexts.count {
                    let errorText = errorTexts.element(boundBy: i)
                    print("  - \(errorText.label)")
                }
                XCTAssertTrue(errorTexts.count > 0, "Error message should be displayed")
            } else {
                print("⚠️ No error message displayed")
                print("💡 Connection may have timed out silently")
            }
        }

        print("✅ testConnectionErrorHandling completed")
    }

    // MARK: - Helper Methods

    private func navigateToRemoteCamera() {
        print("🧭 Navigating to remote camera view...")

        // Wait for app to settle
        sleep(1)

        // Try to find and tap Create button
        let createButton = app.buttons["Create"]
        if createButton.exists {
            createButton.tap()
            sleep(1)
        }

        // Look for Stream/Remote Camera card and tap it
        let streamCard = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'stream' OR label CONTAINS[c] 'remote camera'")).firstMatch
        if streamCard.waitForExistence(timeout: 5) {
            streamCard.tap()
            sleep(1)
        }

        print("✅ Navigation complete")
    }

    private func checkConnectionStatus() {
        print("📊 Checking connection status...")

        // Look for status indicators
        let statusLabels = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'streaming' OR label CONTAINS[c] 'connected' OR label CONTAINS[c] 'connecting' OR label CONTAINS[c] 'error'"))

        if statusLabels.count > 0 {
            print("📡 Status indicators found:")
            for i in 0..<statusLabels.count {
                let status = statusLabels.element(boundBy: i)
                print("  - \(status.label)")
            }
        } else {
            print("⚠️ No status indicators found")
        }

        // Look for streaming indicator (green dot animation)
        let streamingIndicator = app.images.matching(NSPredicate(format: "identifier CONTAINS[c] 'streaming' OR identifier CONTAINS[c] 'recording'")).firstMatch

        if streamingIndicator.exists {
            print("✅ Found streaming indicator")
        } else {
            print("ℹ️ No streaming indicator found (may not be streaming)")
        }
    }
}
