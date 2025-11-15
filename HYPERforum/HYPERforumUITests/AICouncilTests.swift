import XCTest

/// Tests for AI Council features in HYPΞRforum
final class AICouncilTests: XCTestCase {
    var app: XCUIApplication!
    var helpers: TestHelpers!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launch()

        helpers = TestHelpers(app: app)

        // Wait for app to be ready
        sleep(2)

        // NOTE: These tests assume the user is already authenticated
        // and there are messages in the chat to analyze
    }

    override func tearDownWithError() throws {
        app = nil
        helpers = nil
    }

    // MARK: - Quick Insight Tests (Per-Message AI Insights)

    func testOpenQuickInsightMenu() throws {
        // Navigate to chat and ensure there are messages
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Find and click AI insight button on a message
        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))

        // Skip if no messages with insight buttons exist
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages with insight buttons available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        // Verify quick insight menu appears
        let quickInsightMenu = app.otherElements["view_quickInsightMenu"]
        XCTAssertTrue(quickInsightMenu.waitForExistence(timeout: 5), "Quick insight menu should appear")

        // Verify all agent types are listed
        XCTAssertTrue(app.staticTexts["AI Council Insight"].exists, "Should show menu title")
    }

    func testQuickInsightAnalyst() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Open insight menu
        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages with insight buttons available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        // Select Analyst agent
        helpers.selectAgent(type: "Critical Analyst")

        // Wait for insight to be generated (with real AI services, this may take time)
        XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "Analyst insight should be generated")

        // Verify insight content exists
        let insightContent = app.staticTexts["text_insightContent"]
        XCTAssertTrue(insightContent.exists, "Insight content should be displayed")
    }

    func testQuickInsightResearcher() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        helpers.selectAgent(type: "Researcher")

        XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "Researcher insight should be generated")
    }

    func testQuickInsightSynthesizer() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        helpers.selectAgent(type: "Synthesizer")

        XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "Synthesizer insight should be generated")
    }

    func testQuickInsightDevilsAdvocate() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        helpers.selectAgent(type: "Devil's Advocate")

        XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "Devil's Advocate insight should be generated")
    }

    func testQuickInsightFacilitator() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        helpers.selectAgent(type: "Facilitator")

        XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "Facilitator insight should be generated")
    }

    func testMultipleAgentInsightsOnSameMessage() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        // Get insights from multiple agents
        let agents = ["Critical Analyst", "Researcher", "Synthesizer"]

        for agent in agents {
            helpers.selectAgent(type: agent)
            XCTAssertTrue(helpers.waitForInsightContent(timeout: 30), "\(agent) insight should be generated")
            sleep(2) // Brief pause between agents
        }
    }

    // MARK: - Full Council Panel Tests

    func testOpenCouncilPanel() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Open full council panel
        helpers.openCouncilPanel()

        // Verify panel is displayed
        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Full council panel should be displayed")

        // Verify title
        XCTAssertTrue(app.staticTexts["AI Council"].exists, "Should show council title")
    }

    func testCouncilPanelTabs() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council panel should be displayed")

        // Verify tabs exist
        let tabPicker = app.segmentedControls["picker_councilTabs"]
        XCTAssertTrue(tabPicker.exists, "Tab picker should exist")

        // Verify all three tabs
        XCTAssertTrue(tabPicker.buttons["Insights"].exists, "Insights tab should exist")
        XCTAssertTrue(tabPicker.buttons["Summary"].exists, "Summary tab should exist")
        XCTAssertTrue(tabPicker.buttons["Research"].exists, "Research tab should exist")
    }

    func testInsightsTab() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council panel should be displayed")

        // Should default to Insights tab
        let insightsTab = app.otherElements["view_insightsTab"]
        XCTAssertTrue(insightsTab.waitForExistence(timeout: 5), "Insights tab should be displayed")

        // Verify it shows information about all agent types
        XCTAssertTrue(app.staticTexts["Per-Message Insights"].exists, "Should show tab title")

        // Verify all 5 agent types are listed
        XCTAssertTrue(app.staticTexts["Critical Analyst"].exists, "Should list Critical Analyst")
        XCTAssertTrue(app.staticTexts["Researcher"].exists, "Should list Researcher")
        XCTAssertTrue(app.staticTexts["Synthesizer"].exists, "Should list Synthesizer")
        XCTAssertTrue(app.staticTexts["Devil's Advocate"].exists, "Should list Devil's Advocate")
        XCTAssertTrue(app.staticTexts["Facilitator"].exists, "Should list Facilitator")
    }

    func testSummaryTab() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council panel should be displayed")

        // Switch to Summary tab
        helpers.switchCouncilTab(to: "Summary")

        let summaryTab = app.otherElements["view_summaryTab"]
        XCTAssertTrue(summaryTab.waitForExistence(timeout: 5), "Summary tab should be displayed")

        // Verify UI elements
        XCTAssertTrue(app.staticTexts["Conversation Summary"].exists, "Should show summary title")
        XCTAssertTrue(app.buttons["button_generateSummary"].exists, "Should show generate summary button")
    }

    func testGenerateConversationSummary() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        // Generate summary
        helpers.generateSummary()

        // Wait for summary to be generated
        // Note: With real AI services, this could take significant time
        sleep(10)

        // Verify summary content appears
        // The exact verification depends on how the summary is displayed
        let summaryTab = app.otherElements["view_summaryTab"]
        XCTAssertTrue(summaryTab.exists, "Summary tab should still be visible")

        // Look for "Generated:" timestamp text which appears after summary is created
        let generatedText = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Generated:'"))
        XCTAssertTrue(generatedText.count > 0 || app.progressIndicators.count > 0, "Should show generated summary or still be loading")
    }

    func testResearchTab() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council panel should be displayed")

        // Switch to Research tab
        helpers.switchCouncilTab(to: "Research")

        let researchTab = app.otherElements["view_researchTab"]
        XCTAssertTrue(researchTab.waitForExistence(timeout: 5), "Research tab should be displayed")

        // Verify UI elements
        XCTAssertTrue(app.staticTexts["Research Mode"].exists, "Should show research title")
        XCTAssertTrue(app.textFields["field_researchTopic"].exists, "Should show research topic field")
        XCTAssertTrue(app.buttons["button_research"].exists, "Should show research button")
    }

    func testPerformTopicResearch() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        // Perform research on a topic
        let topic = "artificial intelligence ethics"
        helpers.researchTopic(topic)

        // Wait for research to complete
        // Note: With real AI services, this could take significant time
        sleep(10)

        // Verify research results appear
        let researchTab = app.otherElements["view_researchTab"]
        XCTAssertTrue(researchTab.exists, "Research tab should still be visible")

        // Look for the topic in the results or a "Research:" header
        let topicLabels = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", topic))
        XCTAssertTrue(topicLabels.count > 0 || app.progressIndicators.count > 0, "Should show research results or still be loading")
    }

    func testResearchButtonDisabledWhenEmpty() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()
        helpers.switchCouncilTab(to: "Research")

        let researchButton = app.buttons["button_research"]
        XCTAssertTrue(researchButton.exists, "Research button should exist")

        // Button should be disabled when topic field is empty
        XCTAssertFalse(researchButton.isEnabled, "Research button should be disabled when topic is empty")

        // Type something in the field
        let topicField = app.textFields["field_researchTopic"]
        topicField.click()
        topicField.typeText("test")

        // Button should now be enabled
        XCTAssertTrue(researchButton.isEnabled, "Research button should be enabled when topic is entered")
    }

    // MARK: - Council Panel Navigation Tests

    func testSwitchBetweenCouncilTabs() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        // Switch between all tabs
        helpers.switchCouncilTab(to: "Insights")
        XCTAssertTrue(app.otherElements["view_insightsTab"].exists, "Should show Insights tab")

        helpers.switchCouncilTab(to: "Summary")
        XCTAssertTrue(app.otherElements["view_summaryTab"].exists, "Should show Summary tab")

        helpers.switchCouncilTab(to: "Research")
        XCTAssertTrue(app.otherElements["view_researchTab"].exists, "Should show Research tab")

        // Switch back to Insights
        helpers.switchCouncilTab(to: "Insights")
        XCTAssertTrue(app.otherElements["view_insightsTab"].exists, "Should show Insights tab again")
    }

    func testCloseCouncilPanel() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        let councilView = app.otherElements["view_fullCouncil"]
        XCTAssertTrue(councilView.waitForExistence(timeout: 5), "Council panel should be displayed")

        // Find and click Done button
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists, "Done button should exist")
        doneButton.click()

        sleep(1)

        // Panel should be dismissed
        XCTAssertFalse(councilView.exists, "Council panel should be dismissed after clicking Done")
    }

    // MARK: - AI Agent Types Tests

    func testAllAgentTypesAvailable() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        let insightButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_messageInsight_'"))
        guard insightButtons.count > 0 else {
            throw XCTSkip("No messages available")
        }

        insightButtons.element(boundBy: 0).click()
        sleep(1)

        // Verify all 5 agent types are available
        let expectedAgents = [
            "Critical Analyst",
            "Researcher",
            "Synthesizer",
            "Devil's Advocate",
            "Facilitator"
        ]

        for agent in expectedAgents {
            let agentButton = app.buttons["button_agent_\(agent)"]
            XCTAssertTrue(agentButton.exists, "\(agent) button should exist in quick insight menu")
        }
    }

    func testAgentDescriptionsDisplayed() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        helpers.openCouncilPanel()

        // On Insights tab, verify agent descriptions are shown
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'examines'")).count > 0, "Should show agent descriptions")
    }

    // MARK: - Performance Tests

    func testCouncilPanelOpenPerformance() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        measure {
            helpers.openCouncilPanel()
            sleep(1)

            let doneButton = app.buttons["Done"]
            if doneButton.exists {
                doneButton.click()
                sleep(1)
            }
        }
    }

    // MARK: - Integration Tests

    func testCompleteCouncilWorkflow() throws {
        helpers.openChatForGroup(named: "General")
        assertChatViewDisplayed(in: app)

        // Send a message to analyze
        helpers.sendMessage(content: "This is a test message for council analysis", encrypted: false)
        sleep(2)

        // Open council panel
        helpers.openCouncilPanel()

        // Check Insights tab
        let insightsTab = app.otherElements["view_insightsTab"]
        XCTAssertTrue(insightsTab.exists, "Insights tab should be displayed")

        // Generate summary
        helpers.switchCouncilTab(to: "Summary")
        helpers.generateSummary()
        sleep(5)

        // Do research
        helpers.switchCouncilTab(to: "Research")
        helpers.researchTopic("testing AI council")
        sleep(5)

        // Close panel
        app.buttons["Done"].click()
        sleep(1)

        // Verify back to chat
        assertChatViewDisplayed(in: app)
    }
}
