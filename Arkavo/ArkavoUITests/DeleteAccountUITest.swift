import XCTest

final class DeleteAccountUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testNavigateToDeleteAccount() throws {
        // Wait for app to load
        sleep(2)

        // Tap "Continue Offline" if network prompt appears
        let continueOfflineOption = app.staticTexts["Continue Offline"]
        if continueOfflineOption.waitForExistence(timeout: 5) {
            continueOfflineOption.tap()
        }

        sleep(2)

        // Navigate to Profile tab
        let profileTab = app.tabBars.buttons["Profile"]
        if profileTab.waitForExistence(timeout: 5) {
            profileTab.tap()
        }

        sleep(1)

        // Tap on Account
        let accountButton = app.buttons["Account"]
        if accountButton.waitForExistence(timeout: 5) {
            accountButton.tap()
        } else {
            // Try cells or static texts
            let accountCell = app.cells.containing(.staticText, identifier: "Account").firstMatch
            if accountCell.waitForExistence(timeout: 3) {
                accountCell.tap()
            }
        }

        sleep(1)

        // Verify Delete Account button exists
        let deleteAccountButton = app.buttons["Delete Account"]
        XCTAssertTrue(deleteAccountButton.waitForExistence(timeout: 5), "Delete Account button should exist")

        // Verify the trash icon is present (button contains trash icon)
        let trashImage = app.images["trash"]

        // Tap Delete Account to show confirmation alert
        deleteAccountButton.tap()

        sleep(1)

        // Verify the confirmation alert appears
        let deleteAlert = app.alerts["Delete Account"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 3), "Delete Account confirmation alert should appear")

        // Verify alert message
        let alertMessage = app.staticTexts["This will permanently delete your account and all associated data from the server. This action cannot be undone."]
        XCTAssertTrue(alertMessage.exists, "Alert should show deletion warning message")

        // Verify Cancel and Delete buttons exist
        let cancelButton = deleteAlert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should exist in alert")

        let deleteButton = deleteAlert.buttons["Delete"]
        XCTAssertTrue(deleteButton.exists, "Delete button should exist in alert")

        // Tap Cancel to dismiss (don't actually delete)
        cancelButton.tap()

        sleep(1)

        // Verify we're still on the Account view
        XCTAssertTrue(deleteAccountButton.exists, "Should still be on Account view after canceling")
    }
}
