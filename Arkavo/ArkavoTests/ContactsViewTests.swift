@testable import Arkavo
import SwiftData
import XCTest

@MainActor
final class ContactsViewTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var sharedState: SharedState!
    var persistenceController: PersistenceController!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Profile.self, Stream.self, Thought.self,
            configurations: modelConfiguration,
        )
        modelContext = modelContainer.mainContext

        // Initialize persistence controller with test container
        persistenceController = PersistenceController.shared
        // Note: In a real test, we'd need to inject the test container
        // For now, we'll work with the shared instance

        // Initialize shared state
        sharedState = SharedState()
    }

    override func tearDown() async throws {
        // Clean up
        modelContainer = nil
        modelContext = nil
        sharedState = nil
        persistenceController = nil

        try await super.tearDown()
    }

    // MARK: - Model Tests

    func testProfileModelInitialization() {
        // Test default initialization
        let profile = Profile()
        XCTAssertNotNil(profile.id)
        XCTAssertNotNil(profile.publicID)
        XCTAssertEqual(profile.name, "Default")
        XCTAssertNil(profile.blurb)
        XCTAssertEqual(profile.interests, "")
        XCTAssertEqual(profile.location, "")
        XCTAssertFalse(profile.hasHighEncryption)
        XCTAssertFalse(profile.hasHighIdentityAssurance)
        XCTAssertNil(profile.keyStorePublic)
        XCTAssertNil(profile.keyStorePrivate)
    }

    func testProfileModelCustomInitialization() {
        // Test custom initialization
        let profile = Profile(
            name: "John Doe",
            blurb: "Test user",
            interests: "Testing, Development",
            location: "Test City",
            hasHighEncryption: true,
            hasHighIdentityAssurance: true,
        )

        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.blurb, "Test user")
        XCTAssertEqual(profile.interests, "Testing, Development")
        XCTAssertEqual(profile.location, "Test City")
        XCTAssertTrue(profile.hasHighEncryption)
        XCTAssertTrue(profile.hasHighIdentityAssurance)
    }

    func testProfilePublicIDGeneration() {
        // Test that publicID is generated from UUID
        let profile1 = Profile(name: "User 1")
        let profile2 = Profile(name: "User 2")

        XCTAssertNotEqual(profile1.publicID, profile2.publicID)
        XCTAssertEqual(profile1.publicID.count, 32) // SHA256 produces 32 bytes
        XCTAssertEqual(profile2.publicID.count, 32)
    }

    func testProfileFinalizeRegistration() {
        let profile = Profile(name: "Test User")

        XCTAssertNil(profile.did)
        XCTAssertNil(profile.handle)

        profile.finalizeRegistration(did: "did:test:123", handle: "testuser")

        XCTAssertEqual(profile.did, "did:test:123")
        XCTAssertEqual(profile.handle, "testuser")

        // Test idempotency - should not crash when called again
        profile.finalizeRegistration(did: "did:test:456", handle: "newhandle")

        // Values should remain unchanged
        XCTAssertEqual(profile.did, "did:test:123")
        XCTAssertEqual(profile.handle, "testuser")
    }

    // MARK: - Contact Management Tests

    func testFetchAllPeerProfiles() async throws {
        // Create test profiles
        let profile1 = Profile(name: "Alice")
        let profile2 = Profile(name: "Bob")
        let profile3 = Profile(name: "Me") // Should be filtered out
        let profile4 = Profile(name: "InnerCircle") // Should be filtered out

        modelContext.insert(profile1)
        modelContext.insert(profile2)
        modelContext.insert(profile3)
        modelContext.insert(profile4)

        try modelContext.save()

        // Test fetching profiles
        let contacts = try await persistenceController.fetchAllPeerProfiles()

        XCTAssertEqual(contacts.count, 4) // All profiles are returned by fetchAllPeerProfiles
    }

    func testContactFiltering() async throws {
        // Create test profiles
        let alice = Profile(name: "Alice", handle: "alice123")
        let bob = Profile(name: "Bob", handle: "bobby")
        let charlie = Profile(name: "Charlie")
        let me = Profile(name: "Me")
        let innerCircle = Profile(name: "InnerCircle")

        modelContext.insert(alice)
        modelContext.insert(bob)
        modelContext.insert(charlie)
        modelContext.insert(me)
        modelContext.insert(innerCircle)

        try modelContext.save()

        // Simulate ContactsView filtering logic
        let allProfiles = try await persistenceController.fetchAllPeerProfiles()
        let filteredContacts = allProfiles.filter { profile in
            profile.name != "Me" && profile.name != "InnerCircle"
        }

        XCTAssertEqual(filteredContacts.count, 3)
        XCTAssertTrue(filteredContacts.contains { $0.name == "Alice" })
        XCTAssertTrue(filteredContacts.contains { $0.name == "Bob" })
        XCTAssertTrue(filteredContacts.contains { $0.name == "Charlie" })
        XCTAssertFalse(filteredContacts.contains { $0.name == "Me" })
        XCTAssertFalse(filteredContacts.contains { $0.name == "InnerCircle" })
    }

    func testContactSearchFiltering() {
        let alice = Profile(name: "Alice", handle: "alice123")
        let bob = Profile(name: "Bob", handle: "bobby")
        let charlie = Profile(name: "Charlie")

        let contacts = [alice, bob, charlie]

        // Test name search
        let nameSearch = contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains("ali")
        }
        XCTAssertEqual(nameSearch.count, 1)
        XCTAssertEqual(nameSearch.first?.name, "Alice")

        // Test handle search
        let handleSearch = contacts.filter { contact in
            contact.handle?.localizedCaseInsensitiveContains("bob") ?? false
        }
        XCTAssertEqual(handleSearch.count, 1)
        XCTAssertEqual(handleSearch.first?.name, "Bob")

        // Test combined search
        let combinedSearch = contacts.filter { contact in
            contact.name.localizedCaseInsensitiveContains("123") ||
                (contact.handle?.localizedCaseInsensitiveContains("123") ?? false)
        }
        XCTAssertEqual(combinedSearch.count, 1)
        XCTAssertEqual(combinedSearch.first?.name, "Alice")
    }

    // MARK: - Connection Status Tests

    func testContactConnectionStatus() {
        // Test connected contact
        let connectedContact = Profile(name: "Connected User")
        connectedContact.keyStorePublic = Data([1, 2, 3]) // Mock data

        XCTAssertNotNil(connectedContact.keyStorePublic)
        XCTAssertTrue(connectedContact.keyStorePublic != nil) // Simulates "Connected" status

        // Test not connected contact
        let notConnectedContact = Profile(name: "Not Connected User")

        XCTAssertNil(notConnectedContact.keyStorePublic)
        XCTAssertTrue(notConnectedContact.keyStorePublic == nil) // Simulates "Not connected" status
    }

    func testContactEncryptionBadges() {
        // Test high encryption badge
        let encryptedContact = Profile(
            name: "Encrypted User",
            hasHighEncryption: true,
            hasHighIdentityAssurance: false,
        )

        XCTAssertTrue(encryptedContact.hasHighEncryption)
        XCTAssertFalse(encryptedContact.hasHighIdentityAssurance)

        // Test identity verified badge
        let verifiedContact = Profile(
            name: "Verified User",
            hasHighEncryption: true,
            hasHighIdentityAssurance: true,
        )

        XCTAssertTrue(verifiedContact.hasHighEncryption)
        XCTAssertTrue(verifiedContact.hasHighIdentityAssurance)

        // Test no badges
        let basicContact = Profile(name: "Basic User")

        XCTAssertFalse(basicContact.hasHighEncryption)
        XCTAssertFalse(basicContact.hasHighIdentityAssurance)
    }

    // MARK: - Delete Contact Tests

    func testDeletePeerProfile() async throws {
        // Create and save a test profile
        let profile = Profile(name: "Test User")
        modelContext.insert(profile)
        try modelContext.save()

        // Verify profile exists
        let profilesBefore = try await persistenceController.fetchAllPeerProfiles()
        XCTAssertTrue(profilesBefore.contains { $0.id == profile.id })

        // Delete the profile
        try await persistenceController.deletePeerProfile(profile)

        // Verify profile is deleted
        let profilesAfter = try await persistenceController.fetchAllPeerProfiles()
        XCTAssertFalse(profilesAfter.contains { $0.id == profile.id })
    }

    // MARK: - Remote Invitation Tests

    func testShareableLinkGeneration() {
        let profile = Profile(name: "Test User")
        let publicIDString = profile.publicID.base58EncodedString
        let expectedLink = "https://app.arkavo.com/connect/\(publicIDString)"

        XCTAssertFalse(publicIDString.isEmpty)
        XCTAssertTrue(expectedLink.hasPrefix("https://app.arkavo.com/connect/"))
        XCTAssertTrue(expectedLink.count > 30) // Ensure it includes the encoded ID
    }

    // MARK: - Key Store Tests

    func testKeyStoreDataStorage() {
        let profile = Profile(name: "Test User")

        // Test storing public key store
        let mockPublicKeyStore = Data([1, 2, 3, 4, 5])
        profile.keyStorePublic = mockPublicKeyStore
        XCTAssertEqual(profile.keyStorePublic, mockPublicKeyStore)

        // Test storing private key store
        let mockPrivateKeyStore = Data([6, 7, 8, 9, 10])
        profile.keyStorePrivate = mockPrivateKeyStore
        XCTAssertEqual(profile.keyStorePrivate, mockPrivateKeyStore)
    }

    // MARK: - Contact UI Terminology Tests (TDD: RED phase)

    func testContactRemovalTerminologyConsistency() {
        // UI should use consistent terminology: "Remove" for all contact types
        // Both the action button and confirmation should say "Remove"
        let humanContact = Profile(name: "Human User")
        let agentContact = Profile.createAgentProfile(
            agentID: "test-agent",
            name: "Test Agent",
            did: nil,
            purpose: "Testing",
            model: nil,
            endpoint: nil,
            contactType: .remoteAgent,
            channels: []
        )

        // For humans: should use "Remove Contact" not "Delete Contact"
        let humanActionLabel = humanContact.removalActionLabel
        XCTAssertEqual(humanActionLabel, "Remove Contact", "Human contact removal should say 'Remove Contact'")

        // For agents: should use "Remove Agent"
        let agentActionLabel = agentContact.removalActionLabel
        XCTAssertEqual(agentActionLabel, "Remove Agent", "Agent contact removal should say 'Remove Agent'")

        // Confirmation dialog title should be consistent
        let humanConfirmTitle = humanContact.removalConfirmationTitle
        XCTAssertEqual(humanConfirmTitle, "Remove Contact?", "Human removal confirmation should say 'Remove Contact?'")

        let agentConfirmTitle = agentContact.removalConfirmationTitle
        XCTAssertEqual(agentConfirmTitle, "Remove Agent?", "Agent removal confirmation should say 'Remove Agent?'")
    }

    func testContactTypeHasRemovalLabels() {
        // All contact types should provide removal labels
        for contactType in ContactType.allCases {
            let profile = Profile(name: "Test")
            profile.contactType = contactType.rawValue

            // Skip device agent - cannot be removed
            if contactType == .deviceAgent {
                XCTAssertFalse(profile.canBeRemoved, "Device agent should not be removable")
                continue
            }

            XCTAssertTrue(profile.canBeRemoved, "\(contactType) should be removable")
            XCTAssertFalse(profile.removalActionLabel.isEmpty, "\(contactType) should have removal action label")
            XCTAssertFalse(profile.removalConfirmationTitle.isEmpty, "\(contactType) should have confirmation title")
            XCTAssertFalse(profile.removalConfirmationMessage.isEmpty, "\(contactType) should have confirmation message")
        }
    }

    // MARK: - Swipe to Delete Tests

    func testContactSupportsDeletion() {
        // Non-device agent contacts should support deletion
        let humanContact = Profile(name: "Human")
        let remoteAgent = Profile.createAgentProfile(
            agentID: "remote",
            name: "Remote",
            did: nil,
            purpose: nil,
            model: nil,
            endpoint: nil,
            contactType: .remoteAgent,
            channels: []
        )
        let delegatedAgent = Profile.createAgentProfile(
            agentID: "delegated",
            name: "Delegated",
            did: nil,
            purpose: nil,
            model: nil,
            endpoint: nil,
            contactType: .delegatedAgent,
            channels: []
        )
        let deviceAgent = Profile.createAgentProfile(
            agentID: "device",
            name: "Device",
            did: nil,
            purpose: nil,
            model: nil,
            endpoint: nil,
            contactType: .deviceAgent,
            channels: []
        )

        XCTAssertTrue(humanContact.canBeRemoved, "Human contact should be removable")
        XCTAssertTrue(remoteAgent.canBeRemoved, "Remote agent should be removable")
        XCTAssertTrue(delegatedAgent.canBeRemoved, "Delegated agent should be removable")
        XCTAssertFalse(deviceAgent.canBeRemoved, "Device agent should NOT be removable")
    }

    // MARK: - Contact Filter Tests

    func testContactFilterCasesAreComplete() {
        let allFilters = ContactFilter.allCases
        XCTAssertEqual(allFilters.count, 4)
        XCTAssertTrue(allFilters.contains(.all))
        XCTAssertTrue(allFilters.contains(.people))
        XCTAssertTrue(allFilters.contains(.agents))
        XCTAssertTrue(allFilters.contains(.online))
    }

    func testContactFilterDisplayNames() {
        // Each filter should have a user-friendly display name
        XCTAssertEqual(ContactFilter.all.rawValue, "All")
        XCTAssertEqual(ContactFilter.people.rawValue, "People")
        XCTAssertEqual(ContactFilter.agents.rawValue, "Agents")
        XCTAssertEqual(ContactFilter.online.rawValue, "Online")
    }

    // MARK: - Agent Profile Factory Tests

    func testCreateAgentProfileWithAllFields() {
        let profile = Profile.createAgentProfile(
            agentID: "agent-123",
            name: "Test Agent",
            did: "did:key:z6Mk...",
            purpose: "General assistance",
            model: "gpt-4",
            endpoint: "ws://localhost:8080",
            contactType: .remoteAgent,
            channels: [.localNetwork(endpoint: "ws://localhost:8080", isAvailable: true)],
            entitlements: AgentEntitlements(read: true, write: true)
        )

        XCTAssertEqual(profile.agentID, "agent-123")
        XCTAssertEqual(profile.name, "Test Agent")
        XCTAssertEqual(profile.did, "did:key:z6Mk...")
        XCTAssertEqual(profile.agentPurpose, "General assistance")
        XCTAssertEqual(profile.agentModel, "gpt-4")
        XCTAssertEqual(profile.agentEndpoint, "ws://localhost:8080")
        XCTAssertEqual(profile.contactTypeEnum, .remoteAgent)
        XCTAssertEqual(profile.channels.count, 1)
        XCTAssertTrue(profile.entitlements.read)
        XCTAssertTrue(profile.entitlements.write)
        XCTAssertFalse(profile.entitlements.execute)
    }

    // MARK: - Entitlements Display Tests

    func testEntitlementsDisplayList() {
        let fullEntitlements = AgentEntitlements(read: true, write: true, execute: true, delegate: true, admin: true)
        XCTAssertEqual(fullEntitlements.displayList.count, 5)

        let chatEntitlements = AgentEntitlements(from: ["agent.capability.chat"])
        XCTAssertTrue(chatEntitlements.read)
        XCTAssertTrue(chatEntitlements.write)
        XCTAssertFalse(chatEntitlements.execute)

        let emptyEntitlements = AgentEntitlements()
        XCTAssertTrue(emptyEntitlements.isEmpty)
        XCTAssertEqual(emptyEntitlements.displayList.count, 0)
    }

    // MARK: - Agent Connection Tests (TDD: RED Phase)

    /// When a delegated agent is added via QR code, its endpoint must be stored
    /// so it can be connected later without requiring mDNS discovery
    func testDelegatedAgentEndpointIsPersisted() {
        // Given: A delegated agent with an RPC endpoint from QR code
        let rpcEndpoint = "ws://192.168.1.50:8342"
        let profile = Profile.createAgentProfile(
            agentID: "did:key:z6MkTestDelegated",
            name: "My Edge Agent",
            did: "did:key:z6MkTestDelegated",
            purpose: "Delegated from QR authorization",
            model: nil,
            endpoint: rpcEndpoint,
            contactType: .delegatedAgent,
            channels: [.localNetwork(endpoint: rpcEndpoint, isAvailable: true)]
        )

        // Then: The endpoint should be stored in the profile
        XCTAssertEqual(profile.agentEndpoint, rpcEndpoint, "RPC endpoint should be persisted in Profile")

        // And: We should be able to construct an AgentEndpoint for connection
        let agentEndpoint = profile.toAgentEndpoint()
        XCTAssertNotNil(agentEndpoint, "Should be able to create AgentEndpoint from Profile")
        XCTAssertEqual(agentEndpoint?.url, rpcEndpoint, "AgentEndpoint URL should match stored endpoint")
    }

    /// Tests that a profile can indicate if it has a connectable endpoint
    func testProfileIndicatesConnectability() {
        // Profile with local endpoint - connectable locally
        let localProfile = Profile.createAgentProfile(
            agentID: "local-agent",
            name: "Local Agent",
            did: nil,
            purpose: nil,
            model: nil,
            endpoint: "ws://192.168.1.100:8080",
            contactType: .remoteAgent,
            channels: [.localNetwork(endpoint: "ws://192.168.1.100:8080", isAvailable: true)]
        )
        XCTAssertTrue(localProfile.hasLocalEndpoint, "Profile with local endpoint should indicate it's connectable locally")

        // Profile without endpoint - not connectable locally
        let cloudProfile = Profile.createAgentProfile(
            agentID: "cloud-agent",
            name: "Cloud Agent",
            did: nil,
            purpose: nil,
            model: nil,
            endpoint: nil,
            contactType: .delegatedAgent,
            channels: [.arkavoNetwork(isAvailable: true)]
        )
        XCTAssertFalse(cloudProfile.hasLocalEndpoint, "Profile without local endpoint should not indicate local connectivity")
    }
}
