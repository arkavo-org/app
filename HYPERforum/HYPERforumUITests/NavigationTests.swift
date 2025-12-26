import XCTest

/// Tests for navigation and UI structure in HYPΞRforum
final class NavigationTests: XCTestCase {
    var app: XCUIApplication!
    var helpers: TestHelpers!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        TestHelpers.configureForUITesting(app)
        app.launch()

        helpers = TestHelpers(app: app)

        // Wait for app to be ready
        sleep(2)

        // With -UITesting flag, app auto-authenticates as test user
    }

    override func tearDownWithError() throws {
        app = nil
        helpers = nil
    }

    // MARK: - Sidebar Navigation Tests

    func testSidebarPresence() throws {
        // Check for sidebar (indicates authenticated state with main forum)
        let sidebar = app.outlines["list_sidebar"]
        if sidebar.waitForExistence(timeout: 5) {
            XCTAssertTrue(sidebar.exists, "Sidebar should be displayed")
            return
        }

        // Not authenticated - check for welcome screen sign-in button
        let signInButton = app.buttons["button_signInPasskey"]
        XCTAssertTrue(signInButton.waitForExistence(timeout: 3), "Welcome screen with sign-in button should be displayed")
    }

    func testAllSidebarItemsPresent() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Verify all four main navigation items exist
        let groupsButton = app.buttons["sidebar_groups"]
        XCTAssertTrue(groupsButton.exists, "Groups sidebar item should exist")

        let discussionsButton = app.buttons["sidebar_discussions"]
        XCTAssertTrue(discussionsButton.exists, "Discussions sidebar item should exist")

        let councilButton = app.buttons["sidebar_council"]
        XCTAssertTrue(councilButton.exists, "AI Council sidebar item should exist")

        let settingsButton = app.buttons["sidebar_settings"]
        XCTAssertTrue(settingsButton.exists, "Settings sidebar item should exist")
    }

    func testNavigateToGroups() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToGroups()

        // Verify Groups view is displayed
        let groupsView = app.otherElements["view_groups"]
        XCTAssertTrue(groupsView.waitForExistence(timeout: 5), "Groups view should be displayed")

        // Verify navigation title
        XCTAssertTrue(app.staticTexts["Groups"].exists, "Should show 'Groups' title")
    }

    func testNavigateToDiscussions() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToDiscussions()

        // Verify Discussions view is displayed
        let discussionsView = app.otherElements["view_discussions"]
        XCTAssertTrue(discussionsView.waitForExistence(timeout: 5), "Discussions view should be displayed")

        // Verify expected text
        XCTAssertTrue(app.staticTexts["Discussions"].exists, "Should show 'Discussions' heading")
    }

    func testNavigateToCouncil() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToCouncil()

        // Verify Council view is displayed
        let councilView = app.otherElements["view_council"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council view should be displayed")

        // Verify expected elements
        XCTAssertTrue(app.staticTexts["AI Council"].exists, "Should show 'AI Council' heading")
        XCTAssertTrue(app.buttons["button_activateCouncil"].exists, "Should show Activate Council button")
    }

    func testNavigateToSettings() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToSettings()

        // Verify Settings view is displayed
        let settingsView = app.otherElements["view_settings"]
        XCTAssertTrue(settingsView.waitForExistence(timeout: 5), "Settings view should be displayed")

        // Verify navigation title
        XCTAssertTrue(app.staticTexts["Settings"].exists, "Should show 'Settings' title")
    }

    func testNavigateBetweenAllSections() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Navigate through all sections
        helpers.navigateToGroups()
        XCTAssertTrue(app.otherElements["view_groups"].exists, "Should show Groups view")

        helpers.navigateToDiscussions()
        XCTAssertTrue(app.otherElements["view_discussions"].exists, "Should show Discussions view")

        helpers.navigateToCouncil()
        XCTAssertTrue(app.otherElements["view_council"].exists, "Should show Council view")

        helpers.navigateToSettings()
        XCTAssertTrue(app.otherElements["view_settings"].exists, "Should show Settings view")

        // Navigate back to Groups
        helpers.navigateToGroups()
        XCTAssertTrue(app.otherElements["view_groups"].exists, "Should show Groups view again")
    }

    // MARK: - Group Navigation Tests

    func testGroupListDisplay() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToGroups()

        let groupsView = app.otherElements["view_groups"]
        XCTAssertTrue(groupsView.exists, "Groups view should be displayed")

        // Verify group cards are displayed
        let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
        XCTAssertGreaterThan(groupCards.count, 0, "Should display at least one group card")
    }

    func testSelectGroupAndOpenChat() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToGroups()

        // Click first group card
        let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
        if groupCards.count > 0 {
            groupCards.element(boundBy: 0).click()
            sleep(1)

            // Should navigate to chat view
            let chatView = app.otherElements["view_chat"]
            XCTAssertTrue(chatView.waitForExistence(timeout: 5), "Chat view should be displayed after selecting group")
        } else {
            XCTFail("No group cards available")
        }
    }

    func testGroupCardHoverEffect() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToGroups()

        let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
        if groupCards.count > 0 {
            let firstCard = groupCards.element(boundBy: 0)
            XCTAssertTrue(firstCard.exists, "Group card should exist")

            // Hover effect is visual and hard to test in UI tests
            // But we can verify the card is interactive
            XCTAssertTrue(firstCard.isHittable, "Group card should be clickable")
        }
    }

    func testSidebarGroupList() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Verify "My Groups" section in sidebar
        XCTAssertTrue(app.staticTexts["My Groups"].exists, "Sidebar should show 'My Groups' section")

        // Verify group items in sidebar
        let sidebarGroups = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebarGroup_'"))
        XCTAssertGreaterThan(sidebarGroups.count, 0, "Should show groups in sidebar")
    }

    // MARK: - Chat View Navigation Tests

    func testChatViewElements() throws {
        helpers.openChatForGroup(named: "General")

        let chatView = app.otherElements["view_chat"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "Chat view should be displayed")

        // Verify chat header
        let chatHeader = app.otherElements["view_chatHeader"]
        XCTAssertTrue(chatHeader.exists, "Chat header should exist")

        // Verify message scroll view
        let messagesScrollView = app.scrollViews["scrollView_messages"]
        XCTAssertTrue(messagesScrollView.exists, "Messages scroll view should exist")

        // Verify message input
        let messageInput = app.otherElements["view_messageInput"]
        XCTAssertTrue(messageInput.exists, "Message input should exist")
    }

    func testChatViewToolbarButtons() throws {
        helpers.openChatForGroup(named: "General")

        let chatView = app.otherElements["view_chat"]
        XCTAssertTrue(chatView.exists, "Chat view should be displayed")

        // Verify toolbar buttons
        let councilButton = app.buttons["button_openCouncil"]
        XCTAssertTrue(councilButton.exists, "AI Council button should exist in toolbar")

        let encryptionButton = app.buttons["button_encryptionInfo"]
        XCTAssertTrue(encryptionButton.exists, "Encryption button should exist in toolbar")
    }

    func testNavigateBackFromChat() throws {
        helpers.openChatForGroup(named: "General")

        let chatView = app.otherElements["view_chat"]
        XCTAssertTrue(chatView.exists, "Chat view should be displayed")

        // Navigate back to groups (macOS may use back button or sidebar)
        helpers.navigateToGroups()

        // Should return to groups view
        let groupsView = app.otherElements["view_groups"]
        XCTAssertTrue(groupsView.waitForExistence(timeout: 5), "Should return to Groups view")
    }

    // MARK: - Settings View Tests

    func testSettingsViewSections() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToSettings()

        let settingsView = app.otherElements["view_settings"]
        XCTAssertTrue(settingsView.exists, "Settings view should be displayed")

        // Verify settings sections
        XCTAssertTrue(app.staticTexts["Appearance"].exists, "Should show Appearance section")
        XCTAssertTrue(app.staticTexts["Privacy"].exists, "Should show Privacy section")
        XCTAssertTrue(app.staticTexts["Notifications"].exists, "Should show Notifications section")
    }

    func testSettingsToggles() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToSettings()

        // Verify toggles exist
        let darkModeToggle = app.switches["toggle_darkMode"]
        XCTAssertTrue(darkModeToggle.exists, "Dark Mode toggle should exist")

        let encryptionToggle = app.switches["toggle_enableEncryption"]
        XCTAssertTrue(encryptionToggle.exists, "Enable Encryption toggle should exist")

        let onlineStatusToggle = app.switches["toggle_onlineStatus"]
        XCTAssertTrue(onlineStatusToggle.exists, "Show Online Status toggle should exist")

        let groupMessagesToggle = app.switches["toggle_groupMessages"]
        XCTAssertTrue(groupMessagesToggle.exists, "Group Messages toggle should exist")

        let councilInsightsToggle = app.switches["toggle_councilInsights"]
        XCTAssertTrue(councilInsightsToggle.exists, "Council Insights toggle should exist")
    }

    func testToggleSettingsSwitch() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToSettings()

        let onlineStatusToggle = app.switches["toggle_onlineStatus"]
        if onlineStatusToggle.exists {
            // Get initial value
            let initialValue = onlineStatusToggle.value as? String

            // Click to toggle
            onlineStatusToggle.click()
            usleep(500000)

            // Verify value changed
            let newValue = onlineStatusToggle.value as? String
            XCTAssertNotEqual(initialValue, newValue, "Toggle value should change when clicked")
        }
    }

    // MARK: - User Profile Menu Tests

    func testUserProfileMenuAccess() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Look for user profile menu button
        // In macOS, this might be a menu button in the toolbar
        let userMenuButtons = app.menuButtons
        if userMenuButtons.count > 0 {
            XCTAssertTrue(true, "User profile menu button exists")
        } else {
            // May be under a different element type
            XCTAssertTrue(app.images.matching(NSPredicate(format: "identifier CONTAINS 'person'")).count > 0, "Should have user profile icon")
        }
    }

    // MARK: - Window and Layout Tests

    func testMainForumWindowLayout() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Verify sidebar is visible (indicates NavigationSplitView layout)
        let sidebar = app.outlines["list_sidebar"]
        XCTAssertTrue(sidebar.exists, "Sidebar should be visible in split view")
    }

    func testNavigationTitleDisplay() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        helpers.navigateToGroups()

        // Verify "Groups" title appears
        XCTAssertTrue(app.staticTexts["Groups"].exists, "Should display 'Groups' navigation title")

        helpers.navigateToSettings()

        // Verify "Settings" title appears
        XCTAssertTrue(app.staticTexts["Settings"].exists, "Should display 'Settings' navigation title")
    }

    // MARK: - Navigation Performance Tests

    func testNavigationPerformance() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        measure {
            helpers.navigateToGroups()
            helpers.navigateToDiscussions()
            helpers.navigateToCouncil()
            helpers.navigateToSettings()
        }
    }

    // MARK: - Deep Navigation Tests

    func testDeepNavigationToChat() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Navigate: Groups -> Select Group -> Chat
        helpers.navigateToGroups()

        let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
        if groupCards.count > 0 {
            groupCards.element(boundBy: 0).click()
            sleep(1)

            assertChatViewDisplayed(in: app)

            // Open council panel
            helpers.openCouncilPanel()

            let councilView = app.otherElements["view_fullCouncil"]
            XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Should navigate to full council view")
        }
    }

    // MARK: - Accessibility Tests

    func testKeyboardNavigation() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Test tab navigation through sidebar items
        // This is challenging in macOS UI tests but we can verify elements are keyboard accessible
        let groupsButton = app.buttons["sidebar_groups"]
        XCTAssertTrue(groupsButton.exists, "Groups button should exist and be accessible")

        // Verify elements are hittable (can receive interaction)
        XCTAssertTrue(groupsButton.isHittable, "Groups button should be hittable (keyboard accessible)")
    }

    // MARK: - Edge Cases

    func testRapidNavigation() throws {
        guard helpers.isAuthenticated() else {
            throw XCTSkip("User not authenticated")
        }

        // Rapidly switch between views
        for _ in 0..<5 {
            app.buttons["sidebar_groups"].click()
            app.buttons["sidebar_discussions"].click()
            app.buttons["sidebar_council"].click()
            app.buttons["sidebar_settings"].click()
        }

        // App should remain stable - sidebar should still be visible
        let sidebar = app.outlines["list_sidebar"]
        XCTAssertTrue(sidebar.exists, "App should remain stable after rapid navigation")
    }
}
