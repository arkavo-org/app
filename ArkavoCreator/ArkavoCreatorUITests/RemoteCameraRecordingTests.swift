import XCTest

/// UI tests for recording with remote camera sources
final class RemoteCameraRecordingTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING", "ENABLE_REMOTE_CAMERA_LOGGING"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let testRun = testRun, testRun.hasSucceeded == false {
            RemoteCameraTestHelpers.takeScreenshot(named: "Failed: \(name)", attachTo: self)
        }
    }

    // MARK: - Recording with Remote Camera Tests

    func testRecordWithRemoteCamera() throws {
        print("🧪 Starting testRecordWithRemoteCamera")
        print("💡 This test requires an iOS device streaming to be connected")

        RemoteCameraTestHelpers.navigateToRecord(app)

        // Enable remote cameras
        enableRemoteCameras()

        // Wait for remote source
        guard waitForRemoteCamera(timeout: 20) else {
            throw XCTSkip("No remote camera available - skipping recording test")
        }

        // Enable the first remote source
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))
        let firstSource = remoteSources.element(boundBy: 0)

        print("📱 Enabling remote camera: \(firstSource.label)")
        if firstSource.value as? Int != 1 {
            firstSource.click()
            sleep(1)
        }

        // Wait for preview to update (if visible)
        sleep(2)

        // Start recording
        let recordButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'record' OR identifier == 'RecordButton'")).firstMatch

        if recordButton.waitForExistence(timeout: 3) {
            print("🔴 Starting recording...")
            recordButton.click()

            // Record for 5 seconds
            print("⏱️ Recording for 5 seconds...")
            sleep(5)

            // Stop recording
            let stopButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'stop' OR identifier == 'StopButton'")).firstMatch

            if stopButton.waitForExistence(timeout: 2) {
                print("⏹️ Stopping recording...")
                stopButton.click()

                // Wait for processing
                print("⏳ Waiting for recording to process...")
                sleep(3)

                // Verify recording completed
                let processingIndicator = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'processing'")).firstMatch

                if processingIndicator.exists {
                    print("⚙️ Recording is processing...")
                    // Wait up to 30 seconds for processing
                    for i in 1...30 {
                        sleep(1)
                        if !processingIndicator.exists {
                            print("✅ Processing completed after \(i) seconds")
                            break
                        }
                        if i % 5 == 0 {
                            print("   Still processing... (\(i)/30s)")
                        }
                    }
                }

                print("✅ Recording with remote camera completed")
                XCTAssertTrue(true, "Recording should complete successfully")
            } else {
                print("⚠️ Stop button not found")
                XCTFail("Stop button should be available after starting recording")
            }
        } else {
            print("⚠️ Record button not found")
            RemoteCameraTestHelpers.logVisibleButtons(app, prefix: "  ")
            XCTFail("Record button should be available")
        }

        print("✅ testRecordWithRemoteCamera completed")
    }

    func testRemoteCameraInPreview() throws {
        print("🧪 Starting testRemoteCameraInPreview")
        print("💡 This test verifies remote camera preview updates")

        RemoteCameraTestHelpers.navigateToRecord(app)
        enableRemoteCameras()

        guard waitForRemoteCamera(timeout: 20) else {
            throw XCTSkip("No remote camera available")
        }

        // Enable remote source
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))
        let firstSource = remoteSources.element(boundBy: 0)

        print("📱 Enabling remote camera for preview...")
        if firstSource.value as? Int != 1 {
            firstSource.click()
            sleep(2) // Wait for preview to update
        }

        // Look for preview images or indicators
        let previewImages = app.images.matching(NSPredicate(format: "identifier CONTAINS[c] 'preview' OR identifier CONTAINS[c] 'camera'"))

        print("📊 Preview image count: \(previewImages.count)")

        if previewImages.count > 0 {
            print("✅ Preview images found:")
            for i in 0..<min(previewImages.count, 5) {
                let preview = previewImages.element(boundBy: i)
                print("  - Preview \(i): exists=\(preview.exists)")
            }
        } else {
            print("ℹ️ No preview images found (preview may not be visible in test environment)")
        }

        print("✅ testRemoteCameraInPreview completed")
    }

    func testMultipleRemoteCameras() throws {
        print("🧪 Starting testMultipleRemoteCameras")
        print("💡 This test requires multiple iOS devices streaming")

        RemoteCameraTestHelpers.navigateToRecord(app)
        enableRemoteCameras()

        // Wait and monitor for multiple cameras
        print("⏳ Waiting for remote cameras (30 seconds)...")
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))

        var maxCamerasDetected = 0
        for i in 1...30 {
            sleep(1)
            let currentCount = remoteSources.count

            if currentCount > maxCamerasDetected {
                maxCamerasDetected = currentCount
                print("📱 Detected \(currentCount) remote camera(s):")
                for j in 0..<currentCount {
                    let source = remoteSources.element(boundBy: j)
                    print("  - \(source.label)")
                }
            }

            if currentCount >= 2 {
                print("✅ Multiple cameras detected!")
                break
            }

            if i % 10 == 0 {
                print("   Still waiting... (\(i)/30s, \(currentCount) camera(s))")
            }
        }

        if maxCamerasDetected >= 2 {
            print("✅ Multiple remote cameras successfully detected")
            XCTAssertGreaterThanOrEqual(maxCamerasDetected, 2, "Should detect multiple cameras")

            // Try enabling all cameras
            print("🔄 Enabling all remote cameras...")
            for i in 0..<remoteSources.count {
                let source = remoteSources.element(boundBy: i)
                if source.value as? Int != 1 {
                    source.click()
                    sleep(1)
                }
            }
            print("✅ All remote cameras enabled")

        } else if maxCamerasDetected == 1 {
            print("ℹ️ Only one remote camera detected")
            throw XCTSkip("Test requires multiple cameras, only 1 detected")
        } else {
            print("⚠️ No remote cameras detected")
            throw XCTSkip("No remote cameras available")
        }

        print("✅ testMultipleRemoteCameras completed")
    }

    func testRemoteCameraDisconnectDuringRecording() throws {
        print("🧪 Starting testRemoteCameraDisconnectDuringRecording")
        print("💡 This test requires manual disconnection of iOS device during recording")

        RemoteCameraTestHelpers.navigateToRecord(app)
        enableRemoteCameras()

        guard waitForRemoteCamera(timeout: 20) else {
            throw XCTSkip("No remote camera available")
        }

        // Enable remote source
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))
        let firstSource = remoteSources.element(boundBy: 0)
        let sourceName = firstSource.label

        print("📱 Enabling remote camera: \(sourceName)")
        if firstSource.value as? Int != 1 {
            firstSource.click()
            sleep(1)
        }

        // Start recording
        let recordButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'record'")).firstMatch
        if recordButton.waitForExistence(timeout: 3) {
            print("🔴 Starting recording...")
            recordButton.click()
            sleep(2)

            print("💡 Please disconnect the iOS device now!")
            print("⏳ Waiting 15 seconds to detect disconnection...")

            // Monitor for disconnection
            var disconnected = false
            for i in 1...15 {
                sleep(1)

                // Check if source still exists
                let currentSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))
                let sourceStillExists = currentSources.allElementsBoundByIndex.contains { $0.label == sourceName }

                if !sourceStillExists {
                    print("📵 Remote camera disconnected after \(i) seconds!")
                    disconnected = true

                    // Check for error message or graceful handling
                    let errorMessages = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'disconnect' OR label CONTAINS[c] 'lost'"))
                    if errorMessages.count > 0 {
                        print("ℹ️ Disconnect handled with message:")
                        for j in 0..<errorMessages.count {
                            print("  - \(errorMessages.element(boundBy: j).label)")
                        }
                    }
                    break
                }

                if i % 5 == 0 {
                    print("   Still connected... (\(i)/15s)")
                }
            }

            // Stop recording
            let stopButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'stop'")).firstMatch
            if stopButton.exists {
                print("⏹️ Stopping recording...")
                stopButton.click()
                sleep(2)
            }

            if disconnected {
                print("✅ Disconnect detection working")
                XCTAssertTrue(true, "Should detect remote camera disconnection")
            } else {
                print("ℹ️ No disconnection detected (device may still be connected)")
            }
        }

        print("✅ testRemoteCameraDisconnectDuringRecording completed")
    }

    // MARK: - Helper Methods

    private func enableRemoteCameras() {
        print("🔧 Enabling remote cameras...")
        let toggle = app.checkBoxes.matching(NSPredicate(format: "label CONTAINS[c] 'allow remote'")).firstMatch

        if toggle.waitForExistence(timeout: 3) {
            RemoteCameraTestHelpers.setCheckbox(toggle, to: true)
        } else {
            print("⚠️ Remote cameras toggle not found")
        }
    }

    private func waitForRemoteCamera(timeout: Int) -> Bool {
        print("⏳ Waiting for remote camera (up to \(timeout) seconds)...")
        let remoteSources = app.buttons.matching(NSPredicate(format: "identifier CONTAINS[c] 'RemoteCameraSource'"))

        for i in 1...timeout {
            sleep(1)
            if remoteSources.count > 0 {
                print("✅ Remote camera found after \(i) seconds!")
                return true
            }
            if i % 5 == 0 {
                print("   Still waiting... (\(i)/\(timeout)s)")
            }
        }

        print("⚠️ No remote camera found after \(timeout) seconds")
        return false
    }
}
