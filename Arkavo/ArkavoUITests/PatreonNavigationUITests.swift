import XCTest

/// UI test to navigate to Patreon screens and capture screenshots
final class PatreonNavigationUITests: XCTestCase {
    var app: XCUIApplication!
    let screenshotDir = "/Users/arkavo/Projects/arkavo/app/screenshots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    func testNavigateToConnectedAccounts() throws {
        // Wait for app to load
        sleep(2)
        capture("01_initial")

        // Look for tab bar and tap Profile
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 5) {
            // Try to find profile tab by various identifiers
            let profileButton = tabBar.buttons["Profile"]
            let personButton = tabBar.buttons["person.circle.fill"]

            if profileButton.exists {
                profileButton.tap()
            } else if personButton.exists {
                personButton.tap()
            } else {
                // Try last button in tab bar
                let buttons = tabBar.buttons.allElementsBoundByIndex
                if let lastButton = buttons.last {
                    lastButton.tap()
                }
            }
            sleep(1)
            capture("02_profile_tab")
        }

        // Look for settings/gear button
        let gearButton = app.buttons["gearshape"]
        let settingsButton = app.buttons["Settings"]
        let gearImage = app.images["gearshape"]

        if gearButton.waitForExistence(timeout: 3) {
            gearButton.tap()
        } else if settingsButton.exists {
            settingsButton.tap()
        } else if gearImage.exists {
            gearImage.tap()
        } else {
            // Try navigation bar buttons
            let navBar = app.navigationBars.firstMatch
            if navBar.exists {
                let navButtons = navBar.buttons.allElementsBoundByIndex
                for button in navButtons.reversed() {
                    if button.label.lowercased().contains("settings") ||
                       button.label.lowercased().contains("gear") ||
                       button.identifier.contains("gear") {
                        button.tap()
                        break
                    }
                }
            }
        }
        sleep(1)
        capture("03_after_gear_tap")

        // Look for Account or Connected Accounts
        let connectedAccountsCell = app.cells["Manage Connected Accounts"]
        let connectedAccountsButton = app.buttons["Manage Connected Accounts"]
        let connectedAccountsStatic = app.staticTexts["Manage Connected Accounts"]

        if connectedAccountsCell.waitForExistence(timeout: 3) {
            connectedAccountsCell.tap()
        } else if connectedAccountsButton.exists {
            connectedAccountsButton.tap()
        } else if connectedAccountsStatic.exists {
            connectedAccountsStatic.tap()
        }
        sleep(1)
        capture("04_connected_accounts")

        // Look for Supported Creators (only visible if Patreon is linked)
        let supportedCreatorsCell = app.cells["Supported Creators"]
        let supportedCreatorsButton = app.buttons["Supported Creators"]
        let supportedCreatorsStatic = app.staticTexts["Supported Creators"]

        if supportedCreatorsCell.waitForExistence(timeout: 3) {
            supportedCreatorsCell.tap()
            sleep(1)
            capture("05_memberships_list")
        } else if supportedCreatorsButton.exists {
            supportedCreatorsButton.tap()
            sleep(1)
            capture("05_memberships_list")
        } else if supportedCreatorsStatic.exists {
            supportedCreatorsStatic.tap()
            sleep(1)
            capture("05_memberships_list")
        } else {
            capture("05_no_supported_creators")
        }
    }

    func testPrintUIHierarchy() throws {
        // Wait for app to load
        sleep(2)

        // Navigate to profile
        let tabBar = app.tabBars.firstMatch
        if tabBar.waitForExistence(timeout: 5) {
            let buttons = tabBar.buttons.allElementsBoundByIndex
            if let lastButton = buttons.last {
                lastButton.tap()
            }
        }
        sleep(1)

        // Print the UI hierarchy to help debug
        print("=== UI HIERARCHY ===")
        print(app.debugDescription)
        print("=== END HIERARCHY ===")

        capture("hierarchy_debug")
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        // Also save to file
        let path = "\(screenshotDir)/patreon_\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        print("📸 Saved: \(path)")
    }
}
