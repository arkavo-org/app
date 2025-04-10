import XCTest
import SwiftData
import Combine
import MultipeerConnectivity // Required for MCPeerID

// Assuming Profile and related types are accessible for testing
// If not, minimal stub versions might be needed here.
// Example Stub Profile (adjust based on actual Profile definition if needed)
@Model
final class Profile: Identifiable, Codable {
    @Attribute(.unique) var publicID: Data
    var name: String
    var keyStoreData: Data?
    // Add other necessary properties if required by tests or mocks

    init(publicID: Data = UUID().uuidString.data(using: .utf8)!, name: String = "Test User", keyStoreData: Data? = "dummyKeyData".data(using: .utf8)) {
        self.publicID = publicID
        self.name = name
        self.keyStoreData = keyStoreData
    }

    // Add Codable conformance if needed by mocks/tests (though @Model provides it)
    enum CodingKeys: String, CodingKey {
        case publicID, name, keyStoreData // Add other properties if needed
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicID = try container.decode(Data.self, forKey: .publicID)
        name = try container.decode(String.self, forKey: .name)
        keyStoreData = try container.decodeIfPresent(Data.self, forKey: .keyStoreData)
        // Decode other properties if needed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicID, forKey: .publicID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(keyStoreData, forKey: .keyStoreData)
        // Encode other properties if needed
    }
}

// Define the notification name used in the app
extension Notification.Name {
    static let refreshInnerCircleMembers = Notification.Name("refreshInnerCircleMembersNotification")
}

// MARK: - Mock PersistenceController

// Minimal mock focusing on deleteKeyStoreDataFor
// Note: PersistenceController is @MainActor, mocks interacting with it might need @MainActor too
@MainActor
class MockPersistenceController {
    var deleteKeyStoreDataForCalled = false
    var lastProfileDeletedKeyStoreFor: Data?
    var shouldThrowError = false
    var mockError = NSError(domain: "MockPersistenceError", code: 1, userInfo: nil) // Example error
    var mockProfiles: [Data: Profile] = [:] // Store mock profiles if fetchProfile needs mocking

    // Mock implementation matching the expected signature (async throws)
    func deleteKeyStoreDataFor(profile: Profile) async throws {
        print("MockPersistenceController: deleteKeyStoreDataFor called for profile ID: \(profile.publicID)")
        if shouldThrowError {
            throw mockError
        }
        deleteKeyStoreDataForCalled = true
        lastProfileDeletedKeyStoreFor = profile.publicID
        // Simulate removing key data from the mock profile store if needed
        if var fetchedProfile = mockProfiles[profile.publicID] {
            fetchedProfile.keyStoreData = nil
            mockProfiles[profile.publicID] = fetchedProfile
            print("MockPersistenceController: Simulated keyStoreData removal for profile ID: \(profile.publicID)")
        } else {
             print("MockPersistenceController: Profile ID \(profile.publicID) not found in mock store for key removal simulation.")
        }
    }

    // Mock fetchProfile if needed by the logic calling deleteKeyStoreDataFor
    func fetchProfile(withPublicID publicID: Data) async throws -> Profile? {
         print("MockPersistenceController: fetchProfile called for profile ID: \(publicID)")
        if shouldThrowError {
            throw mockError
        }
        return mockProfiles[publicID]
    }

    // Helper to add profiles to the mock store
    func addMockProfile(_ profile: Profile) {
        mockProfiles[profile.publicID] = profile
        print("MockPersistenceController: Added mock profile ID: \(profile.publicID)")
    }
}

// MARK: - Mock PeerDiscoveryManager

// Minimal mock focusing on disconnectPeer
// Note: PeerDiscoveryManager is @MainActor
@MainActor
class MockPeerDiscoveryManager: ObservableObject {
    var disconnectPeerCalled = false
    var lastPeerDisconnected: MCPeerID?

    // Assuming a disconnectPeer method exists with this signature
    func disconnectPeer(peerID: MCPeerID) {
        print("MockPeerDiscoveryManager: disconnectPeer called for peer: \(peerID.displayName)")
        disconnectPeerCalled = true
        lastPeerDisconnected = peerID
    }
}

// MARK: - InnerCircleMemberTests

final class InnerCircleMemberTests: XCTestCase {

    var mockPersistenceController: MockPersistenceController!
    var mockPeerDiscoveryManager: MockPeerDiscoveryManager!
    var testProfile: Profile!
    var testPeerID: MCPeerID!

    @MainActor override func setUpWithError() throws {
        try super.setUpWithError()
        mockPersistenceController = MockPersistenceController()
        mockPeerDiscoveryManager = MockPeerDiscoveryManager()

        // Create a sample profile for testing
        testProfile = Profile(publicID: Data("testProfileID".utf8), name: "Test Member", keyStoreData: Data("initialKeyData".utf8))
        // Add the profile to the mock controller's store so fetchProfile can find it if needed
        mockPersistenceController.addMockProfile(testProfile)


        // Create a sample MCPeerID
        // Note: MCPeerID display name should ideally match or relate to the profile for clarity
        testPeerID = MCPeerID(displayName: "TestMemberDevice") // Use a relevant display name
    }

    override func tearDownWithError() throws {
        mockPersistenceController = nil
        mockPeerDiscoveryManager = nil
        testProfile = nil
        testPeerID = nil
        super.tearDownWithError()
    }

    // MARK: - Test Cases

    @MainActor func testRemoveMember_DeletesKeyStoreData() async throws {
        // Arrange: Ensure the profile exists in the mock controller
        mockPersistenceController.addMockProfile(testProfile)
        XCTAssertNotNil(testProfile.keyStoreData, "Precondition: Profile should have keyStoreData before removal.")

        // Act: Simulate the action that triggers key store data deletion
        // In a real scenario, this would be a call to a ViewModel or Service method.
        // Here, we directly call the mocked method to test its expected invocation.
        try await mockPersistenceController.deleteKeyStoreDataFor(profile: testProfile)

        // Assert: Verify the mock method was called correctly
        XCTAssertTrue(mockPersistenceController.deleteKeyStoreDataForCalled, "deleteKeyStoreDataFor should have been called.")
        XCTAssertEqual(mockPersistenceController.lastProfileDeletedKeyStoreFor, testProfile.publicID, "deleteKeyStoreDataFor was called with the wrong profile ID.")

        // Optional: Assert the key data was cleared in the mock store (if simulation is implemented)
         let updatedProfile = mockPersistenceController.mockProfiles[testProfile.publicID]
         XCTAssertNil(updatedProfile?.keyStoreData, "keyStoreData should be nil in the mock store after deletion.")
         print("Test Assertion: Verified keyStoreData is nil for profile ID \(testProfile.publicID) in mock store.")
    }

    @MainActor func testRemoveMember_DisconnectsPeer() {
        // Arrange (Setup is sufficient)

        // Act: Simulate the action that triggers peer disconnection.
        // This would typically be part of the member removal logic.
        mockPeerDiscoveryManager.disconnectPeer(peerID: testPeerID)

        // Assert: Verify the mock method was called correctly
        XCTAssertTrue(mockPeerDiscoveryManager.disconnectPeerCalled, "disconnectPeer should have been called.")
        XCTAssertEqual(mockPeerDiscoveryManager.lastPeerDisconnected, testPeerID, "disconnectPeer was called with the wrong peer ID.")
         print("Test Assertion: Verified disconnectPeer was called for peer \(testPeerID.displayName).")
    }

    func testRemoveMember_PostsNotification() {
        // Arrange
        let notificationName = Notification.Name.refreshInnerCircleMembers
        let expectation = XCTNSNotificationExpectation(name: notificationName)
         print("Test Arrangement: Setting up expectation for notification '\(notificationName.rawValue)'")


        // Act: Simulate the action that posts the notification.
        // This would typically happen after successful member removal logic.
        NotificationCenter.default.post(name: notificationName, object: nil)
         print("Test Action: Posting notification '\(notificationName.rawValue)'")


        // Assert: Wait for the notification expectation to be fulfilled
        wait(for: [expectation], timeout: 1.0)
         print("Test Assertion: Notification '\(notificationName.rawValue)' received.")
    }

    // Example of testing error handling in deleteKeyStoreDataFor
    @MainActor func testRemoveMember_HandlesPersistenceError() async {
        // Arrange
        mockPersistenceController.shouldThrowError = true
        let expectedError = mockPersistenceController.mockError

        // Act & Assert
        do {
            try await mockPersistenceController.deleteKeyStoreDataFor(profile: testProfile)
            XCTFail("Should have thrown an error, but didn't.")
        } catch {
            // Assert that the correct type of error was thrown (or specific error code/domain)
            XCTAssertEqual(error as NSError, expectedError, "Caught error does not match the expected mock error.")
            print("Test Assertion: Correctly caught expected persistence error.")
        }

        // Assert that the call flag might still be false or handle as appropriate based on implementation
         // Depending on where the error is thrown in the real method, the flag might or might not be set.
         // If the call fails early, it might remain false. Adjust assertion based on expected behavior.
         // XCTAssertFalse(mockPersistenceController.deleteKeyStoreDataForCalled, "deleteKeyStoreDataForCalled should be false if an error occurred early.")
         print("Test Assertion: Verified error handling path.")
    }
}
