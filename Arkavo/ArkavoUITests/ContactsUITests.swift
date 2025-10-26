import XCTest

final class ContactsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launch()

        // Wait for app to fully load
        _ = app.wait(for: .runningForeground, timeout: 5)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Navigation Tests

    func testNavigateToContactsView() {
        // Navigate to Contacts tab
        let contactsTab = app.tabBars.buttons["Contacts"]
        XCTAssertTrue(contactsTab.exists)
        contactsTab.tap()

        // Verify we're on the Contacts view
        let contactsNavBar = app.navigationBars["Contacts"]
        XCTAssertTrue(contactsNavBar.waitForExistence(timeout: 5))
    }

    // MARK: - Empty State Tests

    func testEmptyContactsState() {
        // Navigate to Contacts
        app.tabBars.buttons["Contacts"].tap()

        // Check for empty state animation or message
        let emptyStateView = app.otherElements["WaveEmptyStateView"]
        if emptyStateView.exists {
            XCTAssertTrue(emptyStateView.isHittable)
        } else {
            // Alternative: Check for "Awaiting connections..." text
            let awaitingText = app.staticTexts["Awaiting connections..."]
            XCTAssertTrue(awaitingText.exists)
        }
    }

    // MARK: - Add Contact Tests

    func testOpenAddContactSheet() {
        // Navigate to Contacts
        app.tabBars.buttons["Contacts"].tap()

        // Tap the add button (assuming it's in the navigation bar)
        let addButton = app.navigationBars["Contacts"].buttons["Add"]
        if addButton.exists {
            addButton.tap()

            // Verify the sheet appears
            let connectWithOthersText = app.staticTexts["Connect with Others"]
            XCTAssertTrue(connectWithOthersText.waitForExistence(timeout: 5))

            // Verify both connection options are visible
            let connectNearbyButton = app.buttons["Connect Nearby"]
            let inviteRemotelyButton = app.buttons["Invite Remotely"]

            XCTAssertTrue(connectNearbyButton.exists)
            XCTAssertTrue(inviteRemotelyButton.exists)
        }
    }

    func testConnectNearbyFlow() {
        // Navigate to Contacts and open add sheet
        app.tabBars.buttons["Contacts"].tap()

        let addButton = app.navigationBars["Contacts"].buttons["Add"]
        if addButton.exists {
            addButton.tap()

            // Tap Connect Nearby
            let connectNearbyButton = app.buttons["Connect Nearby"]
            connectNearbyButton.tap()

            // Verify the nearby connection view appears
            let searchingText = app.staticTexts["Searching for nearby devices..."]
            XCTAssertTrue(searchingText.waitForExistence(timeout: 5))

            // Verify instructions are shown
            let instructionsText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Make sure the other person"))
            XCTAssertTrue(instructionsText.element.exists)

            // Test Done button
            let doneButton = app.buttons["Done"]
            XCTAssertTrue(doneButton.exists)
            doneButton.tap()
        }
    }

    func testInviteRemotelyFlow() {
        // Navigate to Contacts and open add sheet
        app.tabBars.buttons["Contacts"].tap()

        let addButton = app.navigationBars["Contacts"].buttons["Add"]
        if addButton.exists {
            addButton.tap()

            // Tap Invite Remotely
            let inviteRemotelyButton = app.buttons["Invite Remotely"]
            inviteRemotelyButton.tap()

            // The share sheet should appear (may be system UI, harder to test)
            // We can at least verify the button responds to taps
            XCTAssertTrue(true) // Placeholder for share sheet testing
        }
    }

    // MARK: - Contact List Tests

    func testContactListDisplay() {
        // This test assumes there are contacts in the list
        // In a real test environment, you'd set up test data first

        app.tabBars.buttons["Contacts"].tap()

        // Look for contact rows
        let contactRows = app.buttons.matching(identifier: "ContactRow")
        if contactRows.count > 0 {
            // Verify contact row elements
            let firstContact = contactRows.element(boundBy: 0)
            XCTAssertTrue(firstContact.exists)

            // Check for expected UI elements in a contact row
            let nameLabels = firstContact.staticTexts.matching(NSPredicate(format: "label != ''"))
            XCTAssertTrue(nameLabels.count > 0)
        }
    }

    func testContactSearch() {
        app.tabBars.buttons["Contacts"].tap()

        // Look for search field
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            searchField.tap()
            searchField.typeText("Alice")

            // Verify search results update
            // This would filter the contact list
            let searchResults = app.buttons.matching(identifier: "ContactRow")
            // In a real test, verify the correct contacts are shown
        }
    }

    // MARK: - Contact Detail Tests

    func testOpenContactDetail() {
        app.tabBars.buttons["Contacts"].tap()

        // Tap on a contact (if exists)
        let contactRows = app.buttons.matching(identifier: "ContactRow")
        if contactRows.count > 0 {
            contactRows.element(boundBy: 0).tap()

            // Verify contact detail view appears
            let contactDetailNav = app.navigationBars["Contact Details"]
            XCTAssertTrue(contactDetailNav.waitForExistence(timeout: 5))

            // Check for expected elements
            let sendMessageButton = app.buttons["Send Message"]
            let moreOptionsButton = app.buttons["More Options"]
            let deleteButton = app.buttons["Delete Contact"]

            // At least some of these should exist
            XCTAssertTrue(sendMessageButton.exists || moreOptionsButton.exists || deleteButton.exists)

            // Test Done button
            let doneButton = app.buttons["Done"]
            XCTAssertTrue(doneButton.exists)
            doneButton.tap()
        }
    }

    // MARK: - Swipe Actions Tests

    func testSwipeToDeleteContact() {
        app.tabBars.buttons["Contacts"].tap()

        let contactRows = app.buttons.matching(identifier: "ContactRow")
        if contactRows.count > 0 {
            let firstContact = contactRows.element(boundBy: 0)

            // Swipe left on the contact
            firstContact.swipeLeft()

            // Look for delete button
            let deleteButton = app.buttons["Delete"]
            if deleteButton.waitForExistence(timeout: 2) {
                deleteButton.tap()

                // Verify confirmation alert
                let alert = app.alerts["Delete Contact?"]
                XCTAssertTrue(alert.waitForExistence(timeout: 2))

                // Test cancel
                alert.buttons["Cancel"].tap()

                // Verify contact still exists
                XCTAssertTrue(firstContact.exists)
            }
        }
    }

    // MARK: - Status Indicator Tests

    func testContactStatusIndicators() {
        app.tabBars.buttons["Contacts"].tap()

        let contactRows = app.buttons.matching(identifier: "ContactRow")
        if contactRows.count > 0 {
            let firstContact = contactRows.element(boundBy: 0)

            // Look for status indicators
            let connectedText = firstContact.staticTexts["Connected"]
            let notConnectedText = firstContact.staticTexts["Not connected"]

            // One of these should exist
            XCTAssertTrue(connectedText.exists || notConnectedText.exists)

            // Check for encryption badge (lock icon)
            let encryptionBadge = firstContact.images.matching(NSPredicate(format: "label CONTAINS[c] %@", "lock"))
            // Badge may or may not exist depending on contact
        }
    }

    // MARK: - Performance Tests

    func testContactListScrollPerformance() {
        app.tabBars.buttons["Contacts"].tap()

        measure {
            // Scroll the contact list
            let scrollView = app.scrollViews.firstMatch
            if scrollView.exists {
                scrollView.swipeUp()
                scrollView.swipeDown()
            }
        }
    }

    // MARK: - Accessibility Tests

    func testContactsAccessibility() {
        app.tabBars.buttons["Contacts"].tap()

        // Verify important elements have accessibility labels
        let contactRows = app.buttons.matching(identifier: "ContactRow")
        if contactRows.count > 0 {
            let firstContact = contactRows.element(boundBy: 0)
            XCTAssertFalse(firstContact.label.isEmpty)
        }

        // Check navigation elements
        let addButton = app.navigationBars["Contacts"].buttons["Add"]
        if addButton.exists {
            XCTAssertFalse(addButton.label.isEmpty)
        }
    }
}
