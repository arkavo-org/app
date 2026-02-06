import XCTest

/// Simple screenshot capture that works with any app state
final class SimpleScreenshotUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testCaptureCurrentState() throws {
        // Wait for app to load
        sleep(3)
        
        // Capture screenshot of initial state
        captureScreenshot(name: "01_initial_state")
        
        // Try to navigate to Profile
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.exists {
            profileTab.tap()
            sleep(1)
            captureScreenshot(name: "02_profile_tab")
            
            // Try to tap Account if exists
            let accountButton = app.buttons["Account"].firstMatch
            if accountButton.waitForExistence(timeout: 3) {
                accountButton.tap()
                sleep(1)
                captureScreenshot(name: "03_account_view")
                
                // Try Connected Accounts
                let connectedAccounts = app.buttons["Manage Connected Accounts"].firstMatch
                if connectedAccounts.waitForExistence(timeout: 3) {
                    connectedAccounts.tap()
                    sleep(1)
                    captureScreenshot(name: "04_connected_accounts")
                    
                    // Check for Supported Creators
                    let supportedCreators = app.buttons["Supported Creators"].firstMatch
                    if supportedCreators.waitForExistence(timeout: 3) {
                        captureScreenshot(name: "04b_supported_creators_button")
                        supportedCreators.tap()
                        sleep(1)
                        captureScreenshot(name: "05_memberships_list")
                    } else {
                        captureScreenshot(name: "04b_no_supported_creators")
                    }
                }
            } else {
                // Profile view without Account button
                captureScreenshot(name: "02b_profile_no_account")
            }
        } else {
            captureScreenshot(name: "01b_no_profile_tab")
        }
    }
    
    private func captureScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        
        // Also save to file for easy access
        let testRunDir = "/tmp/arkavo_ui_test_\(ProcessInfo.processInfo.processIdentifier)"
        try? FileManager.default.createDirectory(atPath: testRunDir, withIntermediateDirectories: true)
        
        let path = "\(testRunDir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        print("📸 Screenshot: \(path)")
    }
}
