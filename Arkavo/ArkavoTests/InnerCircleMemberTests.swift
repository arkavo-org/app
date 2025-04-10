import XCTest
@testable import Arkavo // Import your main app module

// MARK: - Mock Dependencies

// Assuming PeerId is a typealias or struct like: typealias PeerId = String
typealias PeerId = String

// Assuming PeerProfile and KeyStoreData are structs/classes in your project
struct PeerProfile {
    let peerId: PeerId
    let name: String
    // Add other relevant properties
}

struct KeyStoreData {
    let peerId: PeerId
    let key: Data
    // Add other relevant properties
}

// Define the protocols your mocks will conform to (if they don't exist, create them or use concrete types)
protocol PersistenceControllerProtocol {
    func getKeyStoreData(for peerId: PeerId) -> KeyStoreData?
    func getProfile(for peerId: PeerId) -> PeerProfile?
    func deleteKeyStoreDataFor(peerId: PeerId)
    func deleteProfile(peerId: PeerId)
    // Add other necessary methods
}

protocol PeerDiscoveryManagerProtocol {
    func disconnectPeer(peerId: PeerId)
    // Add other necessary methods
}

// Notification Name (replace with your actual notification name)
extension Notification.Name {
    static let didUpdateMembers = Notification.Name("didUpdateMembersNotification")
}


class MockPersistenceController: PersistenceControllerProtocol {
    var keyStoreDataStore: [PeerId: KeyStoreData] = [:]
    var profileStore: [PeerId: PeerProfile] = [:]

    var deleteKeyStoreDataForCalledWithPeerId: PeerId?
    var deleteProfileCalledWithPeerId: PeerId? // To verify it's NOT called

    func getKeyStoreData(for peerId: PeerId) -> KeyStoreData? {
        return keyStoreDataStore[peerId]
    }

    func getProfile(for peerId: PeerId) -> PeerProfile? {
        return profileStore[peerId]
    }

    func deleteKeyStoreDataFor(peerId: PeerId) {
        deleteKeyStoreDataForCalledWithPeerId = peerId
        keyStoreDataStore.removeValue(forKey: peerId)
        print("MockPersistenceController: deleteKeyStoreDataFor called for \(peerId)")
    }

    func deleteProfile(peerId: PeerId) {
        deleteProfileCalledWithPeerId = peerId
        profileStore.removeValue(forKey: peerId)
        print("MockPersistenceController: deleteProfile called for \(peerId)")
    }

    // Helper to reset state between tests
    func reset() {
        deleteKeyStoreDataForCalledWithPeerId = nil
        deleteProfileCalledWithPeerId = nil
        keyStoreDataStore = [:]
        profileStore = [:]
    }
}

class MockPeerDiscoveryManager: PeerDiscoveryManagerProtocol {
    var disconnectPeerCalledWithPeerId: PeerId?

    func disconnectPeer(peerId: PeerId) {
        disconnectPeerCalledWithPeerId = peerId
        print("MockPeerDiscoveryManager: disconnectPeer called for \(peerId)")
    }

    // Helper to reset state between tests
    func reset() {
        disconnectPeerCalledWithPeerId = nil
    }
}

// MARK: - InnerCircleManager (Example Class Under Test)

// Assume you have a class like this that handles the logic
// You might need to adapt this based on your actual implementation
class InnerCircleManager {
    let persistenceController: PersistenceControllerProtocol
    let peerDiscoveryManager: PeerDiscoveryManagerProtocol
    let notificationCenter: NotificationCenter

    init(persistenceController: PersistenceControllerProtocol,
         peerDiscoveryManager: PeerDiscoveryManagerProtocol,
         notificationCenter: NotificationCenter = .default) {
        self.persistenceController = persistenceController
        self.peerDiscoveryManager = peerDiscoveryManager
        self.notificationCenter = notificationCenter
    }

    func removeMember(peerId: PeerId) {
        print("InnerCircleManager: Attempting to remove member \(peerId)")
        // 1. Delete KeyStoreData (but not profile)
        persistenceController.deleteKeyStoreDataFor(peerId: peerId)

        // 2. Disconnect Peer
        peerDiscoveryManager.disconnectPeer(peerId: peerId)

        // 3. Post Notification
        notificationCenter.post(name: .didUpdateMembers, object: nil)
        print("InnerCircleManager: Posted didUpdateMembers notification")
    }
}


// MARK: - Test Class

class InnerCircleMemberTests: XCTestCase {

    var mockPersistenceController: MockPersistenceController!
    var mockPeerDiscoveryManager: MockPeerDiscoveryManager!
    var innerCircleManager: InnerCircleManager! // The class under test
    var notificationCenter: NotificationCenter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mockPersistenceController = MockPersistenceController()
        mockPeerDiscoveryManager = MockPeerDiscoveryManager()
        notificationCenter = NotificationCenter() // Use a specific instance for testing

        innerCircleManager = InnerCircleManager(
            persistenceController: mockPersistenceController,
            peerDiscoveryManager: mockPeerDiscoveryManager,
            notificationCenter: notificationCenter
        )
    }

    override func tearDownWithError() throws {
        mockPersistenceController = nil
        mockPeerDiscoveryManager = nil
        innerCircleManager = nil
        notificationCenter = nil
        try super.tearDownWithError()
    }

    func testRemoveMember_SuccessPath() throws {
        // Arrange
        let peerIdToRemove: PeerId = "peer-123"
        let memberProfile = PeerProfile(peerId: peerIdToRemove, name: "Test Member")
        let memberKeyData = KeyStoreData(peerId: peerIdToRemove, key: Data("testkey".utf8))

        // Pre-populate mock data
        mockPersistenceController.profileStore[peerIdToRemove] = memberProfile
        mockPersistenceController.keyStoreDataStore[peerIdToRemove] = memberKeyData

        // Expectation for the notification
        let notificationExpectation = XCTNSNotificationExpectation(
            name: .didUpdateMembers,
            object: nil, // Or specify the object if your manager sends itself
            notificationCenter: notificationCenter
        )
        notificationExpectation.expectedFulfillmentCount = 1 // Expect exactly one notification

        // Act
        innerCircleManager.removeMember(peerId: peerIdToRemove)

        // Assert

        // 1. Verify PersistenceController interactions
        XCTAssertEqual(mockPersistenceController.deleteKeyStoreDataForCalledWithPeerId, peerIdToRemove, "deleteKeyStoreDataFor should be called with the correct peerId")
        XCTAssertNil(mockPersistenceController.deleteProfileCalledWithPeerId, "deleteProfile should NOT be called")
        XCTAssertNil(mockPersistenceController.getKeyStoreData(for: peerIdToRemove), "KeyStoreData should be removed from the store")
        XCTAssertNotNil(mockPersistenceController.getProfile(for: peerIdToRemove), "Profile should NOT be removed from the store") // Verify profile still exists

        // 2. Verify PeerDiscoveryManager interaction
        XCTAssertEqual(mockPeerDiscoveryManager.disconnectPeerCalledWithPeerId, peerIdToRemove, "disconnectPeer should be called with the correct peerId")

        // 3. Verify Notification was posted
        wait(for: [notificationExpectation], timeout: 1.0) // Wait for the notification expectation to be fulfilled
    }

    // Add more tests here for edge cases if needed (e.g., removing a non-existent member)
    func testRemoveMember_NonExistentMember() throws {
         // Arrange
        let nonExistentPeerId: PeerId = "peer-does-not-exist"

        // Expectation for the notification (might still be posted depending on implementation)
        let notificationExpectation = XCTNSNotificationExpectation(
            name: .didUpdateMembers,
            notificationCenter: notificationCenter
        )
        notificationExpectation.expectedFulfillmentCount = 1 // Adjust if notification shouldn't post

        // Act
        innerCircleManager.removeMember(peerId: nonExistentPeerId)

        // Assert
        // Verify methods were still called with the non-existent ID
        XCTAssertEqual(mockPersistenceController.deleteKeyStoreDataForCalledWithPeerId, nonExistentPeerId)
        XCTAssertEqual(mockPeerDiscoveryManager.disconnectPeerCalledWithPeerId, nonExistentPeerId)
        XCTAssertNil(mockPersistenceController.deleteProfileCalledWithPeerId, "deleteProfile should NOT be called")

        // Verify notification
        wait(for: [notificationExpectation], timeout: 1.0)
    }
}
