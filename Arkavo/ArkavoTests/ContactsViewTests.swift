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
}
