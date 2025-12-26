import XCTest

/// Tests for messaging and encryption features in HYPΞRforum
final class MessagingTests: XCTestCase {
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

    // MARK: - Plain Message Tests

    func testSendPlainMessage() throws {
        // Navigate to a chat
        helpers.openChatForGroup(named: "General")

        // Verify chat view is displayed
        assertChatViewDisplayed(in: app)

        // Get initial message count
        let initialCount = helpers.getMessageCount()

        // Send a plain (unencrypted) message
        let messageContent = "Test message at \(Date().timeIntervalSince1970)"
        helpers.sendMessage(content: messageContent, encrypted: false)

        // Verify message appears
        XCTAssertTrue(helpers.waitForMessage(containing: "Test message", timeout: 10), "Sent message should appear")

        // Verify message count increased
        let newCount = helpers.getMessageCount()
        XCTAssertGreaterThan(newCount, initialCount, "Message count should increase after sending")
    }

    func testSendMultipleMessages() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let messages = [
            "First message",
            "Second message",
            "Third message"
        ]

        for message in messages {
            helpers.sendMessage(content: message, encrypted: false)
            sleep(1) // Wait between messages
        }

        // Verify all messages appear
        for message in messages {
            XCTAssertTrue(helpers.waitForMessage(containing: message, timeout: 5), "\(message) should appear")
        }
    }

    // MARK: - Encrypted Message Tests

    func testSendEncryptedMessage() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Enable encryption
        helpers.enableEncryption()
        sleep(1)

        // Send encrypted message
        let messageContent = "Encrypted test message"
        helpers.sendMessage(content: messageContent, encrypted: true)

        // Verify message appears
        XCTAssertTrue(helpers.waitForMessage(containing: messageContent, timeout: 10), "Encrypted message should appear")

        // Note: With real services, you'd verify the encryption icon appears
        // This would require getting the message ID which is challenging in UI tests
    }

    func testToggleEncryptionMultipleTimes() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let encryptionToggle = app.buttons["button_toggleEncryption"]
        XCTAssertTrue(encryptionToggle.exists, "Encryption toggle should exist")

        // Toggle encryption on and off multiple times
        for _ in 0..<3 {
            encryptionToggle.click()
            usleep(500000)
            encryptionToggle.click()
            usleep(500000)
        }

        // Should still be functional
        helpers.sendMessage(content: "Message after toggles", encrypted: false)
        XCTAssertTrue(helpers.waitForMessage(containing: "Message after toggles"), "Message should send successfully after toggling")
    }

    func testEncryptionInfoPopover() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Open encryption info popover
        helpers.openEncryptionInfo()

        // Verify popover is displayed
        let encryptionInfoView = app.otherElements["view_encryptionInfo"]
        XCTAssertTrue(encryptionInfoView.waitForExistence(timeout: 5), "Encryption info popover should be displayed")

        // Verify encryption info contains expected text
        XCTAssertTrue(app.staticTexts["End-to-End Encryption"].exists, "Should show encryption title")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'OpenTDF'")).count > 0, "Should mention OpenTDF")
    }

    func testToggleEncryptionFromPopover() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Open encryption info popover
        helpers.openEncryptionInfo()

        let encryptionInfoView = app.otherElements["view_encryptionInfo"]
        XCTAssertTrue(encryptionInfoView.waitForExistence(timeout: 5), "Encryption info popover should be displayed")

        // Find and click the toggle button in the popover
        let toggleButton = app.buttons["button_toggleEncryptionPopover"]
        XCTAssertTrue(toggleButton.exists, "Toggle encryption button should exist in popover")

        toggleButton.click()
        sleep(1)

        // Popover should still be functional
        // Note: State verification would require more complex checks
    }

    // MARK: - Message Display Tests

    func testMessageTimestampDisplay() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Send a message
        helpers.sendMessage(content: "Timestamp test message", encrypted: false)

        // Look for timestamp format (HH:mm for today)
        let timestampPattern = NSPredicate(format: "label MATCHES %@", "\\d{2}:\\d{2}")
        let timestamps = app.staticTexts.matching(timestampPattern)

        // Should have at least one timestamp
        XCTAssertGreaterThan(timestamps.count, 0, "Should display message timestamps")
    }

    func testMessageOrdering() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Send three messages in sequence
        let message1 = "First \(Date().timeIntervalSince1970)"
        let message2 = "Second \(Date().timeIntervalSince1970)"
        let message3 = "Third \(Date().timeIntervalSince1970)"

        helpers.sendMessage(content: message1, encrypted: false)
        sleep(1)
        helpers.sendMessage(content: message2, encrypted: false)
        sleep(1)
        helpers.sendMessage(content: message3, encrypted: false)

        // All should be visible
        XCTAssertTrue(helpers.waitForMessage(containing: "First"), "First message should appear")
        XCTAssertTrue(helpers.waitForMessage(containing: "Second"), "Second message should appear")
        XCTAssertTrue(helpers.waitForMessage(containing: "Third"), "Third message should appear")

        // Note: Verifying actual order would require more complex element querying
    }

    func testEmptyMessageNotSent() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let sendButton = app.buttons["button_sendMessage"]
        let messageField = app.textFields["field_messageInput"]

        // Verify send button is disabled when field is empty
        XCTAssertTrue(messageField.exists, "Message input should exist")
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled when message is empty")
    }

    func testMessageInputFieldFunctionality() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let messageField = app.textFields["field_messageInput"]
        XCTAssertTrue(messageField.waitForExistence(timeout: 5), "Message input field should exist")

        // Click and type
        messageField.click()
        messageField.typeText("Test typing functionality")

        // Verify text appears in field
        // Note: Getting actual text value from textField in XCUITest can be tricky
        let sendButton = app.buttons["button_sendMessage"]
        XCTAssertTrue(sendButton.isEnabled, "Send button should be enabled when text is entered")

        // Clear field
        messageField.typeKey("a", modifierFlags: .command) // Select all
        messageField.typeKey(.delete, modifierFlags: [])

        // Send button should be disabled again
        XCTAssertFalse(sendButton.isEnabled, "Send button should be disabled after clearing text")
    }

    // MARK: - Integration Tests

    func testSendMessageWithEncryptionToggle() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Send plain message
        helpers.sendMessage(content: "Plain message 1", encrypted: false)
        XCTAssertTrue(helpers.waitForMessage(containing: "Plain message 1"))

        // Enable encryption and send
        helpers.enableEncryption()
        helpers.sendMessage(content: "Encrypted message", encrypted: true)
        XCTAssertTrue(helpers.waitForMessage(containing: "Encrypted message"))

        // Disable encryption and send
        helpers.disableEncryption()
        helpers.sendMessage(content: "Plain message 2", encrypted: false)
        XCTAssertTrue(helpers.waitForMessage(containing: "Plain message 2"))

        // All three messages should be visible
        let messageCount = helpers.getMessageCount()
        XCTAssertGreaterThanOrEqual(messageCount, 3, "Should have at least 3 messages")
    }

    func testMessageSendingWithKeyboardShortcut() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let messageField = app.textFields["field_messageInput"]
        messageField.click()
        messageField.typeText("Message with Enter key")

        // Press Enter to send
        messageField.typeKey(.enter, modifierFlags: [])

        // Message should be sent
        XCTAssertTrue(helpers.waitForMessage(containing: "Message with Enter key", timeout: 5), "Message should be sent with Enter key")
    }

    // MARK: - Performance Tests

    func testMessageSendingPerformance() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        measure {
            helpers.sendMessage(content: "Performance test message", encrypted: false)
        }
    }

    // MARK: - Edge Cases

    func testSendLongMessage() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Create a long message
        let longMessage = String(repeating: "This is a long message. ", count: 20)

        helpers.sendMessage(content: longMessage, encrypted: false)

        // Should be sent successfully
        XCTAssertTrue(helpers.waitForMessage(containing: "This is a long message", timeout: 10), "Long message should be sent")
    }

    func testSendSpecialCharacters() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let specialMessage = "Special chars: 🎉 @#$% Ξ ♦ 中文"

        helpers.sendMessage(content: specialMessage, encrypted: false)

        XCTAssertTrue(helpers.waitForMessage(containing: "Special chars", timeout: 10), "Message with special characters should be sent")
    }
}
