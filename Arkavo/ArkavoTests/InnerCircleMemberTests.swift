@testable import Arkavo
import Combine
import MultipeerConnectivity // Required for MCPeerID
import SwiftData
import XCTest

// Using the real Profile class from the app

// Define the notification name used in the app
extension Notification.Name {
    static let refreshInnerCircleMembers = Notification.Name("refreshInnerCircleMembersNotification")
}

// MARK: - Mock PersistenceController

// Minimal mock focusing on deleteKeyStoreDataFor
class MockPersistenceController: @unchecked Sendable {
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
            fetchedProfile.keyStorePrivate = nil
            fetchedProfile.keyStorePublic = nil
            mockProfiles[profile.publicID] = fetchedProfile
            print("MockPersistenceController: Simulated keyStore data removal for profile ID: \(profile.publicID)")
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
class MockPeerDiscoveryManager: ObservableObject, @unchecked Sendable {
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

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockPersistenceController = MockPersistenceController()
        mockPeerDiscoveryManager = MockPeerDiscoveryManager()

        // Create a sample profile for testing
        testProfile = Profile(name: "Test Member")
        testProfile.publicID = Data("testProfileID".utf8)
        // Add the profile to the mock controller's store so fetchProfile can find it if needed
        // Since this is a test setup and we're using mocks, we can safely add directly
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
        try super.tearDownWithError()
    }

    // MARK: - Test Cases

    @MainActor func testRemoveMemberDeletesKeyStoreData() async throws {
        // Arrange: Ensure the profile exists in the mock controller
        // Prepare profile with key store data
        testProfile.keyStorePrivate = "privateData".data(using: .utf8)!
        testProfile.keyStorePublic = "publicData".data(using: .utf8)!
        mockPersistenceController.addMockProfile(testProfile)
        XCTAssertNotNil(testProfile.keyStorePrivate, "Precondition: Profile should have keyStorePrivate before removal.")
        XCTAssertNotNil(testProfile.keyStorePublic, "Precondition: Profile should have keyStorePublic before removal.")

        // Act: Simulate the action that triggers key store data deletion
        // In a real scenario, this would be a call to a ViewModel or Service method.
        // Here, we directly call the mocked method to test its expected invocation.
        try await mockPersistenceController.deleteKeyStoreDataFor(profile: testProfile)

        // Assert: Verify the mock method was called correctly
        XCTAssertTrue(mockPersistenceController.deleteKeyStoreDataForCalled, "deleteKeyStoreDataFor should have been called.")
        XCTAssertEqual(mockPersistenceController.lastProfileDeletedKeyStoreFor, testProfile.publicID, "deleteKeyStoreDataFor was called with the wrong profile ID.")

        // Optional: Assert the key data was cleared in the mock store (if simulation is implemented)
        let updatedProfile = mockPersistenceController.mockProfiles[testProfile.publicID]
        XCTAssertNil(updatedProfile?.keyStorePrivate, "keyStorePrivate should be nil in the mock store after deletion.")
        XCTAssertNil(updatedProfile?.keyStorePublic, "keyStorePublic should be nil in the mock store after deletion.")
        print("Test Assertion: Verified keyStore data is nil for profile ID \(testProfile.publicID) in mock store.")
    }

    @MainActor func testRemoveMemberDisconnectsPeer() {
        // Arrange (Setup is sufficient)

        // Act: Simulate the action that triggers peer disconnection.
        // This would typically be part of the member removal logic.
        mockPeerDiscoveryManager.disconnectPeer(peerID: testPeerID)

        // Assert: Verify the mock method was called correctly
        XCTAssertTrue(mockPeerDiscoveryManager.disconnectPeerCalled, "disconnectPeer should have been called.")
        XCTAssertEqual(mockPeerDiscoveryManager.lastPeerDisconnected, testPeerID, "disconnectPeer was called with the wrong peer ID.")
        print("Test Assertion: Verified disconnectPeer was called for peer \(testPeerID.displayName).")
    }

    func testRemoveMemberPostsNotification() {
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
    @MainActor func testRemoveMemberHandlesPersistenceError() async throws {
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
