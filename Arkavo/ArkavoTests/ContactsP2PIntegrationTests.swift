@testable import Arkavo
import MultipeerConnectivity
import SwiftData
import XCTest

@MainActor
final class ContactsP2PIntegrationTests: XCTestCase {
    var peerManager1: PeerDiscoveryManager!
    var peerManager2: PeerDiscoveryManager!
    var modelContainer: ModelContainer!
    var sharedState1: SharedState!
    var sharedState2: SharedState!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Profile.self, Stream.self, Thought.self,
            configurations: modelConfiguration,
        )

        // Initialize shared states
        sharedState1 = SharedState()
        sharedState2 = SharedState()

        // Create peer managers for two test devices
        peerManager1 = PeerDiscoveryManager()
        peerManager2 = PeerDiscoveryManager()

        // Create test profiles for each peer
        let profile1 = Profile(name: "Test User 1")
        let profile2 = Profile(name: "Test User 2")

        // Configure peer managers with profiles
        await peerManager1.configure(profile: profile1, wsManager: WebSocketManager())
        await peerManager2.configure(profile: profile2, wsManager: WebSocketManager())
    }

    override func tearDown() async throws {
        // Stop peer discovery
        peerManager1?.stopSearchingForPeers()
        peerManager2?.stopSearchingForPeers()

        // Clean up
        peerManager1 = nil
        peerManager2 = nil
        modelContainer = nil
        sharedState1 = nil
        sharedState2 = nil

        try await super.tearDown()
    }

    // MARK: - P2P Discovery Tests

    func testPeerDiscoveryInitialization() throws {
        XCTAssertNotNil(peerManager1)
        XCTAssertNotNil(peerManager2)
        XCTAssertFalse(peerManager1.isSearchingForPeers)
        XCTAssertFalse(peerManager2.isSearchingForPeers)
        XCTAssertEqual(peerManager1.connectionStatus, .idle)
        XCTAssertEqual(peerManager2.connectionStatus, .idle)
    }

    func testStartSearchingForPeers() throws {
        // Start searching on peer 1
        XCTAssertNoThrow(try peerManager1.startSearchingForPeers())
        XCTAssertTrue(peerManager1.isSearchingForPeers)
        XCTAssertEqual(peerManager1.connectionStatus, .searching)

        // Start searching on peer 2
        XCTAssertNoThrow(try peerManager2.startSearchingForPeers())
        XCTAssertTrue(peerManager2.isSearchingForPeers)
        XCTAssertEqual(peerManager2.connectionStatus, .searching)
    }

    func testStopSearchingForPeers() throws {
        // Start then stop searching
        try peerManager1.startSearchingForPeers()
        XCTAssertTrue(peerManager1.isSearchingForPeers)

        peerManager1.stopSearchingForPeers()
        XCTAssertFalse(peerManager1.isSearchingForPeers)
        XCTAssertEqual(peerManager1.connectionStatus, .idle)
    }

    // MARK: - Connection State Tests

    func testConnectionStatusTransitions() async throws {
        // Test idle -> searching
        XCTAssertEqual(peerManager1.connectionStatus, .idle)

        try peerManager1.startSearchingForPeers()
        XCTAssertEqual(peerManager1.connectionStatus, .searching)

        // Simulate connection found (would normally happen via MCNearbyServiceBrowser)
        await peerManager1.updateConnectionStatus(.connecting)
        XCTAssertEqual(peerManager1.connectionStatus, .connecting)

        // Simulate successful connection
        await peerManager1.updateConnectionStatus(.connected)
        XCTAssertEqual(peerManager1.connectionStatus, .connected)

        // Stop searching
        peerManager1.stopSearchingForPeers()
        XCTAssertEqual(peerManager1.connectionStatus, .idle)
    }

    // MARK: - Profile Exchange Tests

    func testProfileExchangePayload() throws {
        let profile = Profile(name: "Test User", handle: "testuser")
        profile.blurb = "Test bio"
        profile.interests = "Testing, Development"

        // Test encoding profile for exchange
        let encoder = JSONEncoder()
        let profileData = try encoder.encode(profile)
        let payload = ProfileSharePayload(profileData: profileData)

        // Test creating P2P message
        let messageData = try P2PMessage.encode(type: .profileShare, payload: payload)

        // Test decoding P2P message
        let decodedMessage = try P2PMessage.decode(from: messageData)
        XCTAssertEqual(decodedMessage.messageType, .profileShare)

        // Test decoding payload
        let decodedPayload = try decodedMessage.decodePayload(ProfileSharePayload.self)
        let decoder = JSONDecoder()
        let decodedProfile = try decoder.decode(Profile.self, from: decodedPayload.profileData)

        XCTAssertEqual(decodedProfile.name, profile.name)
        XCTAssertEqual(decodedProfile.handle, profile.handle)
        XCTAssertEqual(decodedProfile.blurb, profile.blurb)
        XCTAssertEqual(decodedProfile.interests, profile.interests)
    }

    // MARK: - Key Exchange Tests

    func testKeyExchangeStateTransitions() {
        var trackingInfo = KeyExchangeTrackingInfo()
        XCTAssertEqual(trackingInfo.state, .idle)

        // Test request sent
        let nonce = Data([1, 2, 3, 4])
        trackingInfo.state = .requestSent(nonce: nonce)
        XCTAssertEqual(trackingInfo.state.nonce, nonce)

        // Test offer received
        let offerNonce = Data([5, 6, 7, 8])
        trackingInfo.state = .offerReceived(nonce: offerNonce)
        XCTAssertEqual(trackingInfo.state.nonce, offerNonce)

        // Test completed
        trackingInfo.state = .completed(nonce: nonce)
        if case let .completed(completedNonce) = trackingInfo.state {
            XCTAssertEqual(completedNonce, nonce)
        } else {
            XCTFail("Expected completed state")
        }

        // Test failed
        trackingInfo.state = .failed("Test error")
        if case let .failed(error) = trackingInfo.state {
            XCTAssertEqual(error, "Test error")
        } else {
            XCTFail("Expected failed state")
        }
    }

    func testKeyStoreSharePayload() throws {
        let senderProfileID = "testuser123"
        let keyStoreData = Data([1, 2, 3, 4, 5]) // Mock key store data
        let timestamp = Date()

        let payload = KeyStoreSharePayload(
            senderProfileID: senderProfileID,
            keyStorePublicData: keyStoreData,
            timestamp: timestamp,
        )

        // Test encoding
        let messageData = try P2PMessage.encode(type: .keyStoreShare, payload: payload)

        // Test decoding
        let decodedMessage = try P2PMessage.decode(from: messageData)
        XCTAssertEqual(decodedMessage.messageType, .keyStoreShare)

        let decodedPayload = try decodedMessage.decodePayload(KeyStoreSharePayload.self)
        XCTAssertEqual(decodedPayload.senderProfileID, senderProfileID)
        XCTAssertEqual(decodedPayload.keyStorePublicData, keyStoreData)
        XCTAssertEqual(decodedPayload.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Remote Invitation Tests

    func testRemoteInvitationLinkGeneration() {
        let profile = Profile(name: "Test User")
        let publicIDString = profile.publicID.base58EncodedString
        let inviteLink = "https://app.arkavo.com/connect/\(publicIDString)"

        // Verify link format
        XCTAssertTrue(inviteLink.hasPrefix("https://app.arkavo.com/connect/"))
        XCTAssertTrue(inviteLink.contains(publicIDString))

        // Verify link can be parsed
        if let url = URL(string: inviteLink) {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "app.arkavo.com")
            XCTAssertTrue(url.path.hasPrefix("/connect/"))

            // Extract profile ID from URL
            let pathComponents = url.path.split(separator: "/")
            if pathComponents.count >= 2 {
                let extractedID = String(pathComponents[1])
                XCTAssertEqual(extractedID, publicIDString)
            }
        } else {
            XCTFail("Invalid URL generated")
        }
    }

    // MARK: - Connection Status Badge Tests

    func testConnectionStatusBadgeLogic() {
        let contact = Profile(name: "Test Contact")

        // Test not connected state
        XCTAssertNil(contact.keyStorePublic)
        XCTAssertFalse(contact.hasHighEncryption)

        // Simulate connected state
        contact.keyStorePublic = Data([1, 2, 3])
        XCTAssertNotNil(contact.keyStorePublic)

        // Test high encryption badge
        contact.hasHighEncryption = true
        XCTAssertTrue(contact.hasHighEncryption)

        // Test identity assurance badge
        contact.hasHighIdentityAssurance = true
        XCTAssertTrue(contact.hasHighIdentityAssurance)
    }

    // MARK: - Peer Connection Time Tracking Tests

    func testPeerConnectionTimeTracking() async {
        let peerID = MCPeerID(displayName: "TestPeer")
        let connectionTime = Date()

        // Track connection time
        await peerManager1.trackPeerConnection(peerID: peerID, time: connectionTime)

        let trackedTime = await peerManager1.getConnectionTime(for: peerID)
        XCTAssertNotNil(trackedTime)
        XCTAssertEqual(trackedTime?.timeIntervalSince1970, connectionTime.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Error Handling Tests

    func testP2PMessageDecodingErrors() {
        // Test invalid message data
        let invalidData = Data([0, 1, 2, 3])

        XCTAssertThrowsError(try P2PMessage.decode(from: invalidData)) { error in
            // Verify it's a decoding error
            XCTAssertTrue(error is DecodingError)
        }

        // Test invalid payload type
        let validMessage = P2PMessage(messageType: .profileShare, payload: Data())

        let encoder = JSONEncoder()
        if let messageData = try? encoder.encode(validMessage) {
            let decoded = try? P2PMessage.decode(from: messageData)
            XCTAssertNotNil(decoded)

            // Try to decode as wrong type
            XCTAssertThrowsError(try decoded?.decodePayload(KeyStoreSharePayload.self))
        }
    }
}
