import ArkavoSocial
import CryptoKit
@preconcurrency import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import SwiftUI
import UIKit

// MARK: - Notifications

extension Notification.Name {
    static let chatMessagesUpdated = Notification.Name("chatMessagesUpdatedNotification")
    static let nonJsonDataReceived = Notification.Name("nonJsonDataReceivedNotification")
    static let p2pMessageReceived = Notification.Name("p2pMessageReceivedNotification")
    static let profileSharedAndSaved = Notification.Name("profileSharedAndSavedNotification")
    static let keyStoreSharedAndSaved = Notification.Name("keyStoreSharedAndSavedNotification")
}

// MARK: - Data Structures

/// Basic info about the local KeyStore status.
struct LocalKeyStoreInfo: Equatable {
    let validKeyCount: Int
    let expiredKeyCount: Int
    let capacity: Int
}

// MARK: - Key Exchange Protocol Definitions

/// Represents the state of the secure key regeneration exchange with a specific peer.
enum KeyExchangeState: Codable, Equatable {
    case idle
    case requestSent(nonce: Data)
    case requestReceived(nonce: Data)
    case offerSent(nonce: Data)
    case offerReceived(nonce: Data)
    case ackSent(nonce: Data)
    case ackReceived(nonce: Data)
    case commitSent(nonce: Data)
    case commitReceivedWaitingForKeys(nonce: Data) // New state: Initiator received commit, waiting for peer keys
    case completed(nonce: Data)
    case failed(String)

    var nonce: Data? {
        switch self {
        case let .requestSent(n), let .requestReceived(n), let .offerSent(n),
             let .offerReceived(n), let .ackSent(n), let .ackReceived(n),
             let .commitSent(n), let .commitReceivedWaitingForKeys(n), let .completed(n):
            n
        case .idle, .failed:
            nil
        }
    }
}

/// Stores the tracking information for a key exchange with a peer.
struct KeyExchangeTrackingInfo: Codable, Equatable {
    var state: KeyExchangeState = .idle
    var lastActivity: Date = .init()
}

/// Enum defining the types of P2P messages exchanged directly between peers.
enum P2PMessageType: String, Codable {
    case keyRegenerationRequest
    case keyRegenerationOffer
    case keyRegenerationAcknowledgement
    case keyRegenerationCommit
    case profileShare
    case keyStoreShare
}

/// Wrapper for all direct P2P messages.
struct P2PMessage: Codable {
    let messageType: P2PMessageType
    let payload: Data // Encoded data of the specific message struct

    /// Encode a specific message payload into a P2PMessage Data object.
    static func encode(type: P2PMessageType, payload: some Codable) throws -> Data {
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(payload)
        let message = P2PMessage(messageType: type, payload: payloadData)
        return try encoder.encode(message)
    }

    /// Decode the outer P2PMessage structure.
    static func decode(from data: Data) throws -> P2PMessage {
        let decoder = JSONDecoder()
        return try decoder.decode(P2PMessage.self, from: data)
    }

    /// Decode the specific inner payload from a P2PMessage.
    func decodePayload<T: Codable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: payload)
    }
}

// MARK: - P2P Message Payloads

struct KeyRegenerationRequest: Codable {
    let requestID: UUID
    let initiatorProfileID: String // Base58 encoded public ID
    let timestamp: Date
}

struct KeyRegenerationOffer: Codable {
    let requestID: UUID
    let responderProfileID: String // Base58 encoded public ID
    let nonce: Data // Responder's nonce
    let timestamp: Date
}

struct KeyRegenerationAcknowledgement: Codable {
    let requestID: UUID
    let initiatorProfileID: String // Base58 encoded public ID
    let nonce: Data // Initiator's original nonce
    let timestamp: Date
}

struct KeyRegenerationCommit: Codable {
    let requestID: UUID
    let responderProfileID: String
    let timestamp: Date
}

/// Payload for the `.profileShare` P2P message.
struct ProfileSharePayload: Codable {
    let profileData: Data
}

/// Payload for the `.keyStoreShare` P2P message.
struct KeyStoreSharePayload: Codable {
    let senderProfileID: String
    let keyStorePublicData: Data
    let timestamp: Date
}

// MARK: - PeerDiscoveryManager Facade

/// Provides a simplified interface for peer discovery and P2P communication using MultipeerConnectivity and ArkavoClient.
@MainActor
class PeerDiscoveryManager: ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    @Published var localKeyStoreInfo: LocalKeyStoreInfo?
    @Published var isRegeneratingKeys: Bool = false
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]

    /// Map of connected MCPeerID to their Base58 encoded Profile Public ID string.
    var peerIDToProfileIDMap: [MCPeerID: String] {
        implementation.peerIDToProfileID
    }

    /// Exposes the current key exchange state with each connected peer.
    @Published var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]
    // Removed peerKeyCounts tracking

    private var implementation: P2PGroupViewModel

    init(arkavoClient: ArkavoClient) {
        implementation = P2PGroupViewModel(arkavoClient: arkavoClient)

        // Bind published properties from implementation to facade
        implementation.$connectedPeers.assign(to: &$connectedPeers)
        implementation.$isSearchingForPeers.assign(to: &$isSearchingForPeers)
        implementation.$selectedStream.assign(to: &$selectedStream)
        implementation.$connectionStatus.assign(to: &$connectionStatus)
        implementation.$peerConnectionTimes.assign(to: &$peerConnectionTimes)
        implementation.$localKeyStoreInfo.assign(to: &$localKeyStoreInfo)
        implementation.$isRegeneratingKeys.assign(to: &$isRegeneratingKeys)
        implementation.$connectedPeerProfiles.assign(to: &$connectedPeerProfiles)
        implementation.$peerKeyExchangeStates.assign(to: &$peerKeyExchangeStates)
        // Removed peerKeyCounts binding

        // REMOVED: arkavoClient.delegate = implementation (ArkavoMessageRouter is the delegate)
    }

    /// Sets up the Multipeer Connectivity session and advertiser/browser.
    func setupMultipeerConnectivity() async throws {
        try await implementation.setupMultipeerConnectivity()
    }

    /// Starts advertising and browsing for nearby peers.
    func startSearchingForPeers() throws {
        try implementation.startSearchingForPeers()
    }

    /// Stops advertising and browsing.
    func stopSearchingForPeers() {
        implementation.stopSearchingForPeers()
    }

    /// Returns the standard Multipeer Connectivity browser view controller.
    func getPeerBrowser() -> MCBrowserViewController? {
        implementation.getBrowser()
    }

    /// Fetches the locally stored Profile associated with a given MCPeerID.
    func getProfile(for peerID: MCPeerID) -> Profile? {
        implementation.connectedPeerProfiles[peerID]
    }

    /// Encrypts data using ArkavoClient and sends it via MCSession.
    func sendSecureData(_ data: Data, policy: String, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
        try await implementation.sendSecureData(data, policy: policy, toPeers: peers, in: stream)
    }

    /// Encrypts a text message using ArkavoClient and sends it.
    func sendSecureTextMessage(_ message: String, in stream: Stream) async throws {
        try await implementation.sendSecureTextMessage(message, in: stream)
    }

    /// Disconnects a specific peer from the session.
    func disconnectPeer(_ peer: MCPeerID) {
        implementation.disconnectPeer(peer)
    }

    /// Finds a connected peer by their Profile Public ID.
    func findPeer(byProfileID profileID: Data) -> MCPeerID? {
        implementation.findPeer(byProfileID: profileID)
    }

    /// Initiates the secure key regeneration protocol with a specific peer.
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        try await implementation.initiateKeyRegeneration(with: peer)
    }

    /// Sends a direct P2P message (e.g., profile share, key exchange) to designated peers.
    func sendP2PMessage(type: P2PMessageType, payload: some Codable, toPeers peers: [MCPeerID]) async throws {
        try await implementation.sendP2PMessage(type: type, payload: payload, toPeers: peers)
    }
}

/// Represents the current state of the Multipeer Connectivity connection.
enum ConnectionStatus: Equatable {
    case idle
    case searching
    case connecting
    case connected
    case failed(Error)

    static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.searching, .searching),
             (.connecting, .connecting), (.connected, .connected):
            true
        case let (.failed(lhsError), .failed(rhsError)):
            // Compare based on localized description for simplicity
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

// MARK: - P2PGroupViewModel Implementation

/// Handles the underlying MultipeerConnectivity logic, ArkavoClient integration, and P2P protocols.
@MainActor
class P2PGroupViewModel: NSObject, ObservableObject { // REMOVED: ArkavoClientDelegate
    // MultipeerConnectivity components
    private var mcSession: MCSession?
    private var mcPeerID: MCPeerID?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCBrowserViewController?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?

    private let arkavoClient: ArkavoClient

    // Published properties (mirrored by PeerDiscoveryManager)
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    @Published var localKeyStoreInfo: LocalKeyStoreInfo?
    @Published var isRegeneratingKeys: Bool = false
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:] // Cache of fetched peer profiles
    @Published var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:] // Tracks key exchange state per peer
    // Removed peerKeyCounts tracking

    // Internal tracking
    private var resourceProgress: [String: Progress] = [:]
    private var activeInputStreams: [InputStream: MCPeerID] = [:] // Tracks open streams by peer

    /// Specific errors related to P2P operations.
    enum P2PError: Error, LocalizedError {
        case sessionNotInitialized
        case invalidStream // Attempted operation on non-InnerCircle stream
        case browserNotInitialized
        case profileNotAvailable
        case serializationFailed(String)
        case deserializationFailed(String)
        case persistenceError(String)
        case noConnectedPeers
        case keyGenerationFailed(String) // OpenTDFKit key generation error
        case arkavoClientError(String) // General ArkavoClient error
        case policyCreationFailed(String)
        case peerNotFoundForDisconnection(String)
        case keyStoreInfoUnavailable(String) // Error fetching KeyStore details
        case keyExchangeError(String) // Key exchange protocol error
        case peerNotConnected(String) // Operation requires a connected peer
        case invalidStateForAction(String) // Key exchange state machine error
        case missingNonce // Key exchange error
        case keyStoreDataNotFound(String) // Missing KeyStore data in profile
        case keyStoreDeserializationFailed(String)
        case keyStoreSerializationFailed(String)
        case keyStoreInitializationFailed(String) // Error creating new KeyStore
        case profileSharingError(String) // Profile sharing specific error
        case keyStoreSharingError(String) // KeyStore sharing specific error
        case keyStorePublicDataExtractionFailed(String) // Error getting public KeyStore data

        var errorDescription: String? {
            // Concise descriptions for each case
            switch self {
            case .sessionNotInitialized: "P2P session not initialized"
            case .invalidStream: "Not a valid InnerCircle stream"
            case .browserNotInitialized: "Browser controller not initialized"
            case .profileNotAvailable: "User profile not available"
            case let .serializationFailed(context): "Serialization failed: \(context)"
            case let .deserializationFailed(context): "Deserialization failed: \(context)"
            case let .persistenceError(context): "Persistence error: \(context)"
            case .noConnectedPeers: "No connected peers"
            case let .keyGenerationFailed(reason): "Key generation failed: \(reason)"
            case let .arkavoClientError(reason): "ArkavoClient error: \(reason)"
            case let .policyCreationFailed(reason): "Policy creation failed: \(reason)"
            case let .peerNotFoundForDisconnection(reason): "Peer not found for disconnection: \(reason)"
            case let .keyStoreInfoUnavailable(reason): "KeyStore info unavailable: \(reason)"
            case let .keyExchangeError(reason): "Key exchange error: \(reason)"
            case let .peerNotConnected(reason): "Peer not connected: \(reason)"
            case let .invalidStateForAction(reason): "Invalid state for action: \(reason)"
            case .missingNonce: "Nonce missing for key exchange"
            case let .keyStoreDataNotFound(reason): "KeyStore data not found: \(reason)"
            case let .keyStoreDeserializationFailed(reason): "KeyStore deserialization failed: \(reason)"
            case let .keyStoreSerializationFailed(reason): "KeyStore serialization failed: \(reason)"
            case let .keyStoreInitializationFailed(reason): "KeyStore initialization failed: \(reason)"
            case let .profileSharingError(reason): "Profile sharing error: \(reason)"
            case let .keyStoreSharingError(reason): "KeyStore sharing error: \(reason)"
            case let .keyStorePublicDataExtractionFailed(reason): "Public KeyStore data extraction failed: \(reason)"
            }
        }
    }

    /// Map MCPeerID to ProfileID (Base58 String) for lookups. Accessible by PeerDiscoveryManager.
    var peerIDToProfileID: [MCPeerID: String] = [:]

    private let persistenceController = PersistenceController.shared

    // MARK: - Initialization and Cleanup

    init(arkavoClient: ArkavoClient) {
        self.arkavoClient = arkavoClient
        super.init()
        // ArkavoClient delegate is set by PeerDiscoveryManager
    }

    deinit {
        // Need to use Task for actor-isolated methods in deinit
        _ = Task { @MainActor [weak self] in
            self?.cleanup()
        }
    }

    private func cleanup() {
        stopSearchingForPeers()
        mcSession?.disconnect()
        invitationHandler = nil
        peerIDToProfileID.removeAll()
        connectedPeerProfiles.removeAll()
        peerKeyExchangeStates.removeAll()
        activeInputStreams.keys.forEach { $0.close() }
        activeInputStreams.removeAll()
        resourceProgress.removeAll()
        localKeyStoreInfo = nil
        isRegeneratingKeys = false
        connectedPeers = []
        connectionStatus = .idle
        print("P2PGroupViewModel cleaned up.")
    }

    // MARK: - MultipeerConnectivity Setup

    func setupMultipeerConnectivity() async throws {
        cleanup() // Ensure clean state

        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            connectionStatus = .failed(P2PError.profileNotAvailable)
            throw P2PError.profileNotAvailable
        }

        mcPeerID = MCPeerID(displayName: profile.name)
        guard let mcPeerID else { return } // Should always succeed

        mcSession = MCSession(peer: mcPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self

        let serviceType = "arkavo-circle"

        // Include essential info for discovery and identification
        let discoveryInfo: [String: String] = [
            "profileID": profile.publicID.base58EncodedString,
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": "\(Date().timeIntervalSince1970)",
            "name": profile.name,
        ]

        mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: mcPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType,
        )
        mcAdvertiser?.delegate = self

        mcBrowser = MCBrowserViewController(serviceType: serviceType, session: mcSession!)
        mcBrowser?.delegate = self

        connectionStatus = .idle
        print("MultipeerConnectivity setup complete for \(profile.name)")
    }

    func startSearchingForPeers() throws {
        guard mcSession != nil else {
            connectionStatus = .failed(P2PError.sessionNotInitialized)
            throw P2PError.sessionNotInitialized
        }
        mcAdvertiser?.startAdvertisingPeer()
        isSearchingForPeers = true
        connectionStatus = .searching
        print("Started advertising and searching for peers.")
    }

    func stopSearchingForPeers() {
        mcAdvertiser?.stopAdvertisingPeer()
        isSearchingForPeers = false
        if connectedPeers.isEmpty {
            connectionStatus = .idle
        } else {
            connectionStatus = .connected // Remain connected if peers exist
        }
        print("Stopped advertising and searching.")
    }

    /// Finds a connected peer by their Profile Public ID (Data).
    func findPeer(byProfileID profileID: Data) -> MCPeerID? {
        let profileIDString = profileID.base58EncodedString
        guard let foundPeerID = peerIDToProfileID.first(where: { $0.value == profileIDString })?.key else {
            print("FindPeer: Profile ID \(profileIDString) not found in map.")
            return nil
        }
        // Verify the found peer is actually connected
        if connectedPeers.contains(where: { $0.hashValue == foundPeerID.hashValue }) {
            return foundPeerID
        } else {
            print("FindPeer: Warning - MCPeerID \(foundPeerID.displayName) found in map but not in connectedPeers list.")
            // Optionally clean up inconsistent map entry here
            // peerIDToProfileID.removeValue(forKey: foundPeerID)
            return nil
        }
    }

    /// Disconnects a specific peer from the MCSession.
    func disconnectPeer(_ peer: MCPeerID) {
        let profileID = peerIDToProfileID[peer] ?? "Unknown"
        print("DisconnectPeer: Attempting disconnection for \(peer.displayName) (Profile: \(profileID))")

        guard let session = mcSession else {
            print("DisconnectPeer Error: Session not active.")
            return
        }

        // Check if the peer (by hash value) is in the connected list
        let isPeerConnected = connectedPeers.contains { $0.hashValue == peer.hashValue }

        guard isPeerConnected else {
            print("DisconnectPeer Warning: Peer \(peer.displayName) not found in connectedPeers list. Cleanup might be needed.")
            // Clean up lingering data just in case state is inconsistent
            if peerIDToProfileID[peer] != nil { peerIDToProfileID.removeValue(forKey: peer) }
            if connectedPeerProfiles[peer] != nil { connectedPeerProfiles.removeValue(forKey: peer) }
            peerConnectionTimes.removeValue(forKey: peer)
            peerKeyExchangeStates.removeValue(forKey: peer)
            return
        }

        print("DisconnectPeer: Proceeding with session disconnect for \(peer.displayName)")
        session.cancelConnectPeer(peer) // Request disconnection

        // Rely on the MCSessionDelegate's `didChange state: .notConnected` callback
        // for the primary cleanup (removing from lists, closing streams etc.)
        // This avoids race conditions if the delegate callback is delayed.
        print("DisconnectPeer: Disconnection initiated for \(peer.displayName). Waiting for delegate callback.")
    }

    /// Returns the MCBrowserViewController for presentation.
    func getBrowser() -> MCBrowserViewController? {
        mcBrowser
    }

    // MARK: - Data Transmission

    /// Sends raw data via MCSession (used for P2P messages and by ArkavoClient).
    private func sendRawData(_ data: Data, toPeers peers: [MCPeerID]) throws {
        guard let mcSession else { throw P2PError.sessionNotInitialized }
        guard !peers.isEmpty else {
            print("Warning: sendRawData called with empty peer list.")
            return
        }

        // Ensure peers are currently connected before sending
        let connectedPeerHashes = Set(mcSession.connectedPeers.map(\.hashValue))
        let targetPeersToSend = peers.filter { connectedPeerHashes.contains($0.hashValue) }

        guard !targetPeersToSend.isEmpty else {
            let targetNames = peers.map(\.displayName).joined(separator: ", ")
            print("Error: None of the target peers (\(targetNames)) are currently connected.")
            throw P2PError.peerNotConnected("Target peers [\(targetNames)] not connected.")
        }

        if targetPeersToSend.count < peers.count {
            let missingPeers = peers.filter { !connectedPeerHashes.contains($0.hashValue) }
            print("Warning: Not sending data to disconnected peers: \(missingPeers.map(\.displayName))")
        }

        print("Sending \(data.count) bytes raw data to \(targetPeersToSend.count) peers: \(targetPeersToSend.map(\.displayName))")
        try mcSession.send(data, toPeers: targetPeersToSend, with: .reliable)
    }

    /// Encodes and sends a structured P2P message.
    func sendP2PMessage(type: P2PMessageType, payload: some Codable, toPeers peers: [MCPeerID]) async throws {
        print("Encoding P2P message type \(type) for peers: \(peers.map(\.displayName))")
        do {
            let dataToSend = try P2PMessage.encode(type: type, payload: payload)
            try sendRawData(dataToSend, toPeers: peers)
            print("Successfully sent P2P message type \(type)")
        } catch let error as P2PError {
            print("❌ P2PError sending \(type): \(error)")
            throw error
        } catch {
            print("❌ Error encoding/sending P2P message \(type): \(error)")
            throw P2PError.serializationFailed("Encoding/Sending \(type): \(error.localizedDescription)")
        }
    }

    /// Encrypts data using ArkavoClient and sends it via MCSession for InnerCircle streams.
    func sendSecureData(_ data: Data, policy: String, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
        // Ensure this function is only used for InnerCircle streams where P2P makes sense
        guard stream.isInnerCircleStream else {
            print("❌ Error: sendSecureData called on a non-InnerCircle stream. This function requires P2P context.")
            throw P2PError.invalidStream
        }
        guard let mcSession else { throw P2PError.sessionNotInitialized }

        // Determine target peers (default to all connected if nil)
        let targetPeers = peers ?? mcSession.connectedPeers
        guard !targetPeers.isEmpty else {
            print("Warning: sendSecureData called with no target peers.")
            return // Or throw P2PError.noConnectedPeers
        }

        guard let policyData = policy.data(using: .utf8) else {
            throw P2PError.policyCreationFailed("Failed to encode policy JSON string")
        }

        print("Processing secure data send for \(targetPeers.count) peer(s) in InnerCircle stream '\(stream.profile.name)'...")

        // Process each target peer individually to use their specific KAS key
        for peer in targetPeers {
            var peerKasMetadata: KasMetadata? = nil
            do {
                print("      Deserializing PublicKeyStore for \(peer.displayName)...")

                // 1. Get Peer Profile
                guard let peerProfile = connectedPeerProfiles[peer] else {
                    print("      ❌ Error: Profile not found locally for peer \(peer.displayName). Cannot get PublicKeyStore. Skipping peer.")
                    continue // Skip this peer
                }

                // 2. Get Peer's Public KeyStore Data
                guard let keyStorePublicData = peerProfile.keyStorePublic, !keyStorePublicData.isEmpty else {
                    print("      ❌ Error: Peer \(peer.displayName) profile (\(peerProfile.name)) does not have public KeyStore data. Skipping peer.")
                    // Optional: Initiate key exchange if missing?
                    continue // Skip this peer
                }

                // 1. Create an instance of PublicKeyStore for the peer's curve
                //    TODO: Determine the correct curve dynamically if necessary. Using p256 for now.
                let publicKeyStore = PublicKeyStore(curve: .secp256r1) // Create an instance

                // 2. Deserialize *into* the existing instance
                try await publicKeyStore.deserialize(from: keyStorePublicData) // Call instance method

                print("      PublicKeyStore deserialized successfully.")

                // 4. Create KasMetadata using the peer's KeyStore instance
                // Use the peer's profile ID as the resource locator body for KAS identification
                let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: peerProfile.publicID.base58EncodedString)!
                // Now call createKasMetadata on the deserialized instance
                peerKasMetadata = try await publicKeyStore.createKasMetadata(resourceLocator: kasRL)
                print("      Created peer-specific KasMetadata for \(peer.displayName).")
            }

            // Ensure we actually created KasMetadata
            guard let finalKasMetadata = peerKasMetadata else {
                print("      ❌ Error: Failed to create KasMetadata for peer \(peer.displayName) (internal logic error). Skipping peer.")
                continue // Skip this peer
            }

            // 5. Encrypt using ArkavoClient, providing the specific peer's KasMetadata
            print("      Encrypting payload using ArkavoClient with peer's KasMetadata...")
            do {
                let nanoTDFData = try await arkavoClient.encryptAndSendPayload(
                    payload: data,
                    policyData: policyData,
                    kasMetadata: finalKasMetadata, // Provide the specific KAS metadata
                )
                print("      Encryption successful. NanoTDF size: \(nanoTDFData.count) bytes.")

                // 6. Send the resulting NanoTDF data via P2P (MultipeerConnectivity)
                print("      Sending encrypted NanoTDF via P2P to \(peer.displayName)...")
                try sendRawData(nanoTDFData, toPeers: [peer]) // Send only to this specific peer
                print("      ✅ Successfully sent secure data via P2P to \(peer.displayName).")

            } catch let encryptOrSendError {
                print("      ❌ Error encrypting payload or sending P2P data to \(peer.displayName): \(encryptOrSendError)")
                // Decide if you want to stop processing other peers on error, or just continue
                // For now, we continue with the next peer.
            }
        }
        print("Finished processing all target peers for secure data send.")
    }

    /// Encrypts and sends a text message securely.
    func sendSecureTextMessage(_ message: String, in stream: Stream) async throws {
        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }
        let streamID = stream.publicID
        let messageData = Data(message.utf8)

        // Simple policy granting access based on a stream-specific attribute.
        // Assumes recipients acquire this attribute through other means (e.g., KAS).
        let policyJson = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [ { "attribute": "stream:\(streamID.base58EncodedString)" } ],
            "dissem": []
          }
        }
        """
        // Note: ArkavoClient might expect only the policy *body* as `policyData`.
        // Adjust if necessary based on ArkavoClient's API documentation.
        print("Using policy for secure text message: \(policyJson)")

        // Use the generic secure data sending method
        try await sendSecureData(messageData, policy: policyJson, in: stream)

        // Persist the original (unencrypted) message locally as a Thought
        Task {
            do {
                let thought = try await storeP2PMessageAsThought(
                    content: message,
                    sender: profile.name,
                    senderProfileID: profile.publicID.base58EncodedString,
                    timestamp: Date(),
                    stream: stream,
                    nanoData: nil, // Indicate it's unencrypted content
                )
                print("✅ Local text message stored as Thought ID: \(thought.id)")
                await MainActor.run {
                    NotificationCenter.default.post(name: .chatMessagesUpdated, object: nil)
                }
            } catch {
                print("❌ Failed to store local P2P message as Thought: \(error)")
            }
        }
    }

    // MARK: - Message Handling

    /// Routes incoming data: P2P messages or encrypted data for ArkavoClient.
    private func handleIncomingData(_ data: Data, from peer: MCPeerID) {
        // Try decoding as a standard P2PMessage first
        do {
            let p2pMessage = try P2PMessage.decode(from: data)
            print("Received P2PMessage type: \(p2pMessage.messageType) from \(peer.displayName)")
            // Handle known P2P message types
            switch p2pMessage.messageType {
            case .keyRegenerationRequest: handleKeyRegenerationRequest(from: peer, data: p2pMessage.payload)
            case .keyRegenerationOffer: handleKeyRegenerationOffer(from: peer, data: p2pMessage.payload)
            case .keyRegenerationAcknowledgement: handleKeyRegenerationAcknowledgement(from: peer, data: p2pMessage.payload)
            case .keyRegenerationCommit: handleKeyRegenerationCommit(from: peer, data: p2pMessage.payload)
            case .profileShare: handleProfileShare(from: peer, data: p2pMessage.payload)
            case .keyStoreShare: handleKeyStoreShare(from: peer, data: p2pMessage.payload)
            }
        } catch {
            // If not a standard P2PMessage, assume it's encrypted data for ArkavoClient
            print("Data from \(peer.displayName) not a P2PMessage. Passing to ArkavoClient.")
            // ArkavoClient needs to process this data, potentially via a specific method
            // or internal handling linked to its delegate calls.
            // Example: Task { await arkavoClient.processReceivedP2PData(data, fromPeerID: peer) }
            // Post notification if ArkavoClient doesn't handle directly
            NotificationCenter.default.post(
                name: .nonJsonDataReceived,
                object: nil,
                userInfo: ["data": data, "peer": peer],
            )
        }
    }

    /// Stores a received P2P message (usually decrypted text) as a Thought.
    private func storeP2PMessageAsThought(content: String, sender _: String, senderProfileID: String, timestamp: Date, stream: Stream, nanoData: Data?) async throws -> Thought {
        guard let senderPublicID = Data(base58Encoded: senderProfileID) else {
            throw P2PError.deserializationFailed("Invalid sender profile ID")
        }

        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: senderPublicID,
            streamPublicID: stream.publicID,
            mediaType: .say, // Use .say for P2P text messages
            createdAt: timestamp,
            contributors: [],
        )

        // Use provided nanoData (e.g., encrypted) or convert content string (decrypted)
        let dataToStore = nanoData ?? Data(content.utf8)

        // 1. Create Thought object in memory
        let thought = Thought(nano: dataToStore, metadata: thoughtMetadata)

        // 2. Fetch the associated Stream from the context
        guard let managedStream = try await persistenceController.fetchStream(withPublicID: stream.publicID) else {
            print("❌ Error: Could not find managed stream \(stream.publicID.base58EncodedString) to associate thought.")
            // 4. Throw error if stream not found, do not save thought
            throw P2PError.persistenceError("Could not find stream \(stream.publicID.base58EncodedString) to associate thought.")
        }

        // 3. Establish relationship and save Thought *only if* stream was found
        print("   Found managed stream: \(managedStream.profile.name). Associating thought...")
        thought.stream = managedStream // Associate with the managed stream object
        managedStream.addThought(thought) // Add to the stream's collection

        // Insert the new thought into the context *before* saving changes
        // Note: SwiftData might handle insertion automatically when relationship is set,
        // but explicit insertion ensures it's managed.
        if thought.modelContext == nil {
            persistenceController.mainContext.insert(thought)
            print("   Inserted new thought into context.")
        }

        // Save changes to persist the new thought and the updated stream relationship
        try await PersistenceController.shared.saveChanges()
        print("✅ P2P message stored as Thought (\(thought.publicID.base58EncodedString)) and associated with stream \(managedStream.publicID.base58EncodedString).")

        return thought
    }

    // MARK: - Profile & KeyStore Sharing Handling

    /// Handles incoming ProfileShare P2P messages.
    private func handleProfileShare(from peer: MCPeerID, data: Data) {
        print("Received ProfileShare from \(peer.displayName)")
        Task {
            do {
                let payload: ProfileSharePayload = try P2PMessage(messageType: .profileShare, payload: data).decodePayload(ProfileSharePayload.self)
                let sharedProfile = try Profile.fromData(payload.profileData)
                let profileIDString = sharedProfile.publicID.base58EncodedString
                print("Deserialized Profile: \(sharedProfile.name) (\(profileIDString))")

                // Save/Update the peer profile locally
                try await persistenceController.savePeerProfile(sharedProfile, keyStorePublicData: nil)
                print("Saved/Updated shared profile \(sharedProfile.name) locally.")

                // Notify relevant views (e.g., GroupViewModel) to update
                NotificationCenter.default.post(
                    name: .profileSharedAndSaved,
                    object: nil,
                    userInfo: ["profilePublicID": sharedProfile.publicID], // Send public ID
                )
            } catch {
                print("❌ Error handling ProfileShare from \(peer.displayName): \(error)")
            }
        }
    }

    /// Handles incoming KeyStoreShare P2P messages.
    private func handleKeyStoreShare(from peer: MCPeerID, data: Data) {
        print("Received KeyStoreShare from \(peer.displayName)")
        Task {
            do {
                let payload: KeyStoreSharePayload = try P2PMessage(messageType: .keyStoreShare, payload: data).decodePayload(KeyStoreSharePayload.self)
                let senderProfileIDString = payload.senderProfileID
                let receivedPublicData = payload.keyStorePublicData
                print("Decoded KeyStoreSharePayload from \(senderProfileIDString). Public data: \(receivedPublicData.count) bytes.")

                guard let senderProfileID = Data(base58Encoded: senderProfileIDString) else {
                    throw P2PError.keyStoreSharingError("Invalid sender profile ID format")
                }

                // Fetch the sender's profile locally to attach the KeyStore data
                guard let senderProfile = try await persistenceController.fetchProfile(withPublicID: senderProfileID) else {
                    // Profile must exist locally first (likely from a ProfileShare message)
                    print("❌ KeyStoreShare Error: Sender profile \(senderProfileIDString) not found locally. Cannot save public KeyStore.")
                    return
                }
                print("Found local profile for sender (peer): \(senderProfile.name)")

                // Save/Update the *peer's* profile with their received *public* KeyStore data
                try await persistenceController.savePeerProfile(senderProfile, keyStorePublicData: receivedPublicData)
                print("✅ Saved/Updated peer's public KeyStore data to profile \(senderProfile.name)'s keyStorePublic field.")

                // Notify relevant views
                NotificationCenter.default.post(
                    name: .keyStoreSharedAndSaved,
                    object: nil,
                    userInfo: ["profilePublicID": senderProfileID],
                )

                // --- Check Key Exchange State and Complete Protocol ---
                if let currentStateInfo = peerKeyExchangeStates[peer] {
                    let currentState = currentStateInfo.state
                    print("KeyExchange: Received KeyStoreShare from \(peer.displayName). Current state: \(currentState)")

                    switch currentState {
                    case let .commitSent(nonce): // Responder was waiting for keys
                        print("KeyExchange (Responder): Received keys from Initiator. Completing protocol.")
                        updatePeerExchangeState(for: peer, newState: .completed(nonce: nonce))
                    case let .commitReceivedWaitingForKeys(nonce): // Initiator was waiting for keys
                        print("KeyExchange (Initiator): Received keys from Responder. Completing protocol.")
                        updatePeerExchangeState(for: peer, newState: .completed(nonce: nonce))
                    default:
                        print("KeyExchange: Received KeyStoreShare in unexpected state (\(currentState)). No state transition.")
                    }
                } else {
                    print("KeyExchange: Received KeyStoreShare, but no key exchange state found for peer \(peer.displayName).")
                }
                // --- End Key Exchange State Check ---

                // Refresh peer profiles/counts after successfully saving new KeyStore data
                await refreshConnectedPeerProfiles()

            } catch let error as P2PError {
                print("❌ KeyStoreShare: P2PError handling message from \(peer.displayName): \(error)")
                // Optionally update key exchange state to failed if appropriate
                if peerKeyExchangeStates[peer] != nil {
                    updatePeerExchangeState(for: peer, newState: .failed("Error processing KeyStoreShare: \(error.localizedDescription)"))
                }
            } catch {
                print("❌ KeyStoreShare: Unexpected error handling message from \(peer.displayName): \(error)")
                // Optionally update key exchange state to failed if appropriate
                if peerKeyExchangeStates[peer] != nil {
                    updatePeerExchangeState(for: peer, newState: .failed("Unexpected error processing KeyStoreShare: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Local Profile & KeyStore Management

    /// Fetches Profiles for currently connected peers from persistence.
    private func refreshConnectedPeerProfiles() async {
        print("Refreshing connected peer profiles cache...")
        var updatedProfiles: [MCPeerID: Profile] = [:]
        let currentPeers = connectedPeers // Capture current list

        for peer in currentPeers {
            // Get profile ID from the map
            guard let profileIDString = peerIDToProfileID[peer],
                  let profileIDData = Data(base58Encoded: profileIDString)
            else {
                print("No profile ID mapped for peer \(peer.displayName), cannot fetch profile.")
                continue
            }

            do {
                if let profile = try await persistenceController.fetchProfile(withPublicID: profileIDData) {
                    updatedProfiles[peer] = profile
                } else {
                    print("Profile \(profileIDString) for peer \(peer.displayName) not found locally.")
                }
            } catch {
                print("❌ Error fetching profile \(profileIDString) for peer \(peer.displayName): \(error)")
            }
        }

        connectedPeerProfiles = updatedProfiles
        print("Finished refreshing peer profiles. Found \(updatedProfiles.count) profiles locally.")

        // --- Add fetched profiles to the selected InnerCircle stream ---
        if let currentStream = selectedStream, currentStream.isInnerCircleStream {
            print("   InnerCircle stream selected. Attempting to add fetched profiles...")
            var streamUpdated = false
            for (_, profile) in updatedProfiles {
                if !currentStream.isInInnerCircle(profile) {
                    print("   Adding profile \(profile.name) (\(profile.publicID.base58EncodedString)) to stream \(currentStream.profile.name)")
                    currentStream.addToInnerCircle(profile)
                    streamUpdated = true
                }
            }
            if streamUpdated {
                do {
                    try await persistenceController.saveChanges()
                    print("   Saved updates to InnerCircle stream members.")
                    // Optionally post a notification if InnerCircleView needs an explicit refresh trigger beyond @State changes
                    // NotificationCenter.default.post(name: .refreshInnerCircleMembers, object: nil)
                } catch {
                    print("❌ Error saving InnerCircle stream after adding profiles: \(error)")
                }
            } else {
                print("   No new profiles to add to the InnerCircle stream.")
            }
        } else {
            print("   No InnerCircle stream selected, skipping profile addition to stream.")
        }
        // --- End profile addition ---

        // --- KeyStore count calculation removed ---
    }

    // MARK: - Secure Key Regeneration Protocol Implementation

    /// Generates a cryptographically secure nonce.
    private func generateNonce(size: Int = 32) -> Data {
        var keyData = Data(count: size)
        let result = keyData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!)
        }
        guard result == errSecSuccess else {
            print("Warning: SecRandomCopyBytes failed. Using fallback nonce.")
            return Data((0 ..< size).map { _ in UInt8.random(in: .min ... .max) })
        }
        return keyData
    }

    /// Updates the key exchange state for a peer and logs the change.
    private func updatePeerExchangeState(for peer: MCPeerID, newState: KeyExchangeState) {
        var info = peerKeyExchangeStates[peer] ?? KeyExchangeTrackingInfo()
        info.state = newState
        info.lastActivity = Date()
        peerKeyExchangeStates[peer] = info
        print("KeyExchange State [\(peer.displayName)]: \(newState)")
    }

    /// Initiates the key regeneration protocol with a peer. (Step 1)
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        print("KeyExchange: Initiating with \(peer.displayName)")
        guard let session = mcSession, session.connectedPeers.contains(peer) else {
            throw P2PError.peerNotConnected("Peer \(peer.displayName) not connected.")
        }
        guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }

        // Allow initiation only from idle or failed state
        let currentState = peerKeyExchangeStates[peer]?.state ?? .idle
        guard currentState == .idle || currentState.nonce == nil else { // Check if failed or idle
            throw P2PError.invalidStateForAction("Cannot initiate key exchange, state is \(currentState)")
        }

        let nonce = generateNonce()
        let request = KeyRegenerationRequest(
            requestID: UUID(),
            initiatorProfileID: myProfile.publicID.base58EncodedString,
            timestamp: Date(),
        )

        // Update state *before* sending
        updatePeerExchangeState(for: peer, newState: .requestSent(nonce: nonce))

        do {
            try await sendP2PMessage(type: .keyRegenerationRequest, payload: request, toPeers: [peer])
            print("KeyExchange: Sent Request to \(peer.displayName)")
        } catch {
            // Rollback state on send failure
            updatePeerExchangeState(for: peer, newState: .failed("Failed to send request: \(error.localizedDescription)"))
            throw error
        }
    }

    /// Handles incoming KeyRegenerationRequest. (Step 2: Responder)
    private func handleKeyRegenerationRequest(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received Request from \(peer.displayName)")
        Task {
            do {
                let request: KeyRegenerationRequest = try P2PMessage(messageType: .keyRegenerationRequest, payload: data).decodePayload(KeyRegenerationRequest.self)
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }

                // Allow processing only from idle or failed state
                let currentState = peerKeyExchangeStates[peer]?.state ?? .idle
                guard currentState == .idle || currentState.nonce == nil else {
                    print("KeyExchange: Ignoring Request from \(peer.displayName), already in state \(currentState)")
                    return
                }

                let nonce = generateNonce() // Responder's nonce
                let offer = KeyRegenerationOffer(
                    requestID: request.requestID,
                    responderProfileID: myProfile.publicID.base58EncodedString,
                    nonce: nonce,
                    timestamp: Date(),
                )

                // Update state *before* sending
                updatePeerExchangeState(for: peer, newState: .requestReceived(nonce: nonce)) // Store *our* (responder's) nonce

                try await sendP2PMessage(type: .keyRegenerationOffer, payload: offer, toPeers: [peer])
                print("KeyExchange: Sent Offer to \(peer.displayName)")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .offerSent(nonce: nonce))

            } catch {
                print("❌ KeyExchange: Error handling Request from \(peer.displayName): \(error)")
                updatePeerExchangeState(for: peer, newState: .failed("Error processing request: \(error.localizedDescription)"))
            }
        }
    }

    /// Handles incoming KeyRegenerationOffer. (Step 3: Initiator)
    private func handleKeyRegenerationOffer(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received Offer from \(peer.displayName)")
        Task {
            do {
                let offer: KeyRegenerationOffer = try P2PMessage(messageType: .keyRegenerationOffer, payload: data).decodePayload(KeyRegenerationOffer.self)
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }
                // Must be in RequestSent state to process an Offer
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case let .requestSent(initiatorNonce) = currentStateInfo.state
                else {
                    print("KeyExchange: Ignoring Offer from \(peer.displayName), not in RequestSent state.")
                    return
                }

                let ack = KeyRegenerationAcknowledgement(
                    requestID: offer.requestID,
                    initiatorProfileID: myProfile.publicID.base58EncodedString,
                    nonce: initiatorNonce, // Send back *our* original nonce
                    timestamp: Date(),
                )

                // Update state *before* sending
                updatePeerExchangeState(for: peer, newState: .offerReceived(nonce: initiatorNonce))

                try await sendP2PMessage(type: .keyRegenerationAcknowledgement, payload: ack, toPeers: [peer])
                print("KeyExchange: Sent Acknowledgement to \(peer.displayName)")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .ackSent(nonce: initiatorNonce))

                // --- Initiator's Key Generation & Share Trigger ---
                guard let peerProfileIDData = Data(base58Encoded: offer.responderProfileID) else {
                    throw P2PError.keyExchangeError("Invalid peer profile ID in offer")
                }
                print("KeyExchange (Initiator): Triggering local key regeneration for peer \(offer.responderProfileID)")
                let localPublicKeyStoreData = try await performKeyGenerationAndSave(peerProfileIDData: peerProfileIDData, peer: peer)
                print("KeyExchange (Initiator): Local key regeneration successful. Sharing public keys...")

                // Send own public KeyStore data to the peer
                let keySharePayload = KeyStoreSharePayload(
                    senderProfileID: myProfile.publicID.base58EncodedString,
                    keyStorePublicData: localPublicKeyStoreData,
                    timestamp: Date(),
                )
                try await sendP2PMessage(type: .keyStoreShare, payload: keySharePayload, toPeers: [peer])
                print("KeyExchange (Initiator): Sent KeyStoreShare to \(peer.displayName)")
                // State remains ackSent, waiting for Commit and peer's KeyStoreShare

            } catch {
                print("❌ KeyExchange: Error handling Offer, regenerating/sharing keys (Initiator) for \(peer.displayName): \(error)")
                let errorMessage = (error as? P2PError)?.localizedDescription ?? error.localizedDescription
                updatePeerExchangeState(for: peer, newState: .failed("Error processing offer/regenerating: \(errorMessage)"))
            }
        }
    }

    /// Handles incoming KeyRegenerationAcknowledgement. (Step 4: Responder)
    private func handleKeyRegenerationAcknowledgement(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received Acknowledgement from \(peer.displayName)")
        Task {
            do {
                let ack: KeyRegenerationAcknowledgement = try P2PMessage(messageType: .keyRegenerationAcknowledgement, payload: data).decodePayload(KeyRegenerationAcknowledgement.self)
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }
                // Must be in OfferSent state to process an Ack
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case let .offerSent(responderNonce) = currentStateInfo.state
                else {
                    print("KeyExchange: Ignoring Ack from \(peer.displayName), not in OfferSent state.")
                    return
                }

                let commit = KeyRegenerationCommit(
                    requestID: ack.requestID,
                    responderProfileID: myProfile.publicID.base58EncodedString,
                    timestamp: Date(),
                )

                // Update state *before* sending
                updatePeerExchangeState(for: peer, newState: .ackReceived(nonce: responderNonce))

                try await sendP2PMessage(type: .keyRegenerationCommit, payload: commit, toPeers: [peer])
                print("KeyExchange: Sent Commit to \(peer.displayName)")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .commitSent(nonce: responderNonce)) // Final state for responder

                // --- Responder's Key Generation & Share Trigger ---
                guard let peerProfileIDData = Data(base58Encoded: ack.initiatorProfileID) else {
                    throw P2PError.keyExchangeError("Invalid peer profile ID in ack")
                }
                print("KeyExchange (Responder): Triggering local key regeneration for peer \(ack.initiatorProfileID)")
                let localPublicKeyStoreData = try await performKeyGenerationAndSave(peerProfileIDData: peerProfileIDData, peer: peer)
                print("KeyExchange (Responder): Local key regeneration successful. Sharing public keys...")

                // Send own public KeyStore data to the peer
                let keySharePayload = KeyStoreSharePayload(
                    senderProfileID: myProfile.publicID.base58EncodedString,
                    keyStorePublicData: localPublicKeyStoreData,
                    timestamp: Date(),
                )
                try await sendP2PMessage(type: .keyStoreShare, payload: keySharePayload, toPeers: [peer])
                print("KeyExchange (Responder): Sent KeyStoreShare to \(peer.displayName)")
                // State remains commitSent, waiting for peer's KeyStoreShare

            } catch {
                print("❌ KeyExchange: Error handling Ack, regenerating/sharing keys (Responder) for \(peer.displayName): \(error)")
                let errorMessage = (error as? P2PError)?.localizedDescription ?? error.localizedDescription
                updatePeerExchangeState(for: peer, newState: .failed("Error processing ack/regenerating: \(errorMessage)"))
            }
        }
    }

    /// Handles incoming KeyRegenerationCommit. (Step 5: Initiator)
    private func handleKeyRegenerationCommit(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received Commit from \(peer.displayName)")
        Task {
            do {
                let commit: KeyRegenerationCommit = try P2PMessage(messageType: .keyRegenerationCommit, payload: data).decodePayload(KeyRegenerationCommit.self)
                // Must be in AckSent state to process a Commit
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case let .ackSent(initiatorNonce) = currentStateInfo.state
                else {
                    print("KeyExchange: Ignoring Commit from \(peer.displayName), not in AckSent state.")
                    return
                }

                // Received Commit, now waiting for peer's KeyStoreShare
                print("KeyExchange (Initiator): Received Commit from \(peer.displayName) (ReqID: \(commit.requestID)). Waiting for peer keys.")
                updatePeerExchangeState(for: peer, newState: .commitReceivedWaitingForKeys(nonce: initiatorNonce))

            } catch {
                print("❌ KeyExchange: Error handling Commit from \(peer.displayName): \(error)")
                // Keep the state as ackSent or move to failed? Let's move to failed for clarity.
                updatePeerExchangeState(for: peer, newState: .failed("Error processing commit: \(error.localizedDescription)"))
            }
        }
    }

    /// Performs local key generation/regeneration using OpenTDFKit, saves the updated private KeyStore to the Profile,
    /// and returns the corresponding public KeyStore data.
    /// - Returns: The serialized public KeyStore data.
    private func performKeyGenerationAndSave(peerProfileIDData: Data, peer: MCPeerID) async throws -> Data {
        print("KeyExchange: Performing OpenTDFKit key generation/save (Profile.keyStorePrivate)... Peer: \(peerProfileIDData.base58EncodedString)")

        let keyStore = KeyStore(curve: .secp256r1)

        do {
            // Generate exactly 8192 keys into the new store
            print("   Generating 8192 key pairs...")
            try await keyStore.generateAndStoreKeyPairs(count: 8192)

            // Serialize updated private KeyStore
            let updatedSerializedData = await keyStore.serialize()
            print("   Serialized updated KeyStore (\(updatedSerializedData.count) bytes).")

            // --- Save Local Private Keys to Peer's Profile ---
            // Fetch the peer's profile from the context to save the local private keys generated for this relationship.
            guard let peerProfile = try await persistenceController.fetchProfile(withPublicID: peerProfileIDData) else {
                let errorMsg = "Peer profile \(peerProfileIDData.base58EncodedString) not found locally. Cannot save local private KeyStore for this relationship."
                print("❌ KeyExchange: \(errorMsg)")
                updatePeerExchangeState(for: peer, newState: .failed(errorMsg))
                throw P2PError.keyStoreSharingError(errorMsg)
            }
            print("   Found peer profile \(peerProfile.name) to store local private keys.")
            // Save the generated *private* keys to the *peer's* profile record.
            try await persistenceController.savePeerProfile(peerProfile, keyStorePrivateData: updatedSerializedData)
            print("   ✅ Saved local private KeyStore data to peer profile \(peerProfile.name)'s keyStorePrivate field.")
            // --- End Save ---

            // Extract and return the public data for sharing with the peer
            let publicKeyStore = await keyStore.exportPublicKeyStore()
            let publicData = await publicKeyStore.serialize()
            // Use await on the property access
            await print("   Extracted public KeyStore data (\((publicKeyStore.publicKeys).count) keys, \(publicData.count) bytes).")
            return publicData

        } catch {
            // Catch errors from deserialization, generation, serialization, save, or public key extraction
            print("❌ KeyExchange: Failed during key generation/save: \(error)")
            let errorMessage = (error as? P2PError)?.localizedDescription ?? error.localizedDescription
            updatePeerExchangeState(for: peer, newState: .failed("Key generation/save failed: \(errorMessage)"))
            throw error // Re-throw to calling context
        }
    }

    // MARK: - REMOVED ArkavoClientDelegate Methods

    // P2PGroupViewModel now relies on NotificationCenter for updates from the primary delegate (ArkavoMessageRouter).
    // The delegate methods previously here have been removed as they are no longer called.
}

// MARK: - MCSessionDelegate

extension P2PGroupViewModel: MCSessionDelegate {
    nonisolated func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Determine state string outside actor context
        let stateStr: String = {
            switch state {
            case .notConnected: return "Not Connected"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            @unknown default: return "Unknown"
            }
        }()
        print("MCSessionDelegate: Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) -> \(stateStr)")

        Task { @MainActor in
            switch state {
            case .connected:
                self.invitationHandler = nil // Clear pending invitation
                // Add peer if not already present (use hashValue for comparison)
                if !self.connectedPeers.contains(where: { $0.hashValue == peerID.hashValue }) {
                    self.connectedPeers.append(peerID)
                    self.peerConnectionTimes[peerID] = Date()
                    self.peerKeyExchangeStates[peerID] = KeyExchangeTrackingInfo() // Initialize key exchange state
                    self.connectionStatus = .connected
                    print("✅ Connected to peer: \(peerID.displayName)")

                    // Fetch and cache profile for the newly connected peer
                    await self.refreshConnectedPeerProfiles() // Refresh for all, including new one

                } else {
                    print("ℹ️ Received connected state for already known peer: \(peerID.displayName)")
                    // Optionally re-fetch profile if needed
                    if self.connectedPeerProfiles[peerID] == nil {
                        await self.refreshConnectedPeerProfiles()
                    }
                }
                // Ensure status updates even if connection is brief
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.connectionStatus = (self?.connectedPeers.isEmpty ?? true) ? (self?.isSearchingForPeers ?? false ? .searching : .idle) : .connected
                }

            case .connecting:
                print("⏳ Connecting to peer: \(peerID.displayName)...")
                if self.connectionStatus != .connected { // Avoid overriding if already connected to others
                    self.connectionStatus = .connecting
                }
                // Simple timeout logic
                let peerHash = peerID.hashValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self else { return }
                    if connectionStatus == .connecting, !connectedPeers.contains(where: { $0.hashValue == peerHash }) {
                        print("⚠️ Connection to \(peerID.displayName) timed out.")
                        if connectedPeers.isEmpty {
                            connectionStatus = isSearchingForPeers ? .searching : .idle
                        }
                    }
                }

            case .notConnected:
                print("❌ Disconnected from peer: \(peerID.displayName)")
                if self.connectionStatus == .connecting { self.invitationHandler = nil }

                // --- Primary Cleanup Location ---
                let profileID = self.peerIDToProfileID[peerID] // Get ID before removal
                let peerHash = peerID.hashValue

                // Remove from tracking collections
                self.connectedPeers.removeAll { $0.hashValue == peerHash }
                self.peerIDToProfileID.removeValue(forKey: peerID)
                self.connectedPeerProfiles.removeValue(forKey: peerID) // Remove profile cache
                self.peerConnectionTimes.removeValue(forKey: peerID)
                self.peerKeyExchangeStates.removeValue(forKey: peerID) // Remove key exchange state

                print("   Cleanup for \(peerID.displayName) (Profile: \(profileID ?? "N/A")) complete.")

                // Close associated input streams
                let streamsToRemove = self.activeInputStreams.filter { $1.hashValue == peerHash }.keys
                if !streamsToRemove.isEmpty {
                    print("   Closing \(streamsToRemove.count) input stream(s) for \(peerID.displayName)")
                    streamsToRemove.forEach { self.closeAndRemoveStream($0) }
                }

                // Update overall connection status
                if self.connectedPeers.isEmpty {
                    print("   No connected peers remaining.")
                    self.connectionStatus = self.isSearchingForPeers ? .searching : .idle
                } else {
                    print("   \(self.connectedPeers.count) peers still connected.")
                    self.connectionStatus = .connected
                }

            @unknown default:
                print(" MCSessionDelegate: Unknown state \(state) for \(peerID.displayName)")
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Route data to the main actor handler
        Task { @MainActor in
            handleIncomingData(data, from: peerID)
        }
    }

    nonisolated func session(_: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received stream '\(streamName)' from \(peerID.displayName)")
        Task { @MainActor in
            self.activeInputStreams[stream] = peerID
            stream.delegate = self // Use nonisolated delegate reference
            stream.schedule(in: .main, forMode: .default)
            stream.open()
            print("Opened and tracking input stream from \(peerID.displayName)")
        }
    }

    nonisolated func session(_: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            print("Receiving resource '\(resourceName)' from \(peerID.displayName)...")
            resourceProgress[resourceName] = progress
            // Optionally observe progress updates here
        }
    }

    nonisolated func session(_: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            resourceProgress.removeValue(forKey: resourceName)
            if let error {
                print("Error receiving resource '\(resourceName)' from \(peerID.displayName): \(error)")
                return
            }
            guard let url = localURL else {
                print("No URL for received resource '\(resourceName)'")
                return
            }
            print("Successfully received resource '\(resourceName)' at \(url.path)")
            // TODO: Consider security implications. Resources likely need encryption/decryption via ArkavoClient.
            saveReceivedResource(at: url, withName: resourceName) // Simple local save for now
        }
    }

    /// Saves a received resource to the documents directory.
    private func saveReceivedResource(at url: URL, withName name: String) {
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(name)
            // Overwrite if exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: url, to: destinationURL)
            print("Saved resource '\(name)' to: \(destinationURL.path)")
        } catch {
            print("Error saving resource '\(name)': \(error)")
        }
    }
}

// MARK: - MCBrowserViewControllerDelegate

extension P2PGroupViewModel: MCBrowserViewControllerDelegate {
    nonisolated func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        print("Browser finished.")
        Task { @MainActor in browserViewController.dismiss(animated: true) }
    }

    nonisolated func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        print("Browser cancelled.")
        Task { @MainActor in browserViewController.dismiss(animated: true) }
    }

    nonisolated func browserViewController(_: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) -> Bool {
        // Check if the peer is already connected before proceeding
        Task { @MainActor in
            if self.connectedPeers.contains(where: { $0.hashValue == peerID.hashValue }) {
                print("⚠️ MCBrowserViewController shouldn't be receiving this callback for connected peer: \(peerID.displayName). Returning false.")
                // Returning false here prevents the browser from showing the already connected peer.
                // Note: This Task runs asynchronously, the return true below might execute first.
                // A synchronous check might be better if feasible, but requires careful state management.
            } else {
                print("Browser found peer: \(peerID.displayName) with info: \(info ?? [:])")
                // Associate ProfileID from discovery info immediately if available
                if let profileID = info?["profileID"] {
                    print("   Peer \(peerID.displayName) has Profile ID: \(profileID)")
                    // Update map if new or different
                    if self.peerIDToProfileID[peerID] != profileID {
                        self.peerIDToProfileID[peerID] = profileID
                        print("   Associated peer \(peerID.displayName) with profile ID \(profileID)")
                    }
                } else {
                    print("   Peer \(peerID.displayName) did not provide profileID in discovery info.")
                }
            }
        }
        return true // Always allow presentation in the browser
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension P2PGroupViewModel: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Advertiser received invitation from: \(peerID.displayName)")
        Task { @MainActor in
            self.invitationHandler = invitationHandler // Store handler for acceptance

            // Extract ProfileID from context if provided
            var peerProfileID: String? = nil
            if let contextData = context,
               let contextDict = try? JSONSerialization.jsonObject(with: contextData) as? [String: String]
            {
                print("   Invitation context: \(contextDict)")
                peerProfileID = contextDict["profileID"]
            }

            // Update map with ProfileID from context
            if let profileID = peerProfileID {
                if self.peerIDToProfileID[peerID] != profileID {
                    self.peerIDToProfileID[peerID] = profileID
                    print("   Associated peer \(peerID.displayName) with profile ID \(profileID) from context")
                }
            } else {
                print("   No profile ID found in invitation context for \(peerID.displayName)")
            }

            // Auto-accept invitation for simplicity in this example
            print("   Auto-accepting invitation from \(peerID.displayName)")
            invitationHandler(true, self.mcSession)
            // Clear handler after use (could also be done in session delegate .connected/.notConnected)
            // self.invitationHandler = nil // Let session delegate clear potentially
        }
    }

    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Advertiser failed to start: \(error.localizedDescription)")
        Task { @MainActor in self.connectionStatus = .failed(error) }
    }
}

// MARK: - StreamDelegate

extension P2PGroupViewModel: Foundation.StreamDelegate {
    nonisolated func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }

        Task { @MainActor in
            // Find associated peer before potential stream removal
            let peerID = self.activeInputStreams[inputStream]
            let peerDesc = peerID?.displayName ?? "Unknown Peer"

            switch eventCode {
            case .hasBytesAvailable:
                // print("StreamDelegate: HasBytesAvailable from \(peerDesc)")
                self.readInputStream(inputStream) // Read data -> handleIncomingData -> ArkavoClient
            case .endEncountered:
                print("StreamDelegate: EndEncountered from \(peerDesc)")
                self.closeAndRemoveStream(inputStream)
            case .errorOccurred:
                print("StreamDelegate: ErrorOccurred from \(peerDesc): \(aStream.streamError?.localizedDescription ?? "N/A")")
                self.closeAndRemoveStream(inputStream)
            case .openCompleted:
                print("StreamDelegate: OpenCompleted for stream from \(peerDesc)")
            case .hasSpaceAvailable: // Usually for OutputStream
                break // print("StreamDelegate: HasSpaceAvailable for stream from \(peerDesc)")
            default:
                print("StreamDelegate: Unhandled event \(eventCode) for stream from \(peerDesc)")
            }
        }
    }

    /// Reads available data from an input stream and passes it to `handleIncomingData`.
    private func readInputStream(_ stream: InputStream) {
        guard let peerID = activeInputStreams[stream] else {
            print("StreamDelegate Error: Data from untracked stream. Closing.")
            closeAndRemoveStream(stream)
            return
        }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        var data = Data()

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else if bytesRead < 0 {
                print("StreamDelegate Error reading from \(peerID.displayName): \(stream.streamError?.localizedDescription ?? "N/A")")
                closeAndRemoveStream(stream)
                return
            } else { // bytesRead == 0 usually means end of stream or temporary pause
                break
            }
        }

        if !data.isEmpty {
            // print("StreamDelegate: Read \(data.count) bytes from \(peerID.displayName)")
            handleIncomingData(data, from: peerID) // Route the data
        }
    }

    /// Closes an input stream and removes it from tracking.
    private func closeAndRemoveStream(_ stream: InputStream) {
        stream.remove(from: .main, forMode: .default)
        stream.close()
        if let peerID = activeInputStreams.removeValue(forKey: stream) {
            print("StreamDelegate: Closed and removed stream for \(peerID.displayName)")
        } else {
            print("StreamDelegate: Closed an untracked stream.")
        }
    }
}
