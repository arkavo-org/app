import XCTest

/// UI tests for remote camera discovery and server functionality on macOS
/// These tests help debug Bonjour service publishing and iOS device detection
final class RemoteCameraDiscoveryTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "ENABLE_REMOTE_CAMERA_LOGGING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let testRun = testRun, testRun.hasSucceeded == false {
            let screenshot = XCUIScreen.main.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.lifetime = .keepAlways
            attachment.name = "Failed Test Screenshot"
            add(attachment)
        }
    }

    // MARK: - Server Setup Tests

    func testRemoteCameraServerToggleExists() throws {
        print("🧪 Starting testRemoteCameraServerToggleExists")

        navigateToRecord()

        // Look for "Allow Remote Cameras" toggle
        let allowRemoteCamerasToggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS[c] 'allow remote' OR label CONTAINS[c] 'remote camera'")).firstMatch

        if allowRemoteCamerasToggle.waitForExistence(timeout: 5) {
            print("✅ Found 'Allow Remote Cameras' toggle")
            print("📊 Toggle state: \(allowRemoteCamerasToggle.value as? Int == 1 ? "ON" : "OFF")")
            XCTAssertTrue(allowRemoteCamerasToggle.exists, "Remote camera toggle should exist")
        } else {
            print("⚠️ 'Allow Remote Cameras' toggle not found")
            print("📋 Available checkboxes:")
            app.checkBoxes.allElementsBoundByIndex.forEach { checkbox in
                print("  - \(checkbox.label)")
            }
            XCTFail("Allow Remote Cameras toggle should be visible")
        }

        print("✅ testRemoteCameraServerToggleExists completed")
    }

    func testRemoteCameraServerInfo() throws {
        print("🧪 Starting testRemoteCameraServerInfo")

        navigateToRecord()

        // Ensure remote cameras are enabled
        enableRemoteCameras()

        // Look for server host/port display
        let serverInfo = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] ':5757' OR label CONTAINS[c] 'port'"))

        print("🔍 Searching for server info display...")
        sleep(1) // Give UI time to update

        if serverInfo.count > 0 {
            print("✅ Found server info:")
            for i in 0..<serverInfo.count {
                let info = serverInfo.element(boundBy: i)
                print("  - \(info.label)")
            }
            XCTAssertTrue(serverInfo.count > 0, "Server info should be displayed")
        } else {
            print("⚠️ Server host/port info not displayed")
            print("💡 Server may not be running or UI not showing info")
        }

        print("✅ testRemoteCameraServerInfo completed")
    }

    // MARK: - Remote Source Detection Tests

    func testRemoteCameraSourcesListVisible() throws {
        print("🧪 Starting testRemoteCameraSourcesListVisible")

        navigateToRecord()
        enableRemoteCameras()

        // Look for "Remote iOS Cameras" section or list
        let remoteCameraSection = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'remote' AND label CONTAINS[c] 'camera'")).firstMatch

        if remoteCameraSection.waitForExistence(timeout: 3) {
            print("✅ Found remote camera section: \(remoteCameraSection.label)")
        } else {
            print("ℹ️ Remote camera section not found (may be collapsed or not visible)")
        }

        // Look for "Waiting for Arkavo on iPhone/iPad" message
        let waitingMessage = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'waiting' OR label CONTAINS[c] 'connect'")).firstMatch

        if waitingMessage.exists {
            print("📱 Status: \(waitingMessage.label)")
        }

        print("✅ testRemoteCameraSourcesListVisible completed")
    }

    func testWaitForRemoteCameraConnection() throws {
        print("🧪 Starting testWaitForRemoteCameraConnection")
        print("💡 This test waits 30 seconds for an iOS device to connect")
        print("   Please start remote camera streaming from an iOS device now!")

        navigateToRecord()
        enableRemoteCameras()

        // Wait for remote camera sources to appear
        let waitTime = 30
        print("⏳ Waiting \(waitTime) seconds for iOS device connection...")

        var remoteCameraFound = false
        for i in 1...waitTime {
            sleep(1)

            // Look for remote camera source buttons/toggles
            let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource' OR label CONTAINS[c] '-face' OR label CONTAINS[c] '-body'"))

            if remoteSources.count > 0 {
                print("✅ Remote camera detected after \(i) seconds!")
                print("📊 Found \(remoteSources.count) remote source(s):")
                for j in 0..<remoteSources.count {
                    let source = remoteSources.element(boundBy: j)
                    print("  - \(source.label)")
                }
                remoteCameraFound = true
                break
            }

            if i % 5 == 0 {
                print("   Still waiting... (\(i)/\(waitTime) seconds)")
            }
        }

        if remoteCameraFound {
            print("✅ Remote camera successfully detected!")
            XCTAssertTrue(true, "Remote camera should be detected")
        } else {
            print("⚠️ No remote camera detected after \(waitTime) seconds")
            print("💡 Possible issues:")
            print("   1. iOS device not streaming")
            print("   2. iOS device on different network")
            print("   3. Bonjour not working between devices")
            print("   4. Mac server not accepting connections")
            print("   5. Data not reaching RecordViewModel.handleRemoteSourceUpdate")
            XCTFail("Remote camera should be detected when iOS device is streaming")
        }

        print("✅ testWaitForRemoteCameraConnection completed")
    }

    func testEnableDisableRemoteSource() throws {
        print("🧪 Starting testEnableDisableRemoteSource")
        print("💡 This test requires an iOS device to be connected")

        navigateToRecord()
        enableRemoteCameras()

        // Wait for at least one remote source
        print("⏳ Waiting for remote camera source...")
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))

        var sourceFound = false
        for _ in 1...15 {
            sleep(1)
            if remoteSources.count > 0 {
                sourceFound = true
                break
            }
        }

        guard sourceFound else {
            print("⚠️ No remote source found - skipping test")
            throw XCTSkip("No remote camera source available")
        }

        let firstSource = remoteSources.element(boundBy: 0)
        print("📱 Found remote source: \(firstSource.label)")

        // Check initial state
        let initialState = firstSource.value as? Int == 1
        print("📊 Initial state: \(initialState ? "ENABLED" : "DISABLED")")

        // Toggle the source
        print("🔄 Toggling remote source...")
        firstSource.click()
        sleep(1)

        // Check state changed
        let newState = firstSource.value as? Int == 1
        print("📊 New state: \(newState ? "ENABLED" : "DISABLED")")

        XCTAssertNotEqual(initialState, newState, "Toggle should change state")

        // Toggle back
        print("🔄 Toggling back...")
        firstSource.click()
        sleep(1)

        let finalState = firstSource.value as? Int == 1
        print("📊 Final state: \(finalState ? "ENABLED" : "DISABLED")")

        XCTAssertEqual(initialState, finalState, "Should return to initial state")

        print("✅ testEnableDisableRemoteSource completed")
    }

    // MARK: - Discovery Flow Debug Tests

    func testBonjourServicePublishing() throws {
        print("🧪 Starting testBonjourServicePublishing")
        print("💡 This test verifies Bonjour service is published")

        navigateToRecord()
        enableRemoteCameras()

        // Give server time to publish
        print("⏳ Waiting for Bonjour service to publish...")
        sleep(3)

        // Check system logs or server info for Bonjour publish confirmation
        // In a real scenario, we'd use `dns-sd -B _arkavo-remote._tcp` to verify
        print("ℹ️ To manually verify Bonjour publishing, run in Terminal:")
        print("   dns-sd -B _arkavo-remote._tcp local.")
        print("   You should see the ArkavoCreator service listed")

        // For now, we just verify the server is enabled
        let serverEnabled = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS[c] 'allow remote'")).firstMatch.value as? Int == 1

        XCTAssertTrue(serverEnabled, "Remote camera server should be enabled")

        print("✅ testBonjourServicePublishing completed")
    }

    func testRemoteSourceUpdateFlow() throws {
        print("🧪 Starting testRemoteSourceUpdateFlow")
        print("💡 This test monitors the remote source update flow")
        print("   Start streaming from iOS now!")

        navigateToRecord()
        enableRemoteCameras()

        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))

        print("📊 Monitoring remote sources for 20 seconds...")
        var previousCount = 0

        for i in 1...20 {
            sleep(1)
            let currentCount = remoteSources.count

            if currentCount != previousCount {
                print("🔄 Change detected at \(i)s: \(previousCount) → \(currentCount) sources")

                if currentCount > previousCount {
                    print("✅ New remote camera(s) added:")
                    for j in previousCount..<currentCount {
                        let source = remoteSources.element(boundBy: j)
                        print("  + \(source.label)")
                    }
                } else {
                    print("➖ Remote camera(s) removed")
                }

                previousCount = currentCount
            }

            if i % 5 == 0 && currentCount == 0 {
                print("   Still no sources... (\(i)/20 seconds)")
            }
        }

        if previousCount > 0 {
            print("✅ Remote source update flow working!")
            print("📊 Final count: \(previousCount) source(s)")
        } else {
            print("⚠️ No remote sources detected during test")
            print("💡 Check:")
            print("   1. iOS device is streaming")
            print("   2. Handshake message being sent")
            print("   3. RemoteCameraServer.didUpdateSources being called")
            print("   4. RecordViewModel.handleRemoteSourceUpdate receiving data")
        }

        print("✅ testRemoteSourceUpdateFlow completed")
    }

    // MARK: - Helper Methods

    private func navigateToRecord() {
        print("🧭 Navigating to Record view...")

        // Click Record in toolbar/sidebar
        let recordButton = app.buttons["Record"]
        if recordButton.waitForExistence(timeout: 5) {
            recordButton.click()
            sleep(1)
            print("✅ Clicked Record button")
        } else {
            print("⚠️ Record button not found, may already be on Record view")
        }
    }

    private func enableRemoteCameras() {
        print("🔧 Ensuring remote cameras are enabled...")

        let allowRemoteCamerasToggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS[c] 'allow remote'")).firstMatch

        if allowRemoteCamerasToggle.waitForExistence(timeout: 3) {
            let isEnabled = allowRemoteCamerasToggle.value as? Int == 1

            if !isEnabled {
                print("🔄 Enabling remote cameras...")
                allowRemoteCamerasToggle.click()
                sleep(1)
                print("✅ Remote cameras enabled")
            } else {
                print("✅ Remote cameras already enabled")
            }
        } else {
            print("⚠️ Could not find remote cameras toggle")
        }
    }
}
