import XCTest

final class ContactsUITest: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testContactsEmptyState() throws {
        // Navigate to Contacts tab
        let contactsTab = app.tabBars.buttons["Contacts"]
        XCTAssertTrue(contactsTab.waitForExistence(timeout: 5), "Contacts tab should exist")
        contactsTab.tap()

        // Verify empty state appears
        let emptyState = app.staticTexts["No contacts yet"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 3) || app.otherElements["WaveEmptyStateView"].exists,
                     "Empty state should appear when no contacts exist")
    }

    func testContactsSearch() throws {
        // Navigate to Contacts
        app.tabBars.buttons["Contacts"].tap()

        // If there are contacts, test search
        let searchField = app.searchFields.firstMatch
        if searchField.exists {
            searchField.tap()
            searchField.typeText("test")

            // Verify search filters contacts or shows empty result
            XCTAssertTrue(
                app.staticTexts["No contacts found"].waitForExistence(timeout: 2) ||
                app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'test'")).count > 0,
                "Search should filter contacts or show no results"
            )
        }
    }

    func testContactRowDisplay() throws {
        // This test assumes at least one contact exists
        app.tabBars.buttons["Contacts"].tap()

        sleep(2) // Wait for contacts to load

        // Check if any contact rows exist
        let contactButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'contact-'"))
        if contactButtons.count > 0 {
            let firstContact = contactButtons.element(boundBy: 0)

            // Verify contact row elements
            XCTAssertTrue(firstContact.exists, "Contact row should exist")

            // Tap contact to open detail view
            firstContact.tap()

            // Verify detail view appears
            let detailView = app.navigationBars["Contact Details"]
            XCTAssertTrue(detailView.waitForExistence(timeout: 3), "Contact detail view should appear")

            // Check for expected elements in detail view
            XCTAssertTrue(app.buttons["Done"].exists, "Done button should exist")
            XCTAssertTrue(
                app.buttons["Send Message"].exists || app.buttons["Connect"].exists,
                "Action button should exist"
            )
        }
    }

    func testContactSwipeToDelete() throws {
        app.tabBars.buttons["Contacts"].tap()

        sleep(2)

        let contactButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'contact-'"))
        if contactButtons.count > 0 {
            let firstContact = contactButtons.element(boundBy: 0)

            // Swipe left to reveal delete action
            firstContact.swipeLeft()

            // Verify delete button appears
            let deleteButton = app.buttons["Delete"]
            XCTAssertTrue(deleteButton.waitForExistence(timeout: 2), "Delete button should appear after swipe")
        }
    }
}
