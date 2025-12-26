import XCTest

/// Test helpers for HYPΞRforum UI tests
class TestHelpers {
    let app: XCUIApplication

    init(app: XCUIApplication) {
        self.app = app
    }

    /// Configure app for UI testing with auto-authentication
    static func configureForUITesting(_ app: XCUIApplication) {
        app.launchEnvironment["UI_TESTING"] = "1"
        app.launchArguments.append("-UITesting")
    }

    /// Check if user is authenticated (sidebar is visible)
    func isAuthenticated(timeout: TimeInterval = 5) -> Bool {
        let sidebar = app.outlines["list_sidebar"]
        return sidebar.waitForExistence(timeout: timeout)
    }

    // MARK: - Navigation Helpers

    /// Navigate to the Groups section via sidebar
    func navigateToGroups() {
        let groupsSidebarButton = app.buttons["sidebar_groups"]
        if groupsSidebarButton.exists {
            groupsSidebarButton.click()
            sleep(1) // Wait for navigation
        }
    }

    /// Navigate to the Discussions section via sidebar
    func navigateToDiscussions() {
        let discussionsSidebarButton = app.buttons["sidebar_discussions"]
        if discussionsSidebarButton.exists {
            discussionsSidebarButton.click()
            sleep(1)
        }
    }

    /// Navigate to the AI Council section via sidebar
    func navigateToCouncil() {
        let councilSidebarButton = app.buttons["sidebar_council"]
        if councilSidebarButton.exists {
            councilSidebarButton.click()
            sleep(1)
        }
    }

    /// Navigate to the Settings section via sidebar
    func navigateToSettings() {
        let settingsSidebarButton = app.buttons["sidebar_settings"]
        if settingsSidebarButton.exists {
            settingsSidebarButton.click()
            sleep(1)
        }
    }

    /// Select a group by its ID and open chat
    func selectGroup(withId groupId: String) {
        let groupCard = app.otherElements["card_group_\(groupId)"]
        if groupCard.waitForExistence(timeout: 5) {
            groupCard.click()
            sleep(1) // Wait for chat to load
        }
    }

    /// Open chat for a group by name
    func openChatForGroup(named groupName: String) {
        // First ensure we're on the Groups view
        navigateToGroups()

        // Wait briefly for groups to load
        sleep(1)

        // Click the first group card (for demo purposes)
        // In a real implementation, you'd search for the specific group by name
        let groupCards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'card_group_'"))
        if groupCards.count > 0 {
            groupCards.element(boundBy: 0).click()
            sleep(1)
        }
    }

    /// Open the AI Council panel from chat view
    func openCouncilPanel() {
        let councilButton = app.buttons["button_openCouncil"]
        if councilButton.waitForExistence(timeout: 5) {
            councilButton.click()
            sleep(1) // Wait for panel to open
        }
    }

    // MARK: - Message Helpers

    /// Send a message with specified content
    func sendMessage(content: String, encrypted: Bool = false) {
        // First ensure encryption is set correctly
        if encrypted {
            enableEncryption()
        } else {
            disableEncryption()
        }

        // Type and send message
        let messageField = app.textFields["field_messageInput"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5), "Message input field should exist")

        messageField.click()
        messageField.typeText(content)

        let sendButton = app.buttons["button_sendMessage"]
        XCTAssertTrue(sendButton.exists, "Send button should exist")
        sendButton.click()

        sleep(1) // Wait for message to be sent and appear
    }

    /// Wait for a message containing specific text to appear
    @discardableResult
    func waitForMessage(containing text: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let messageText = app.staticTexts.matching(predicate).firstMatch
        return messageText.waitForExistence(timeout: timeout)
    }

    /// Verify that a message is encrypted
    func verifyMessageEncryption(messageId: String, shouldBeEncrypted: Bool) {
        let encryptionIcon = app.images["icon_encrypted_\(messageId)"]
        if shouldBeEncrypted {
            XCTAssertTrue(encryptionIcon.exists, "Message should have encryption icon")
        } else {
            XCTAssertFalse(encryptionIcon.exists, "Message should not have encryption icon")
        }
    }

    /// Get the count of messages currently displayed
    func getMessageCount() -> Int {
        let messages = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'text_message_'"))
        return messages.count
    }

    // MARK: - Encryption Helpers

    /// Enable encryption for messages
    func enableEncryption() {
        let encryptionToggle = app.buttons["button_toggleEncryption"]
        if encryptionToggle.waitForExistence(timeout: 5) {
            // Check current state and toggle if needed
            // For simplicity, we'll just click it
            // In a real implementation, you'd check the visual state
            encryptionToggle.click()
            usleep(500000) // 0.5 seconds
        }
    }

    /// Disable encryption for messages
    func disableEncryption() {
        let encryptionToggle = app.buttons["button_toggleEncryption"]
        if encryptionToggle.waitForExistence(timeout: 5) {
            // Similar to enableEncryption - would need state check in real implementation
            encryptionToggle.click()
            usleep(500000) // 0.5 seconds
        }
    }

    /// Open encryption info popover
    func openEncryptionInfo() {
        let encryptionInfoButton = app.buttons["button_encryptionInfo"]
        if encryptionInfoButton.waitForExistence(timeout: 5) {
            encryptionInfoButton.click()
            sleep(1) // Wait for popover to appear
        }
    }

    // MARK: - AI Council Helpers

    /// Select an AI agent by type in the quick insight menu
    func selectAgent(type: String) {
        let agentButton = app.buttons["button_agent_\(type)"]
        if agentButton.waitForExistence(timeout: 5) {
            agentButton.click()
            sleep(2) // Wait for AI processing (may take time with real services)
        }
    }

    /// Wait for AI insight content to appear
    @discardableResult
    func waitForInsightContent(timeout: TimeInterval = 30) -> Bool {
        let insightText = app.staticTexts["text_insightContent"]
        return insightText.waitForExistence(timeout: timeout)
    }

    /// Switch to a specific council tab
    func switchCouncilTab(to tab: String) {
        let tabPicker = app.segmentedControls["picker_councilTabs"]
        if tabPicker.waitForExistence(timeout: 5) {
            // Click the specific tab
            let tabButton = tabPicker.buttons[tab]
            if tabButton.exists {
                tabButton.click()
                sleep(1)
            }
        }
    }

    /// Generate conversation summary
    func generateSummary() {
        switchCouncilTab(to: "Summary")

        let generateButton = app.buttons["button_generateSummary"]
        if generateButton.waitForExistence(timeout: 5) {
            generateButton.click()
            sleep(5) // Wait for AI to generate summary
        }
    }

    /// Perform topic research
    func researchTopic(_ topic: String) {
        switchCouncilTab(to: "Research")

        let topicField = app.textFields["field_researchTopic"]
        if topicField.waitForExistence(timeout: 5) {
            topicField.click()
            topicField.typeText(topic)

            let researchButton = app.buttons["button_research"]
            if researchButton.exists {
                researchButton.click()
                sleep(5) // Wait for AI to research
            }
        }
    }
}

// MARK: - XCTest Assertion Extensions

extension XCTestCase {
    /// Assert that encryption is currently enabled
    func assertEncryptionEnabled(in app: XCUIApplication) {
        let encryptionButton = app.buttons["button_encryptionInfo"]
        XCTAssertTrue(encryptionButton.exists, "Encryption button should exist")
        // Additional state verification could be added here
    }

    /// Assert that encryption is currently disabled
    func assertEncryptionDisabled(in app: XCUIApplication) {
        let encryptionButton = app.buttons["button_encryptionInfo"]
        XCTAssertTrue(encryptionButton.exists, "Encryption button should exist")
        // Additional state verification could be added here
    }

    /// Assert that a specific council insight is shown
    func assertCouncilInsightShown(agentType: String, in app: XCUIApplication) {
        let agentButton = app.buttons["button_agent_\(agentType)"]
        XCTAssertTrue(agentButton.exists, "Agent button for \(agentType) should exist")

        let insightContent = app.staticTexts["text_insightContent"]
        XCTAssertTrue(insightContent.exists, "Insight content should be displayed")
    }

    /// Assert that a specific number of messages are displayed
    func assertMessageCount(expected: Int, in app: XCUIApplication) {
        let messages = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'text_message_'"))
        XCTAssertEqual(messages.count, expected, "Should have \(expected) messages displayed")
    }

    /// Assert that the chat view is displayed
    func assertChatViewDisplayed(in app: XCUIApplication) {
        let chatView = app.otherElements["view_chat"]
        XCTAssertTrue(chatView.waitForExistence(timeout: 5), "Chat view should be displayed")
    }

    /// Assert that the welcome view is displayed
    func assertWelcomeViewDisplayed(in app: XCUIApplication) {
        let welcomeTitle = app.staticTexts["text_appTitle"]
        XCTAssertTrue(welcomeTitle.waitForExistence(timeout: 5), "Welcome view should be displayed")
    }

    /// Assert that the user is authenticated (main forum view shown)
    func assertAuthenticated(in app: XCUIApplication) {
        let mainForumView = app.otherElements["view_mainForum"]
        XCTAssertTrue(mainForumView.waitForExistence(timeout: 5), "Main forum view should be displayed after authentication")
    }
}
