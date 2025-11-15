import ArkavoSocial
import XCTest

@testable import HYPERforum

final class HYPERforumTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        XCTAssertTrue(true)
    }

    // MARK: - AppState Tests

    func testAppStateInitialization() throws {
        let appState = AppState()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(appState.currentUser)
    }

    func testSignIn() throws {
        let appState = AppState()
        appState.signIn(user: "test@example.com")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertEqual(appState.currentUser, "test@example.com")
    }

    func testSignOut() throws {
        let appState = AppState()
        appState.signIn(user: "test@example.com")
        appState.signOut()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(appState.currentUser)
    }

    // MARK: - EncryptionManager Tests

    @MainActor
    func testEncryptionManagerInitialization() throws {
        let client = createMockClient()
        let manager = EncryptionManager(arkavoClient: client)

        XCTAssertTrue(manager.encryptionEnabled, "Encryption should be enabled by default")
        XCTAssertFalse(manager.isEncrypting)
        XCTAssertNil(manager.encryptionError)
    }

    @MainActor
    func testEncryptionToggle() throws {
        let client = createMockClient()
        let manager = EncryptionManager(arkavoClient: client)

        XCTAssertTrue(manager.encryptionEnabled)

        manager.toggleEncryption()
        XCTAssertFalse(manager.encryptionEnabled)

        manager.toggleEncryption()
        XCTAssertTrue(manager.encryptionEnabled)
    }

    @MainActor
    func testPolicyGeneration() throws {
        let client = createMockClient()
        let manager = EncryptionManager(arkavoClient: client)

        let groupId = "test-group"
        let policy1 = manager.getPolicy(for: groupId)
        let policy2 = manager.getPolicy(for: groupId)

        // Should return same policy for same group (cached)
        XCTAssertEqual(policy1, policy2, "Policy should be cached for the same group")
        XCTAssertFalse(policy1.isEmpty, "Policy should not be empty")
    }

    @MainActor
    func testPolicyDifferentGroups() throws {
        let client = createMockClient()
        let manager = EncryptionManager(arkavoClient: client)

        let policy1 = manager.getPolicy(for: "group1")
        let policy2 = manager.getPolicy(for: "group2")

        // Different groups should have different policies
        XCTAssertNotEqual(policy1, policy2, "Different groups should have different policies")
    }

    @MainActor
    func testClearPolicies() throws {
        let client = createMockClient()
        let manager = EncryptionManager(arkavoClient: client)

        _ = manager.getPolicy(for: "group1")
        _ = manager.getPolicy(for: "group2")

        XCTAssertEqual(manager.groupsWithPolicies.count, 2)

        manager.clearPolicies()
        XCTAssertEqual(manager.groupsWithPolicies.count, 0)
    }

    // MARK: - Message Model Tests

    func testForumMessageInitialization() throws {
        let message = ForumMessage(
            id: "test-id",
            groupId: "test-group",
            senderId: "sender-1",
            senderName: "Test User",
            content: "Test message",
            timestamp: Date(),
            threadId: nil,
            isEncrypted: false
        )

        XCTAssertEqual(message.id, "test-id")
        XCTAssertEqual(message.groupId, "test-group")
        XCTAssertEqual(message.senderName, "Test User")
        XCTAssertEqual(message.content, "Test message")
        XCTAssertFalse(message.isEncrypted)
        XCTAssertNil(message.threadId)
    }

    func testForumGroupSampleData() throws {
        let groups = ForumGroup.sampleGroups

        XCTAssertFalse(groups.isEmpty, "Sample groups should not be empty")
        XCTAssertGreaterThan(groups.count, 0, "Should have at least one sample group")

        // Test first group has required properties
        let firstGroup = groups[0]
        XCTAssertFalse(firstGroup.name.isEmpty)
        XCTAssertGreaterThan(firstGroup.memberCount, 0)
    }

    // MARK: - AI Council Tests

    func testCouncilAgentTypes() throws {
        let agentTypes = CouncilAgentType.allCases

        XCTAssertEqual(agentTypes.count, 5, "Should have 5 agent types")

        // Verify all agent types have required properties
        for agentType in agentTypes {
            XCTAssertFalse(agentType.rawValue.isEmpty)
            XCTAssertFalse(agentType.icon.isEmpty)
            XCTAssertFalse(agentType.description.isEmpty)
        }
    }

    func testCouncilAgentIdentifiable() throws {
        let analyst = CouncilAgentType.analyst
        let researcher = CouncilAgentType.researcher

        XCTAssertEqual(analyst.id, analyst.rawValue)
        XCTAssertEqual(researcher.id, researcher.rawValue)
        XCTAssertNotEqual(analyst.id, researcher.id)
    }

    // MARK: - Helper Methods

    @MainActor
    private func createMockClient() -> ArkavoClient {
        return ArkavoClient(
            authURL: URL(string: "https://test.arkavo.net")!,
            websocketURL: URL(string: "wss://test.arkavo.net")!,
            relyingPartyID: "test.arkavo.net",
            curve: .p256
        )
    }
}
