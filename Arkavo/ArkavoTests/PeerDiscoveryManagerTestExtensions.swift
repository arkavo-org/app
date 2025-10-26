@testable import Arkavo
import Foundation
import MultipeerConnectivity

// MARK: - Test Helper Extensions

@MainActor
extension PeerDiscoveryManager {
    // Test-only methods for simulating P2P interactions

    func configure(profile _: Profile, wsManager _: WebSocketManager) async {
        // Configure the peer manager with test profile
        // This would normally be done during app initialization
    }

    func updateConnectionStatus(_ status: ConnectionStatus) async {
        connectionStatus = status
    }

    func trackPeerConnection(peerID: MCPeerID, time: Date) async {
        peerConnectionTimes[peerID] = time
    }

    func getConnectionTime(for peerID: MCPeerID) async -> Date? {
        peerConnectionTimes[peerID]
    }

    func simulatePeerConnection(_ peerID: MCPeerID) async {
        connectedPeers.append(peerID)
        peerConnectionTimes[peerID] = Date()
        connectionStatus = .connected
    }

    func simulatePeerDisconnection(_ peerID: MCPeerID) async {
        connectedPeers.removeAll { $0 == peerID }
        peerConnectionTimes.removeValue(forKey: peerID)
        if connectedPeers.isEmpty {
            connectionStatus = .idle
        }
    }
}

// MARK: - Mock Data Extensions

extension Profile {
    static func createMockProfile(name: String = "Test User",
                                  handle: String? = "testuser",
                                  hasHighEncryption: Bool = false,
                                  hasHighIdentityAssurance: Bool = false) -> Profile
    {
        let profile = Profile(
            name: name,
            blurb: "Test bio for \(name)",
            interests: "Testing, Development",
            location: "Test City",
            hasHighEncryption: hasHighEncryption,
            hasHighIdentityAssurance: hasHighIdentityAssurance,
        )

        if let handle {
            profile.finalizeRegistration(did: "did:test:\(UUID().uuidString)", handle: handle)
        }

        return profile
    }

    func addMockKeyStore() {
        // Add mock key store data for testing
        keyStorePublic = Data([1, 2, 3, 4, 5, 6, 7, 8])
        keyStorePrivate = Data([9, 10, 11, 12, 13, 14, 15, 16])
    }
}

// MARK: - Connection Status Extension

extension ConnectionStatus {
    static let allCases: [ConnectionStatus] = [
        .idle,
        .searching,
        .connecting,
        .connected,
        .failed(NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])),
    ]
}

// MARK: - Base58 Encoding Extension (if not already available)

extension Data {
    var base58EncodedString: String {
        // Simple mock implementation for testing
        // In production, use a proper Base58 encoding library
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Test Helpers

enum ContactsTestHelper {
    static func createMockContacts(count: Int, in context: ModelContext) throws -> [Profile] {
        var contacts: [Profile] = []

        for i in 1 ... count {
            let contact = Profile.createMockProfile(
                name: "Contact \(i)",
                handle: "contact\(i)",
                hasHighEncryption: i % 2 == 0,
                hasHighIdentityAssurance: i % 3 == 0,
            )

            if i % 2 == 0 {
                contact.addMockKeyStore() // Mark as connected
            }

            context.insert(contact)
            contacts.append(contact)
        }

        try context.save()
        return contacts
    }

    static func simulateP2PHandshake(between peer1: PeerDiscoveryManager,
                                     and peer2: PeerDiscoveryManager,
                                     profile1: Profile,
                                     profile2: Profile) async throws
    {
        // Simulate the P2P handshake process
        let peer1ID = MCPeerID(displayName: profile1.name)
        let peer2ID = MCPeerID(displayName: profile2.name)

        // Simulate discovery
        await peer1.simulatePeerConnection(peer2ID)
        await peer2.simulatePeerConnection(peer1ID)

        // Simulate profile exchange
        if let profile1Data = try? JSONEncoder().encode(profile1),
           let profile2Data = try? JSONEncoder().encode(profile2)
        {
            // Peer 1 receives profile from Peer 2
            await peer1.handleProfileShare(from: peer2ID, profileData: profile2Data)

            // Peer 2 receives profile from Peer 1
            await peer2.handleProfileShare(from: peer1ID, profileData: profile1Data)
        }
    }
}

// MARK: - Mock P2P Message Handler

@MainActor
extension PeerDiscoveryManager {
    func handleProfileShare(from peerID: MCPeerID, profileData: Data) async {
        // Simulate handling profile share
        if let profile = try? JSONDecoder().decode(Profile.self, from: profileData) {
            connectedPeerProfiles[peerID] = profile
        }
    }
}
