import ArkavoSocial
@preconcurrency import MultipeerConnectivity
import OpenTDFKit // Keep OpenTDFKit import if ArkavoClient APIs require it
import SwiftData
import SwiftUI
import UIKit
import CryptoKit // Import for nonce generation

// Define custom notification names
extension Notification.Name {
    static let chatMessagesUpdated = Notification.Name("chatMessagesUpdatedNotification")
    // Add notification name for non-JSON data received
    static let nonJsonDataReceived = Notification.Name("nonJsonDataReceivedNotification")
    // Define notification name for P2P message received (used by ArkavoClient delegate)
    static let p2pMessageReceived = Notification.Name("p2pMessageReceivedNotification")
}

// Define the struct for detailed KeyStore info (based on GroupView summary)
// Ensure this struct is accessible where needed (e.g., here or a shared Models file)
struct LocalKeyStoreInfo: Equatable {
    let validKeyCount: Int
    let expiredKeyCount: Int
    let capacity: Int
}

// MARK: - Key Exchange Protocol Definitions

/// Represents the state of the secure key regeneration exchange with a specific peer.
enum KeyExchangeState: Codable, Equatable {
    case idle
    case requestSent(nonce: Data) // Initiator state
    case requestReceived(nonce: Data) // Responder state
    case offerSent(nonce: Data) // Responder state
    case offerReceived(nonce: Data) // Initiator state
    case ackSent(nonce: Data) // Initiator state
    case ackReceived(nonce: Data) // Responder state
    case commitSent(nonce: Data) // Responder state (final state for responder)
    case completed(nonce: Data) // Initiator state (final state for initiator)
    case failed(String)

    // Helper to get the nonce, regardless of state
    var nonce: Data? {
        switch self {
        case .requestSent(let n), .requestReceived(let n), .offerSent(let n),
             .offerReceived(let n), .ackSent(let n), .ackReceived(let n),
             .commitSent(let n), .completed(let n):
            return n
        case .idle, .failed:
            return nil
        }
    }
}

/// Stores the tracking information for a key exchange with a peer.
struct KeyExchangeTrackingInfo: Codable, Equatable {
    var state: KeyExchangeState = .idle
    var lastActivity: Date = Date() // For potential timeout logic
}

/// Enum defining the types of P2P messages exchanged directly between peers.
enum P2PMessageType: String, Codable {
    case keyRegenerationRequest
    case keyRegenerationOffer
    case keyRegenerationAcknowledgement
    case keyRegenerationCommit
    // Add other direct P2P message types here if needed (e.g., profile exchange)
    // Note: Secure text messages are handled via ArkavoClient encryption/decryption delegates
}

/// Wrapper for all direct P2P messages.
struct P2PMessage: Codable {
    let messageType: P2PMessageType
    let payload: Data // Encoded data of the specific message struct (e.g., KeyRegenerationRequest)

    // Helper to encode a specific message payload
    static func encode<T: Codable>(type: P2PMessageType, payload: T) throws -> Data {
        let encoder = JSONEncoder()
        let payloadData = try encoder.encode(payload)
        let message = P2PMessage(messageType: type, payload: payloadData)
        return try encoder.encode(message)
    }

    // Helper to decode the outer message
    static func decode(from data: Data) throws -> P2PMessage {
        let decoder = JSONDecoder()
        return try decoder.decode(P2PMessage.self, from: data)
    }

    // Helper to decode the specific inner payload
    func decodePayload<T: Codable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: payload)
    }
}

// --- Key Exchange Message Payloads ---

struct KeyRegenerationRequest: Codable {
    let requestID: UUID // Unique ID for this request instance
    let initiatorProfileID: String // Base58 encoded public ID
    let timestamp: Date
}

struct KeyRegenerationOffer: Codable {
    let requestID: UUID // Corresponds to the request
    let responderProfileID: String // Base58 encoded public ID
    let nonce: Data // Responder's nonce for the shared key generation
    let timestamp: Date
}

struct KeyRegenerationAcknowledgement: Codable {
    let requestID: UUID // Corresponds to the request
    let initiatorProfileID: String // Base58 encoded public ID
    let nonce: Data // Initiator's nonce (matches the one sent in requestSent state)
    let timestamp: Date
}

struct KeyRegenerationCommit: Codable {
    let requestID: UUID // Corresponds to the request
    let responderProfileID: String // Base58 encoded public ID
    let timestamp: Date
    // No nonce needed here, implicitly uses the one from the Offer
}

// MARK: - PeerDiscoveryManager

// Public interface for peer discovery
@MainActor
class PeerDiscoveryManager: ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    // KeyStore status properties - now uses LocalKeyStoreInfo
    @Published var localKeyStoreInfo: LocalKeyStoreInfo? // UPDATED TYPE
    @Published var isRegeneratingKeys: Bool = false
    // Expose peer profiles fetched from persistence
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]
    // Expose peerID to ProfileID mapping
    var peerIDToProfileIDMap: [MCPeerID: String] {
        implementation.peerIDToProfileID
    }
    // Expose key exchange status
    @Published var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]


    private var implementation: P2PGroupViewModel

    // Inject ArkavoClient instance
    init(arkavoClient: ArkavoClient) {
        implementation = P2PGroupViewModel(arkavoClient: arkavoClient)

        // Forward published properties
        implementation.$connectedPeers.assign(to: &$connectedPeers)
        implementation.$isSearchingForPeers.assign(to: &$isSearchingForPeers)
        implementation.$selectedStream.assign(to: &$selectedStream)
        implementation.$connectionStatus.assign(to: &$connectionStatus)
        implementation.$peerConnectionTimes.assign(to: &$peerConnectionTimes)
        // Forward KeyStore status properties (UPDATED TYPE)
        implementation.$localKeyStoreInfo.assign(to: &$localKeyStoreInfo) // Assignment remains the same, type is forwarded
        implementation.$isRegeneratingKeys.assign(to: &$isRegeneratingKeys)
        // Forward peer profiles
        implementation.$connectedPeerProfiles.assign(to: &$connectedPeerProfiles)
        // Forward key exchange states
        implementation.$peerKeyExchangeStates.assign(to: &$peerKeyExchangeStates)


        // Set the delegate for ArkavoClient to receive events
        arkavoClient.delegate = implementation
    }

    func setupMultipeerConnectivity(for stream: Stream) async throws {
        try await implementation.setupMultipeerConnectivity(for: stream)
    }

    func startSearchingForPeers() throws {
        try implementation.startSearchingForPeers()
    }

    func stopSearchingForPeers() {
        implementation.stopSearchingForPeers()
    }

    // Text message sending is now handled by ArkavoClient via P2PGroupViewModel
    // func sendTextMessage(_ message: String, in stream: Stream) throws {
    //     try implementation.sendTextMessage(message, in: stream)
    // }

    func getPeerBrowser() -> MCBrowserViewController? {
        implementation.getBrowser()
    }

    /// Handle a rewrap request for encrypted communication (delegated to ArkavoClient)
    /// - Parameters:
    ///   - publicKey: The ephemeral public key from the rewrap request
    ///   - encryptedSessionKey: The encrypted session key that needs to be rewrapped
    ///   - senderProfileID: Optional profile ID of the sender (used for tracking/logging)
    /// - Returns: Rewrapped key data or nil if no matching key found
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data, senderProfileID: String? = nil) async throws -> Data? {
        try await implementation.handleRewrapRequest(
            publicKey: publicKey,
            encryptedSessionKey: encryptedSessionKey,
            senderProfileID: senderProfileID
        )
    }

    // KeyStore status management delegated to ArkavoClient
    /// Updates the local KeyStore status information.
    func refreshKeyStoreStatus() async {
        await implementation.refreshKeyStoreStatus()
    }

    /// Manually triggers the regeneration of keys in the local KeyStore.
    func regenerateLocalKeys() async {
        await implementation.regenerateLocalKeys()
    }

    /// Fetches the Profile associated with a given MCPeerID.
    func getProfile(for peerID: MCPeerID) -> Profile? {
        implementation.connectedPeerProfiles[peerID]
    }

    /// Sends data securely using ArkavoClient
    /// - Parameters:
    ///   - data: The raw data to encrypt and send
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    ///   - stream: The stream context for the data
    ///   - policy: The TDF policy to apply (as a JSON string)
    /// - Throws: Errors if encryption or sending fails
    func sendSecureData(_ data: Data, policy: String, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
        try await implementation.sendSecureData(data, policy: policy, toPeers: peers, in: stream)
    }

    /// Sends a secure text message using ArkavoClient
    func sendSecureTextMessage(_ message: String, in stream: Stream) async throws {
        try await implementation.sendSecureTextMessage(message, in: stream)
    }

    /// Disconnects a specific peer from the session.
    /// - Parameter peer: The MCPeerID of the peer to disconnect.
    func disconnectPeer(_ peer: MCPeerID) {
        implementation.disconnectPeer(peer)
    }

    /// Finds a connected peer by their Profile ID.
    /// - Parameter profileID: The public profile ID (Data) of the peer to find.
    /// - Returns: The `MCPeerID` of the connected peer, or `nil` if not found.
    func findPeer(byProfileID profileID: Data) -> MCPeerID? {
        implementation.findPeer(byProfileID: profileID)
    }

    /// Initiates the secure key regeneration process with a specific peer.
    /// - Parameter peer: The `MCPeerID` of the peer to regenerate keys with.
    /// - Throws: `P2PError` if the process cannot be initiated.
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        try await implementation.initiateKeyRegeneration(with: peer)
    }
}

// Connection status enum for UI feedback
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
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

// Implementation class for MultipeerConnectivity, integrating ArkavoClient
@MainActor
class P2PGroupViewModel: NSObject, ObservableObject, ArkavoClientDelegate {
    // Conform to ArkavoClientDelegate - Implementations are further down
    // Removed empty delegate methods:
    // - clientDidChangeState
    // - clientDidReceiveMessage(Data)
    // - clientDidReceiveError(any Error)

    // MultipeerConnectivity properties
    private var mcSession: MCSession?
    private var mcPeerID: MCPeerID?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCBrowserViewController?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?

    // Arkavo Client for secure communication
    private let arkavoClient: ArkavoClient // Inject ArkavoClient

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    // KeyStore status properties - now uses LocalKeyStoreInfo
    @Published var localKeyStoreInfo: LocalKeyStoreInfo? // UPDATED TYPE
    @Published var isRegeneratingKeys: Bool = false
    // Store fetched peer profiles
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]
    // Track key exchange state per peer
    @Published var peerKeyExchangeStates: [MCPeerID: KeyExchangeTrackingInfo] = [:]


    // For tracking resources
    private var resourceProgress: [String: Progress] = [:]
    // For tracking streams
    private var activeInputStreams: [InputStream: MCPeerID] = [:] // Track streams by peer

    // Error types (Keep relevant ones, remove KeyStore stub related errors)
    enum P2PError: Error, LocalizedError {
        case sessionNotInitialized
        case invalidStream
        case browserNotInitialized
        // case keyStoreNotInitialized // Replaced by ArkavoClient errors
        case profileNotAvailable
        case serializationFailed(String)
        case deserializationFailed(String)
        case persistenceError(String)
        case noConnectedPeers
        // case keyRemovalFailed(String) // Handled by ArkavoClient
        // case keyGenerationFailed(String) // Handled by ArkavoClient
        // case keySerializationError(String) // Handled by ArkavoClient
        case arkavoClientError(String) // General ArkavoClient error
        case policyCreationFailed(String) // Added for policy errors
        case peerNotFoundForDisconnection(String) // Added for disconnect errors
        case keyStoreInfoUnavailable(String) // Added for errors fetching KeyStore details
        case keyExchangeError(String) // Added for key exchange protocol errors
        case peerNotConnected(String) // Added for operations requiring a connected peer
        case invalidStateForAction(String) // Added for key exchange state machine errors
        case missingNonce // Added for key exchange errors


        var errorDescription: String? {
            switch self {
            case .sessionNotInitialized:
                "Peer-to-peer session not initialized"
            case .invalidStream:
                "Not a valid InnerCircle stream"
            case .browserNotInitialized:
                "Browser controller not initialized"
            // case .keyStoreNotInitialized: "KeyStore not initialized"
            case .profileNotAvailable:
                "User profile not available"
            case let .serializationFailed(context):
                "Failed to serialize message data: \(context)"
            case let .deserializationFailed(context):
                "Failed to deserialize message data: \(context)"
            case let .persistenceError(context):
                "Persistence error: \(context)"
            case .noConnectedPeers:
                "No connected peers available"
            // case let .keyRemovalFailed(reason): "Failed to remove used key: \(reason)"
            // case let .keyGenerationFailed(reason): "Failed to generate KeyStore keys: \(reason)"
            // case let .keySerializationError(reason): "Failed to serialize KeyStore public/private data: \(reason)"
            case let .arkavoClientError(reason):
                "ArkavoClient error: \(reason)"
            case let .policyCreationFailed(reason):
                "Failed to create policy: \(reason)"
            case let .peerNotFoundForDisconnection(reason):
                "Peer not found for disconnection: \(reason)"
            case let .keyStoreInfoUnavailable(reason):
                "Could not retrieve KeyStore information: \(reason)"
            case let .keyExchangeError(reason):
                "Key exchange protocol error: \(reason)"
            case let .peerNotConnected(reason):
                "Peer is not connected: \(reason)"
            case let .invalidStateForAction(reason):
                "Invalid state for the requested action: \(reason)"
            case .missingNonce:
                "Nonce required for key exchange operation is missing."
            }
        }
    }

    // --- Removed KeyStore Stub Properties ---
    // private var keyStore: KeyStore?
    // private let keyStoreCapacity = 8192
    // private var peerKeyStores: [String: KeyStore] = [:]
    // private var sentKeyStoreToPeers: Set<String> = []
    // @Published var usedKeyPairs: [String: Set<UUID>] = [:]
    // private let minKeyThresholdPercentage = 0.1
    // private let targetKeyPercentage = 0.8
    // private let keyRegenerationBatchSize = 2000
    // private var ephemeralPublicKeys: [Data: String] = [:]

    // Map MCPeerID to ProfileID for easier lookup when fetching/saving profiles
    // Make internal for access by PeerDiscoveryManager wrapper
    var peerIDToProfileID: [MCPeerID: String] = [:]

    // Access to PersistenceController
    private let persistenceController = PersistenceController.shared

    // MARK: - Initialization and Cleanup

    // Inject ArkavoClient
    init(arkavoClient: ArkavoClient) {
        self.arkavoClient = arkavoClient
        super.init()
        // ArkavoClient delegate is set by PeerDiscoveryManager
    }

    deinit {
        // Need to use Task for actor-isolated methods in deinit
        _ = Task { @MainActor [weak self] in
            self?.cancelAsyncTasks()
            self?.cleanup()
        }
    }

    private func cleanup() {
        stopSearchingForPeers()
        mcSession?.disconnect()
        invitationHandler = nil
        // sentKeyStoreToPeers.removeAll() // Removed
        // usedKeyPairs.removeAll() // Removed
        peerIDToProfileID.removeAll()
        // peerKeyStores.removeAll() // Removed
        connectedPeerProfiles.removeAll() // Clear profiles
        peerKeyExchangeStates.removeAll() // Clear key exchange states
        // Close and remove tracked streams
        activeInputStreams.keys.forEach { $0.close() }
        activeInputStreams.removeAll()
        // Reset status properties
        localKeyStoreInfo = nil
        isRegeneratingKeys = false
        // Disconnect ArkavoClient? Check ArkavoClient API for cleanup needs.
        // arkavoClient.disconnect() // Example
    }

    // --- Removed KeyStore Stub Management Methods ---
    // private func checkAndRegenerateKeys(forceRegeneration: Bool = false) async { ... }
    // private func persistLocalKeyStore() async throws { ... }
    // private func removeUsedKey(keyStore: KeyStore, keyID: UUID) async { ... }
    // private func markKeyAsUsed(keyID: UUID, peerIdentifier: String) { ... }

    // Cancel reference cycles to avoid memory leaks
    func cancelAsyncTasks() {
        // No async tasks to cancel yet, but this can be used in the future
    }

    // MARK: - MultipeerConnectivity Setup

    /// Sets up MultipeerConnectivity for the given stream
    /// - Parameter stream: The stream to use for peer discovery
    /// - Throws: P2PError if initialization fails
    func setupMultipeerConnectivity(for stream: Stream) async throws {
        // Cleanup previous session if any
        cleanup()

        guard stream.isInnerCircleStream else {
            connectionStatus = .failed(P2PError.invalidStream)
            throw P2PError.invalidStream
        }

        // Store the selected stream
        selectedStream = stream

        // Create a unique ID for this device using the profile name or a default
        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            connectionStatus = .failed(P2PError.profileNotAvailable)
            throw P2PError.profileNotAvailable
        }

        let displayName = profile.name // Use profile name for MCPeerID
        mcPeerID = MCPeerID(displayName: displayName)

        // --- Removed KeyStore Initialization ---
        // KeyStore management is now handled by ArkavoClient

        // Update local KeyStore info via ArkavoClient
        await refreshKeyStoreStatus()

        // Create the session with encryption
        mcSession = MCSession(peer: mcPeerID!, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self

        // Set up service type for InnerCircle
        let serviceType = "arkavo-circle"

        // Include profile info in discovery info - helps with authentication
        let discoveryInfo: [String: String] = [
            "profileID": profile.publicID.base58EncodedString, // Send publicID for identification
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": "\(Date().timeIntervalSince1970)",
            "name": profile.name, // Send name for display in browser
        ]

        // Create the advertiser with our own delegate implementation
        mcAdvertiser = MCNearbyServiceAdvertiser(
            peer: mcPeerID!,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        mcAdvertiser?.delegate = self

        // Set up the browser controller
        mcBrowser = MCBrowserViewController(serviceType: serviceType, session: mcSession!)
        mcBrowser?.delegate = self

        connectionStatus = .idle
        print("MultipeerConnectivity setup complete for stream: \(stream.profile.name)")

        // Inform ArkavoClient about the current profile (if needed)
        // await arkavoClient.setCurrentProfile(profile) // Example: Check ArkavoClient API
    }

    /// Starts the peer discovery process
    /// - Throws: P2PError if peer discovery cannot be started
    func startSearchingForPeers() throws {
        guard mcSession != nil else {
            connectionStatus = .failed(P2PError.sessionNotInitialized)
            throw P2PError.sessionNotInitialized
        }

        guard let selectedStream, selectedStream.isInnerCircleStream else {
            connectionStatus = .failed(P2PError.invalidStream)
            throw P2PError.invalidStream
        }

        // Start advertising our presence
        mcAdvertiser?.startAdvertisingPeer()
        isSearchingForPeers = true
        connectionStatus = .searching

        print("Started advertising presence for peer discovery")
        // Inform ArkavoClient that we are searching (if needed)
        // await arkavoClient.start() // Example: Check ArkavoClient API
    }

    /// Stops the peer discovery process
    func stopSearchingForPeers() {
        mcAdvertiser?.stopAdvertisingPeer()
        isSearchingForPeers = false

        // If we still have connected peers, keep status as connected
        // Otherwise revert to idle
        if connectedPeers.isEmpty {
            connectionStatus = .idle
        } else {
            connectionStatus = .connected
        }
        // Inform ArkavoClient that we stopped searching (if needed)
        // await arkavoClient.stop() // Example: Check ArkavoClient API
    }

    /// Finds a connected peer by their Profile ID.
    /// - Parameter profileID: The public profile ID (Data) of the peer to find.
    /// - Returns: The `MCPeerID` of the connected peer, or `nil` if not found.
    func findPeer(byProfileID profileID: Data) -> MCPeerID? {
        let profileIDString = profileID.base58EncodedString
        print("FindPeer: Searching for peer with Profile ID: \(profileIDString)")
        print("FindPeer: Current peerIDToProfileID map: \(peerIDToProfileID)")
        print("FindPeer: Current connectedPeers list: \(connectedPeers.map { "\($0.displayName) (\($0.hashValue))" })")

        // Find the MCPeerID in the map that corresponds to the profileIDString
        guard let foundPeerID = peerIDToProfileID.first(where: { $0.value == profileIDString })?.key else {
            print("FindPeer: Profile ID \(profileIDString) not found in peerIDToProfileID map.")
            return nil
        }

        print("FindPeer: Found MCPeerID \(foundPeerID.displayName) (Hash: \(foundPeerID.hashValue)) in map for Profile ID \(profileIDString).")

        // Verify that this MCPeerID is actually in the connectedPeers list
        if connectedPeers.contains(where: { $0.hashValue == foundPeerID.hashValue }) {
            print("FindPeer: MCPeerID \(foundPeerID.displayName) (Hash: \(foundPeerID.hashValue)) is present in connectedPeers list.")
            return foundPeerID
        } else {
            print("FindPeer: Warning - MCPeerID \(foundPeerID.displayName) (Hash: \(foundPeerID.hashValue)) found in map but NOT in connectedPeers list. State might be inconsistent.")
            // Clean up the inconsistent map entry?
            // peerIDToProfileID.removeValue(forKey: foundPeerID)
            return nil
        }
    }

    /// Disconnects a specific peer
    /// - Parameter peer: The MCPeerID of the peer to disconnect
    func disconnectPeer(_ peer: MCPeerID) {
        let profileID = peerIDToProfileID[peer] ?? "Unknown Profile ID"
        print("DisconnectPeer: Attempting to disconnect peer: \(peer.displayName) (Hash: \(peer.hashValue)), Profile ID: \(profileID)")
        print("DisconnectPeer: Current connectedPeers: \(connectedPeers.map { "\($0.displayName) (\($0.hashValue))" })")

        guard let session = mcSession else {
            print("DisconnectPeer Error: Cannot disconnect peer \(peer.displayName) - Session not active.")
            return
        }

        // Check if the *exact* MCPeerID instance is in the connectedPeers list
        let isPeerConnected = connectedPeers.contains { $0.hashValue == peer.hashValue }
        print("DisconnectPeer: Is peer \(peer.displayName) (Hash: \(peer.hashValue)) contained in connectedPeers list? \(isPeerConnected)")

        guard isPeerConnected else {
            print("DisconnectPeer Warning: Peer \(peer.displayName) (Hash: \(peer.hashValue)) not found in connectedPeers list. Disconnection skipped. Profile ID: \(profileID)")
            // Even if not found, try to clean up any lingering map/profile data just in case
            if peerIDToProfileID[peer] != nil {
                print("DisconnectPeer Info: Removing lingering map entry for \(peer.displayName)")
                peerIDToProfileID.removeValue(forKey: peer)
            }
            if connectedPeerProfiles[peer] != nil {
                print("DisconnectPeer Info: Removing lingering profile cache for \(peer.displayName)")
                connectedPeerProfiles.removeValue(forKey: peer)
            }
            // Remove from connection times if present
            peerConnectionTimes.removeValue(forKey: peer)
            // Remove from key exchange state
            peerKeyExchangeStates.removeValue(forKey: peer)
            return
        }

        print("DisconnectPeer: Proceeding with disconnection for peer: \(peer.displayName)")
        // Cancel any connections with this peer using the MCSession method
        session.cancelConnectPeer(peer)
        print("DisconnectPeer: Called session.cancelConnectPeer for \(peer.displayName)")

        // --- Immediate Cleanup ---
        // It's generally better to let the MCSessionDelegate handle the state change to .notConnected
        // for removing the peer from lists and maps, as `cancelConnectPeer` is asynchronous.
        // However, performing *some* cleanup immediately can prevent race conditions if the
        // delegate callback is delayed or doesn't fire for some reason (e.g., during app termination).
        // We will primarily rely on the delegate, but log that we initiated the disconnect here.

        // Optional: Immediately remove from connection times to prevent UI issues
        // peerConnectionTimes.removeValue(forKey: peer)
        // Optional: Immediately remove key exchange state
        // peerKeyExchangeStates.removeValue(forKey: peer)


        // The primary removal from connectedPeers, peerIDToProfileID, connectedPeerProfiles,
        // and stream closing should happen in the session(_:peer:didChange:to:) delegate method
        // when the state becomes .notConnected.

        print("DisconnectPeer: Disconnection initiated for \(peer.displayName). Waiting for delegate callback for final cleanup.")

        // Refresh KeyStore status (might be too early, consider moving to delegate .notConnected state)
        // Task {
        //     await refreshKeyStoreStatus()
        // }
    }

    /// Returns the browser view controller for manual peer selection
    /// - Returns: MCBrowserViewController instance or nil if not available
    func getBrowser() -> MCBrowserViewController? {
        mcBrowser
    }

    // MARK: - Data Transmission (using ArkavoClient and P2P Messages)

    /// Sends raw data via MCSession (used internally for P2P messages and by ArkavoClient)
    /// - Parameters:
    ///   - data: The data to send
    ///   - peers: Specific peers to send to
    /// - Throws: P2PError or session errors if sending fails
    private func sendRawData(_ data: Data, toPeers peers: [MCPeerID]) throws {
        guard let mcSession else {
            throw P2PError.sessionNotInitialized
        }
        guard !peers.isEmpty else {
            // This shouldn't happen if called correctly, but good to check
            print("Warning: sendRawData called with empty peer list.")
            return
        }

        // Ensure all target peers are currently connected
        let connectedPeerHashes = Set(mcSession.connectedPeers.map { $0.hashValue })
        let targetPeersToSend = peers.filter { connectedPeerHashes.contains($0.hashValue) }

        guard !targetPeersToSend.isEmpty else {
            let targetNames = peers.map { $0.displayName }.joined(separator: ", ")
            print("Error: None of the target peers (\(targetNames)) are currently connected.")
            throw P2PError.peerNotConnected("Target peers [\(targetNames)] not found in connected list.")
        }

        if targetPeersToSend.count < peers.count {
            let missingPeers = peers.filter { !connectedPeerHashes.contains($0.hashValue) }
            print("Warning: Not sending data to disconnected peers: \(missingPeers.map { $0.displayName })")
        }

        print("Sending \(data.count) bytes raw data to \(targetPeersToSend.count) peers: \(targetPeersToSend.map { $0.displayName })")
        try mcSession.send(data, toPeers: targetPeersToSend, with: .reliable)
    }

    /// Encodes and sends a P2P message structure to specific peers.
    /// - Parameters:
    ///   - messageType: The type of the message.
    ///   - payload: The `Codable` payload object for the message.
    ///   - peers: The list of `MCPeerID`s to send the message to.
    /// - Throws: `P2PError` if encoding or sending fails.
    private func sendP2PMessage<T: Codable>(type: P2PMessageType, payload: T, toPeers peers: [MCPeerID]) async throws {
        print("Encoding P2P message of type \(type) for peers: \(peers.map { $0.displayName })")
        do {
            let dataToSend = try P2PMessage.encode(type: type, payload: payload)
            try sendRawData(dataToSend, toPeers: peers)
            print("Successfully sent P2P message of type \(type)")
        } catch let error as P2PError {
            print("❌ P2PError sending message type \(type): \(error)")
            throw error // Re-throw P2PError
        } catch {
            print("❌ Error encoding or sending P2P message type \(type): \(error)")
            throw P2PError.serializationFailed("Encoding/Sending \(type): \(error.localizedDescription)")
        }
    }


    /// Sends data securely using ArkavoClient
    /// - Parameters:
    ///   - data: The raw data to encrypt and send
    ///   - policy: The TDF policy to apply (as a JSON string)
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    ///   - stream: The stream context for the data
    /// - Throws: Errors if encryption or sending fails
    func sendSecureData(_ data: Data, policy: String, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
        guard stream.isInnerCircleStream else {
            throw P2PError.invalidStream
        }
        guard let mcSession, !mcSession.connectedPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }

        let targetPeers = peers ?? mcSession.connectedPeers
        guard !targetPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }

        // Map MCPeerIDs to Profile IDs if sending to specific peers
        var targetProfileIDs: [Data]? = nil
        if let specificPeers = peers {
            targetProfileIDs = specificPeers.compactMap { peerID in
                if let profileIDString = peerIDToProfileID[peerID] {
                    return Data(base58Encoded: profileIDString)
                }
                print("Warning: No profile ID found for target peer \(peerID.displayName)")
                return nil
            }
            guard let unwrappedTargetProfileIDs = targetProfileIDs, !unwrappedTargetProfileIDs.isEmpty else {
                print("Error: Could not map any target MCPeerIDs to Profile IDs.")
                throw P2PError.profileNotAvailable // Or a more specific error
            }
        }

        print("Sending secure data (\(data.count) bytes) with policy to \(targetPeers.count) peers in stream \(stream.profile.name)")

        guard let policyData = policy.data(using: .utf8) else {
            throw P2PError.policyCreationFailed("Failed to encode policy JSON string to Data")
        }

        do {
            // Ask ArkavoClient to encrypt the data
            // ArkavoClient might need target profile IDs if not sending to all
            // Check ArkavoClient API for exact method signature
            // Example: let encryptedData = try await arkavoClient.encryptP2PPayload(payload: data, policyData: policyData, recipientProfileIDs: targetProfileIDs)
            let encryptedData = try await arkavoClient.encryptAndSendPayload(payload: data, policyData: policyData) // Assuming this handles P2P via delegate/internal logic

            // Send the encrypted data via MCSession using sendRawData helper
            try sendRawData(encryptedData, toPeers: targetPeers)
            print("Secure data sent successfully via MCSession.")

        } catch {
            print("❌ Error sending secure data: \(error)")
            // Re-throw or wrap the error
            throw P2PError.arkavoClientError("Failed during secure data sending: \(error.localizedDescription)")
        }
    }

    /// Sends a secure text message using ArkavoClient
    func sendSecureTextMessage(_ message: String, in stream: Stream) async throws {
        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }
        let streamID = stream.publicID

        let messageData = Data(message.utf8)

        // Create a simple policy for the stream using only dataAttributes.
        // This grants access based on having an attribute matching the stream ID.
        // Assumes recipients get this attribute via KAS or other means.
        let policyJson = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [ { "attribute": "stream:\(streamID.base58EncodedString)" } ],
            "dissem": []
          }
        }
        """
        // Note: ArkavoClient's encryptAndSendPayload likely expects the policyData
        // to be the *body* of the policy, not the full structure including "uuid".
        // However, the current implementation in ChatViewModel passes the full JSON.
        // We'll keep it consistent for now, but this might need adjustment based on
        // how ArkavoClient actually processes the policyData parameter.
        // If only the body is needed, extract the "body" part of the JSON.

        print("Using policy for secure text message: \(policyJson)")

        // Use sendSecureData to encrypt and send
        try await sendSecureData(messageData, policy: policyJson, in: stream)

        // Optionally, save the *unencrypted* message locally as a Thought?
        // Or does ArkavoClient handle local persistence after sending? Check API.
        // If we save locally, use the original messageData, not the encrypted one.
        Task {
            do {
                let thought = try await storeP2PMessageAsThought(
                    content: message, // Original content
                    sender: profile.name,
                    senderProfileID: profile.publicID.base58EncodedString,
                    timestamp: Date(),
                    stream: stream,
                    nanoData: nil // Indicate it's not pre-encrypted
                )
                print("✅ Local text message stored successfully as Thought with ID: \(thought.id)")
                await MainActor.run {
                    NotificationCenter.default.post(name: .chatMessagesUpdated, object: nil)
                }
            } catch {
                print("❌ Failed to store local P2P message as Thought: \(error)")
            }
        }
    }

    // --- Removed Profile/KeyStore Exchange Methods ---
    // func initiateKeyStoreExchange(with peer: MCPeerID) { ... }
    // private func sendProfileAndPublicKeyStore(to peer: MCPeerID) async throws { ... }
    // These responsibilities likely move to ArkavoClient or are handled differently.

    // --- Removed sendTextMessage (replaced by sendSecureTextMessage) ---
    // func sendTextMessage(_ message: String, in stream: Stream) throws { ... }

    // MARK: - Message Handling (P2P and ArkavoClient)

    /// Handles general incoming data (routes P2P messages, passes others to ArkavoClient)
    /// - Parameters:
    ///   - data: The received message data
    ///   - peer: The peer that sent the message
    private func handleIncomingData(_ data: Data, from peer: MCPeerID) {
        print("Received \(data.count) bytes from \(peer.displayName). Attempting to decode as P2PMessage.")

        // Try decoding as a P2PMessage first
        do {
            let p2pMessage = try P2PMessage.decode(from: data)
            print("Successfully decoded P2PMessage of type: \(p2pMessage.messageType)")
            // Route based on P2P message type
            switch p2pMessage.messageType {
            case .keyRegenerationRequest:
                handleKeyRegenerationRequest(from: peer, data: p2pMessage.payload)
            case .keyRegenerationOffer:
                handleKeyRegenerationOffer(from: peer, data: p2pMessage.payload)
            case .keyRegenerationAcknowledgement:
                handleKeyRegenerationAcknowledgement(from: peer, data: p2pMessage.payload)
            case .keyRegenerationCommit:
                handleKeyRegenerationCommit(from: peer, data: p2pMessage.payload)
                // Add cases for other P2P message types here
            }
        } catch {
            // If decoding as P2PMessage fails, assume it's encrypted data for ArkavoClient
            print("Data from \(peer.displayName) is not a standard P2PMessage (Error: \(error.localizedDescription)). Passing to ArkavoClient for potential decryption.")
            // ArkavoClient should handle decryption and further processing via its delegate methods
            // Example: arkavoClient.processReceivedP2PData(data, from: peer)
            // Assuming ArkavoClient handles this internally or via its own delegate calls
            // Post a notification or directly call ArkavoClient if needed
            // NotificationCenter.default.post(name: .nonJsonDataReceived, object: nil, userInfo: ["data": data, "peer": peer])
            // OR
            // Task { await arkavoClient.processReceivedP2PData(data, fromPeerID: peer) } // Check ArkavoClient API
        }
    }


    // --- Removed JSON Message Handling ---
    // handleIncomingMessage, handleJSONMessage, handleProfileWithPublicKeyStoreMessage,
    // handleProfileWithPublicKeyStoreAcknowledgement, handleTextMessage, handleMessageAcknowledgement
    // ArkavoClient is now responsible for parsing and interpreting the data.

    /// Store a P2P message as a Thought for persistence
    /// - Returns: The created Thought object
    private func storeP2PMessageAsThought(content: String, sender _: String, senderProfileID: String, timestamp: Date, stream: Stream, nanoData: Data?) async throws -> Thought {
        guard let senderPublicID = Data(base58Encoded: senderProfileID) else {
            print("Error: Could not decode sender profile ID \(senderProfileID)")
            throw P2PError.deserializationFailed("Invalid sender profile ID")
        }

        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: senderPublicID,
            streamPublicID: stream.publicID,
            mediaType: .say, // Use .say for P2P text messages
            createdAt: timestamp,
            contributors: []
        )

        // Use provided nanoData if available (e.g., for locally sent encrypted messages if needed)
        // Otherwise, convert the String content to Data for the 'nano' property (for received decrypted messages)
        let dataToStore = nanoData ?? Data(content.utf8)

        let thought = Thought(
            nano: dataToStore, // Store relevant data (encrypted or decrypted)
            metadata: thoughtMetadata
        )

        // Ensure the stream is associated before saving
        thought.stream = stream

        _ = try await PersistenceController.shared.saveThought(thought)

        // Use addThought instead of addToThoughts (assuming Stream model has this)
        // stream.addThought(thought) // This might cause issues if stream is not the managed instance
        // Fetch the managed stream instance to be safe
        if let managedStream = try await persistenceController.fetchStream(withPublicID: stream.publicID) {
            // Check if thought is already associated to prevent duplicates if saveThought handles it
            if !(managedStream.thoughts.contains { $0.persistentModelID == thought.persistentModelID }) {
                managedStream.addThought(thought) // Assuming addThought exists and handles relationships
            }
        } else {
            print("Warning: Could not find managed stream instance to associate thought.")
        }

        try await PersistenceController.shared.saveChanges()
        print("✅ P2P message stored as Thought for stream: \(stream.publicID.base58EncodedString)")

        return thought
    }

    // MARK: - KeyStore Status Management (using ArkavoClient)

    /// Updates the published properties related to the *local* KeyStore status via ArkavoClient.
    func refreshKeyStoreStatus() async {
        print("Refreshing local KeyStore status via ArkavoClient...")
        do {
            // Ask ArkavoClient for the detailed status
            // *** PLACEHOLDER: Replace with actual ArkavoClient API call ***
            // This assumes ArkavoClient has a method like `getLocalKeyStoreDetails()`
            // that returns valid, expired, capacity, and regeneration status.
            let (validCount, expiredCount, capacity, isRegen) = try await arkavoClient.getLocalKeyStoreDetails() // Example API call

            // Update published properties with detailed info
            self.localKeyStoreInfo = LocalKeyStoreInfo(
                validKeyCount: validCount,
                expiredKeyCount: expiredCount,
                capacity: capacity
            )
            self.isRegeneratingKeys = isRegen
            print("✅ Refreshed KeyStore Status: Valid=\(validCount), Expired=\(expiredCount), Capacity=\(capacity), Regenerating=\(isRegen)")

        } catch {
            print("❌ Failed to refresh KeyStore status from ArkavoClient: \(error)")
            // Optionally set status to nil or keep the old value
            // self.localKeyStoreInfo = nil
            // self.isRegeneratingKeys = false
            // Consider propagating the error if needed
            // self.connectionStatus = .failed(P2PError.keyStoreInfoUnavailable(error.localizedDescription))
        }

        // Also refresh connected peer profiles from persistence
        await refreshConnectedPeerProfiles()
    }

    /// Fetches profiles for currently connected peers from persistence.
    private func refreshConnectedPeerProfiles() async {
        print("Refreshing connected peer profiles from persistence...")
        var updatedProfiles: [MCPeerID: Profile] = [:]
        let currentPeers = connectedPeers // Capture current list

        for peer in currentPeers {
            // Try getting profile ID from ArkavoClient first, then fallback to local map
            var profileIDString: String? = nil
            // Example: profileIDString = await arkavoClient.getProfileID(for: peer)
            if profileIDString == nil {
                profileIDString = peerIDToProfileID[peer]
            }

            if let idString = profileIDString, let profileIDData = Data(base58Encoded: idString) {
                do {
                    if let profile = try await persistenceController.fetchProfile(withPublicID: profileIDData) {
                        updatedProfiles[peer] = profile
                        print("Fetched profile for \(peer.displayName) (\(idString))")
                        // Ensure local map is updated
                        if peerIDToProfileID[peer] == nil {
                            peerIDToProfileID[peer] = idString
                        }
                    } else {
                        print("Profile for \(peer.displayName) (\(idString)) not found locally yet.")
                    }
                } catch {
                    print("❌ Error fetching profile \(idString) for peer \(peer.displayName): \(error)")
                }
            } else {
                print("No profile ID mapped or available for peer \(peer.displayName), cannot fetch profile.")
            }
        }

        connectedPeerProfiles = updatedProfiles
        print("Finished refreshing connected peer profiles. Found \(updatedProfiles.count) profiles locally.")
    }

    /// Manually triggers regeneration of local KeyStore keys via ArkavoClient.
    func regenerateLocalKeys() async {
        print("Manual regeneration of local keys requested via ArkavoClient.")
        isRegeneratingKeys = true // Optimistically set regenerating status
        localKeyStoreInfo = nil // Clear info while regenerating
        do {
            // *** PLACEHOLDER: Replace with actual ArkavoClient API call ***
            try await arkavoClient.regenerateLocalKeys()
            print("✅ Triggered key regeneration via ArkavoClient.")
            // Refresh status after triggering (ArkavoClient might also push an update via delegate)
            await refreshKeyStoreStatus()
        } catch {
            print("❌ Failed to trigger key regeneration via ArkavoClient: \(error)")
            isRegeneratingKeys = false // Revert status on failure
            // Optionally show error to user
            // Refresh status even on failure to get the current state
            await refreshKeyStoreStatus()
        }
    }

    // MARK: - KeyStore Rewrap Support (using ArkavoClient)

    /// Handle a rewrap request using ArkavoClient
    /// - Parameters:
    ///   - publicKey: The ephemeral public key from the request
    ///   - encryptedSessionKey: The encrypted session key that needs rewrapping
    ///   - senderProfileID: Optional profile ID of the sender (used for logging/tracking)
    /// - Returns: Rewrapped key data or nil if no matching key found
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data, senderProfileID: String? = nil) async throws -> Data? {
        let peerIdentifier = senderProfileID ?? "unknown-peer"
        print("Handling rewrap request from \(peerIdentifier) via ArkavoClient...")
        print("Ephemeral Public Key: \(publicKey.count) bytes")
        print("Encrypted Session Key: \(encryptedSessionKey.count) bytes")

        var rewrappedKey: Data? = nil
        do {
            // *** PLACEHOLDER: Replace with actual ArkavoClient API call ***
            // Example:
            // rewrappedKey = try await arkavoClient.rewrapSessionKey(
            //     publicKey: publicKey,
            //     encryptedSessionKey: encryptedSessionKey,
            //     senderProfileID: senderProfileID
            // )
            print("Placeholder: Calling ArkavoClient rewrap method (TBD).")
            // Simulate failure for now
            rewrappedKey = nil
            // Simulate success for testing:
            // rewrappedKey = Data("simulated-rewrapped-key".utf8)

            await refreshKeyStoreStatus() // Refresh status after rewrap attempt

            if rewrappedKey != nil {
                print("ArkavoClient successfully rewrapped the session key for \(peerIdentifier).")
            } else {
                print("No matching key found or rewrap failed for request from \(peerIdentifier).")
            }
            return rewrappedKey
        }
    }

    // MARK: - Secure Key Regeneration Protocol

    /// Generates a cryptographically secure nonce.
    private func generateNonce(size: Int = 32) -> Data {
        var keyData = Data(count: size)
        let result = keyData.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!)
        }
        if result == errSecSuccess {
            return keyData
        } else {
            // Fallback for safety, though SecRandomCopyBytes should generally succeed
            print("Warning: SecRandomCopyBytes failed. Using fallback nonce generation.")
            return Data((0..<size).map { _ in UInt8.random(in: .min ... .max) })
        }
    }

    /// Updates the key exchange state for a peer.
    private func updatePeerExchangeState(for peer: MCPeerID, newState: KeyExchangeState) {
        var info = peerKeyExchangeStates[peer] ?? KeyExchangeTrackingInfo()
        info.state = newState
        info.lastActivity = Date()
        peerKeyExchangeStates[peer] = info
        print("KeyExchange: Updated state for \(peer.displayName) to \(newState)")
    }

    /// Initiates the secure key regeneration process with a specific peer.
    /// - Parameter peer: The `MCPeerID` of the peer to regenerate keys with.
    /// - Throws: `P2PError` if the process cannot be initiated.
    func initiateKeyRegeneration(with peer: MCPeerID) async throws {
        print("KeyExchange: Initiating key regeneration with \(peer.displayName)")

        // 1. Check prerequisites
        guard let session = mcSession, session.connectedPeers.contains(peer) else {
            throw P2PError.peerNotConnected("Peer \(peer.displayName) is not connected.")
        }
        guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }

        // 2. Check current state (allow initiation only from idle or failed)
        let currentState = peerKeyExchangeStates[peer]?.state ?? .idle
        guard currentState == .idle || (currentState.nonce == nil) else { // Check if failed or idle
             throw P2PError.invalidStateForAction("Cannot initiate key exchange with \(peer.displayName), current state is \(currentState)")
        }

        // 3. Generate nonce and create request message
        let nonce = generateNonce()
        let request = KeyRegenerationRequest(
            requestID: UUID(),
            initiatorProfileID: myProfile.publicID.base58EncodedString,
            timestamp: Date()
        )

        // 4. Update local state *before* sending
        updatePeerExchangeState(for: peer, newState: .requestSent(nonce: nonce))

        // 5. Send the request message
        do {
            try await sendP2PMessage(type: .keyRegenerationRequest, payload: request, toPeers: [peer])
            print("KeyExchange: Sent KeyRegenerationRequest to \(peer.displayName) (ReqID: \(request.requestID))")
        } catch {
            // Rollback state on send failure
            updatePeerExchangeState(for: peer, newState: .failed("Failed to send request: \(error.localizedDescription)"))
            throw error // Re-throw the error
        }
    }

    /// Handles an incoming KeyRegenerationRequest message.
    private func handleKeyRegenerationRequest(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received KeyRegenerationRequest from \(peer.displayName)")
        Task {
            do {
                // 1. Decode the request
                let request: KeyRegenerationRequest = try P2PMessage(messageType: .keyRegenerationRequest, payload: data).decodePayload(KeyRegenerationRequest.self)
                print("KeyExchange: Decoded request (ReqID: \(request.requestID)) from \(request.initiatorProfileID)")

                // 2. Check prerequisites
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }
                // Optional: Verify initiatorProfileID matches the mapped ID for the peer? Maybe not necessary if map is trusted.

                // 3. Check current state (allow processing only from idle or failed)
                let currentState = peerKeyExchangeStates[peer]?.state ?? .idle
                guard currentState == .idle || (currentState.nonce == nil) else {
                     print("KeyExchange: Ignoring request from \(peer.displayName), already in state \(currentState)")
                     // Maybe send a busy/error response? For now, just ignore.
                     return
                }

                // 4. Generate nonce and create offer message
                let nonce = generateNonce()
                let offer = KeyRegenerationOffer(
                    requestID: request.requestID,
                    responderProfileID: myProfile.publicID.base58EncodedString,
                    nonce: nonce, // Our nonce
                    timestamp: Date()
                )

                // 5. Update local state *before* sending
                updatePeerExchangeState(for: peer, newState: .requestReceived(nonce: nonce)) // Store *our* nonce

                // 6. Send the offer message
                try await sendP2PMessage(type: .keyRegenerationOffer, payload: offer, toPeers: [peer])
                print("KeyExchange: Sent KeyRegenerationOffer to \(peer.displayName) (ReqID: \(request.requestID))")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .offerSent(nonce: nonce))

            } catch {
                print("❌ KeyExchange: Error handling KeyRegenerationRequest from \(peer.displayName): \(error)")
                updatePeerExchangeState(for: peer, newState: .failed("Error processing request: \(error.localizedDescription)"))
            }
        }
    }

    /// Handles an incoming KeyRegenerationOffer message.
    private func handleKeyRegenerationOffer(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received KeyRegenerationOffer from \(peer.displayName)")
        Task {
            do {
                // 1. Decode the offer
                let offer: KeyRegenerationOffer = try P2PMessage(messageType: .keyRegenerationOffer, payload: data).decodePayload(KeyRegenerationOffer.self)
                print("KeyExchange: Decoded offer (ReqID: \(offer.requestID)) from \(offer.responderProfileID)")

                // 2. Check prerequisites
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case .requestSent(let initiatorNonce) = currentStateInfo.state else {
                    print("KeyExchange: Ignoring offer from \(peer.displayName), not in RequestSent state.")
                    // Could be a duplicate or out-of-order message.
                    return
                }

                // 3. Create acknowledgement message (using our original nonce)
                let ack = KeyRegenerationAcknowledgement(
                    requestID: offer.requestID,
                    initiatorProfileID: myProfile.publicID.base58EncodedString,
                    nonce: initiatorNonce, // Our original nonce
                    timestamp: Date()
                )

                // 4. Update local state *before* sending
                updatePeerExchangeState(for: peer, newState: .offerReceived(nonce: initiatorNonce)) // Still using our nonce

                // 5. Send the acknowledgement message
                try await sendP2PMessage(type: .keyRegenerationAcknowledgement, payload: ack, toPeers: [peer])
                print("KeyExchange: Sent KeyRegenerationAcknowledgement to \(peer.displayName) (ReqID: \(offer.requestID))")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .ackSent(nonce: initiatorNonce))

                // --- Initiator's Key Generation Trigger ---
                // At this point, the initiator (us) has both nonces:
                // - Our nonce: initiatorNonce
                // - Peer's nonce: offer.nonce
                // We can now trigger the key generation.
                guard let peerProfileIDData = Data(base58Encoded: offer.responderProfileID) else {
                     throw P2PError.keyExchangeError("Invalid peer profile ID in offer: \(offer.responderProfileID)")
                }
                print("KeyExchange (Initiator): Triggering shared key generation with peer \(offer.responderProfileID)")
                // *** PLACEHOLDER: Call ArkavoClient to generate keys ***
                try await arkavoClient.generateSharedKeys(
                    initiatorNonce: initiatorNonce,
                    responderNonce: offer.nonce,
                    peerProfileID: peerProfileIDData
                )
                print("KeyExchange (Initiator): ArkavoClient key generation triggered successfully.")
                // Note: We don't transition to 'completed' yet, we wait for the Commit message
                // from the responder as final confirmation.

            } catch {
                print("❌ KeyExchange: Error handling KeyRegenerationOffer from \(peer.displayName): \(error)")
                updatePeerExchangeState(for: peer, newState: .failed("Error processing offer: \(error.localizedDescription)"))
            }
        }
    }

    /// Handles an incoming KeyRegenerationAcknowledgement message.
    private func handleKeyRegenerationAcknowledgement(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received KeyRegenerationAcknowledgement from \(peer.displayName)")
        Task {
            do {
                // 1. Decode the acknowledgement
                let ack: KeyRegenerationAcknowledgement = try P2PMessage(messageType: .keyRegenerationAcknowledgement, payload: data).decodePayload(KeyRegenerationAcknowledgement.self)
                print("KeyExchange: Decoded acknowledgement (ReqID: \(ack.requestID)) from \(ack.initiatorProfileID)")

                // 2. Check prerequisites
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PError.profileNotAvailable
                }
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case .offerSent(let responderNonce) = currentStateInfo.state else {
                    print("KeyExchange: Ignoring acknowledgement from \(peer.displayName), not in OfferSent state.")
                    return
                }
                // Optional: Verify ack.requestID matches expectation?

                // 3. Create commit message
                let commit = KeyRegenerationCommit(
                    requestID: ack.requestID,
                    responderProfileID: myProfile.publicID.base58EncodedString,
                    timestamp: Date()
                )

                // 4. Update local state *before* sending
                updatePeerExchangeState(for: peer, newState: .ackReceived(nonce: responderNonce)) // Still using our (responder's) nonce

                // 5. Send the commit message
                try await sendP2PMessage(type: .keyRegenerationCommit, payload: commit, toPeers: [peer])
                print("KeyExchange: Sent KeyRegenerationCommit to \(peer.displayName) (ReqID: \(ack.requestID))")
                // Transition state after successful send
                updatePeerExchangeState(for: peer, newState: .commitSent(nonce: responderNonce)) // Final state for responder

                // --- Responder's Key Generation Trigger ---
                // At this point, the responder (us) has both nonces:
                // - Our nonce: responderNonce
                // - Peer's nonce: ack.nonce
                // We can now trigger the key generation.
                guard let peerProfileIDData = Data(base58Encoded: ack.initiatorProfileID) else {
                     throw P2PError.keyExchangeError("Invalid peer profile ID in acknowledgement: \(ack.initiatorProfileID)")
                }
                print("KeyExchange (Responder): Triggering shared key generation with peer \(ack.initiatorProfileID)")
                // *** PLACEHOLDER: Call ArkavoClient to generate keys ***
                try await arkavoClient.generateSharedKeys(
                    initiatorNonce: ack.nonce, // Peer's nonce is initiator's
                    responderNonce: responderNonce, // Our nonce is responder's
                    peerProfileID: peerProfileIDData
                )
                print("KeyExchange (Responder): ArkavoClient key generation triggered successfully.")
                // CommitSent is the final state for the responder.

            } catch {
                print("❌ KeyExchange: Error handling KeyRegenerationAcknowledgement from \(peer.displayName): \(error)")
                updatePeerExchangeState(for: peer, newState: .failed("Error processing acknowledgement: \(error.localizedDescription)"))
            }
        }
    }

    /// Handles an incoming KeyRegenerationCommit message.
    private func handleKeyRegenerationCommit(from peer: MCPeerID, data: Data) {
        print("KeyExchange: Received KeyRegenerationCommit from \(peer.displayName)")
        Task {
            do {
                // 1. Decode the commit message
                let commit: KeyRegenerationCommit = try P2PMessage(messageType: .keyRegenerationCommit, payload: data).decodePayload(KeyRegenerationCommit.self)
                print("KeyExchange: Decoded commit (ReqID: \(commit.requestID)) from \(commit.responderProfileID)")

                // 2. Check prerequisites
                guard let currentStateInfo = peerKeyExchangeStates[peer],
                      case .ackSent(let initiatorNonce) = currentStateInfo.state else {
                    print("KeyExchange: Ignoring commit from \(peer.displayName), not in AckSent state.")
                    return
                }
                // Optional: Verify commit.requestID matches expectation?

                // 3. Update local state to completed
                print("KeyExchange: Protocol completed successfully with \(peer.displayName) (ReqID: \(commit.requestID))")
                updatePeerExchangeState(for: peer, newState: .completed(nonce: initiatorNonce)) // Final state for initiator

                // Key generation was already triggered by the initiator when handling the Offer.
                // This commit message serves as the final confirmation from the responder.

                // Optional: Refresh local key store status now that keys should be generated/stored
                await refreshKeyStoreStatus()

            } catch {
                print("❌ KeyExchange: Error handling KeyRegenerationCommit from \(peer.displayName): \(error)")
                updatePeerExchangeState(for: peer, newState: .failed("Error processing commit: \(error.localizedDescription)"))
            }
        }
    }


    // MARK: - ArkavoClientDelegate Methods

    // UPDATED Delegate Method - Triggers full refresh
    nonisolated func arkavoClientDidUpdateKeyStatus(_: ArkavoClient, keyCount: Int, capacity: Int, isRegenerating: Bool) {
        Task { @MainActor in
            // This delegate provides potentially incomplete info (missing expired count).
            // Trigger a full refresh to get accurate LocalKeyStoreInfo.
            print("Delegate: ArkavoClient Key Status Update Received (Valid: \(keyCount), Capacity: \(capacity), Regen: \(isRegenerating)). Triggering full status refresh.")
            // Optionally update isRegenerating immediately for responsiveness
            self.isRegeneratingKeys = isRegenerating
            // Trigger the full refresh
            await self.refreshKeyStoreStatus()
        }
    }

    nonisolated func arkavoClientDidReceiveMessage(_: ArkavoClient, message: String, fromProfileID: Data, streamID: Data?) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Received Secure Message from \(fromProfileID.base58EncodedString)")
            guard let currentStream = self.selectedStream, currentStream.publicID == streamID else {
                print("Warning: Received secure message for stream \(streamID?.base58EncodedString ?? "nil") but current stream is \(self.selectedStream?.publicID.base58EncodedString ?? "nil"). Ignoring.")
                return
            }

            // Find sender profile locally
            var senderName = "Unknown Peer"
            do {
                if let profile = try await self.persistenceController.fetchProfile(withPublicID: fromProfileID) {
                    senderName = profile.name
                }
            } catch {
                print("Warning: Could not fetch sender profile locally for ID \(fromProfileID.base58EncodedString): \(error)")
            }

            // Store as Thought
            do {
                let thought = try await self.storeP2PMessageAsThought(
                    content: message,
                    sender: senderName,
                    senderProfileID: fromProfileID.base58EncodedString,
                    timestamp: Date(), // Use current time for received message
                    stream: currentStream,
                    nanoData: nil // Decrypted message content
                )
                print("✅ Stored secure message from \(senderName) as Thought ID: \(thought.id)")

                // Post notification for UI update
                NotificationCenter.default.post(
                    name: .p2pMessageReceived,
                    object: nil,
                    userInfo: [
                        "streamID": currentStream.publicID,
                        "thoughtID": thought.id,
                        "message": message,
                        "sender": senderName,
                        "timestamp": thought.metadata.createdAt, // Use timestamp from Thought
                        "senderProfileID": fromProfileID.base58EncodedString,
                    ]
                )
                NotificationCenter.default.post(name: .chatMessagesUpdated, object: nil)

            } catch {
                print("❌ Failed to store received secure P2P message as Thought: \(error)")
            }
        }
    }

    nonisolated func arkavoClientDidUpdatePeerProfile(_: ArkavoClient, profile: Profile, publicKeyStoreData: Data?) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Updated Peer Profile: \(profile.name) (\(profile.publicID.base58EncodedString))")
            do {
                // Save the updated profile and potentially public KeyStore data
                try await self.persistenceController.savePeerProfile(profile, keyStorePublicData: publicKeyStoreData)
                print("Saved updated peer profile \(profile.name) from ArkavoClient.")

                // Refresh the connected peer profiles list
                await self.refreshConnectedPeerProfiles()

            } catch {
                print("❌ Failed to save updated peer profile from ArkavoClient: \(error)")
            }
        }
    }

    nonisolated func arkavoClientEncounteredError(_: ArkavoClient, error: Error) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Encountered Error: \(error.localizedDescription)")
            // Update connection status or display error to user
            self.connectionStatus = .failed(P2PError.arkavoClientError(error.localizedDescription))
        }
    }

    // Add other ArkavoClientDelegate methods as needed based on its definition
    // e.g., func arkavoClientDidUpdateConnection(...)
    // Implement required methods if ArkavoClientDelegate protocol demands them
    nonisolated func clientDidChangeState(_: ArkavoClient, state: ArkavoClientState) {
        // Example implementation (can be expanded)
        Task { @MainActor in
            print("Delegate: ArkavoClient State Changed: \(state)")
            // Could update connectionStatus based on ArkavoClient state if needed
        }
    }

    nonisolated func clientDidReceiveMessage(_: ArkavoClient, message: Data) {
        // This delegate method receives *raw* data from the WebSocket/NATS
        // It's distinct from the P2P message delegate method above.
        // P2PGroupViewModel might not need to handle these directly if ChatViewModel does.
        Task { @MainActor in
            print("Delegate: ArkavoClient Received Raw Message Data (\(message.count) bytes) - Likely handled elsewhere (e.g., ChatViewModel).")
            // Potentially pass to internal ArkavoClient handler if needed for P2P context
            // self.handleIncomingData(message, from: <#Determine Peer somehow if possible#>)
        }
    }

    nonisolated func clientDidReceiveError(_: ArkavoClient, error: Error) {
        // This seems redundant with arkavoClientEncounteredError, but implement if required.
        Task { @MainActor in
            print("Delegate: ArkavoClient Received Error: \(error.localizedDescription)")
            // Update connection status or display error to user
            self.connectionStatus = .failed(P2PError.arkavoClientError(error.localizedDescription))
        }
    }
}

// MARK: - MCSessionDelegate

extension P2PGroupViewModel: MCSessionDelegate {
    nonisolated func session(_: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // Convert state to string here instead of calling the actor-isolated method
        let stateStr = { () -> String in
            switch state {
            case .notConnected: return "Not Connected"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            @unknown default: return "Unknown"
            }
        }()

        print("MCSessionDelegate: Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) changed state to: \(stateStr)")

        Task { @MainActor in
            switch state {
            case .connected:
                self.invitationHandler = nil
                // Use hashValue for reliable comparison
                if !self.connectedPeers.contains(where: { $0.hashValue == peerID.hashValue }) {
                    self.connectedPeers.append(peerID)
                    self.peerConnectionTimes[peerID] = Date()
                    // Initialize key exchange state for the new peer
                    self.peerKeyExchangeStates[peerID] = KeyExchangeTrackingInfo()


                    if self.connectedPeers.count == 1 {
                        self.connectionStatus = .connected
                    }
                    print("📱 MCSessionDelegate: Successfully connected to peer: \(peerID.displayName) (Hash: \(peerID.hashValue))")

                    // Ensure connection status reflects reality after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self else { return }
                        // Check if the peer is still considered connected
                        if connectedPeers.contains(where: { $0.hashValue == peerID.hashValue }) {
                            connectionStatus = .connected
                        } else if connectedPeers.isEmpty {
                            // If the peer disconnected very quickly, update status accordingly
                            connectionStatus = isSearchingForPeers ? .searching : .idle
                        }
                    }
                    // Refresh status and profiles AFTER connection is fully established
                    await self.refreshKeyStoreStatus() // Includes profile refresh
                } else {
                    print("📱 MCSessionDelegate: Received connected state for already known peer: \(peerID.displayName) (Hash: \(peerID.hashValue))")
                }

            case .connecting:
                print("⏳ MCSessionDelegate: Connecting to peer: \(peerID.displayName) (Hash: \(peerID.hashValue))...")
                if self.connectionStatus != .connected || self.connectedPeers.isEmpty {
                    self.connectionStatus = .connecting
                }
                // Timeout logic (seems reasonable)
                let peerIdentifier = peerID.displayName
                let peerHash = peerID.hashValue
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self else { return }
                    // Check if still connecting and if this specific peer hasn't connected
                    if connectionStatus == .connecting,
                       !connectedPeers.contains(where: { $0.hashValue == peerHash })
                    {
                        print("⚠️ MCSessionDelegate: Connection to \(peerIdentifier) (Hash: \(peerHash)) timed out")
                        // Only change status if no other peers are connected
                        if connectedPeers.isEmpty {
                            connectionStatus = isSearchingForPeers ? .searching : .idle
                        }
                    }
                }

            case .notConnected:
                print("❌ MCSessionDelegate: Disconnected from peer: \(peerID.displayName) (Hash: \(peerID.hashValue))")
                if self.connectionStatus == .connecting {
                    // If we were in the middle of connecting, clear the handler
                    self.invitationHandler = nil
                }

                // --- Reliable Cleanup on Disconnect ---
                // This is the primary place to clean up peer state.
                let profileID = self.peerIDToProfileID[peerID] // Get profile ID *before* removing from map

                // Remove from all tracking collections using hashValue for safety
                let initialPeerCount = self.connectedPeers.count
                self.connectedPeers.removeAll { $0.hashValue == peerID.hashValue }
                let removedFromList = self.connectedPeers.count < initialPeerCount

                let removedFromMap = self.peerIDToProfileID.removeValue(forKey: peerID) != nil
                let removedProfile = self.connectedPeerProfiles.removeValue(forKey: peerID) != nil
                let removedTime = self.peerConnectionTimes.removeValue(forKey: peerID) != nil
                let removedKeyState = self.peerKeyExchangeStates.removeValue(forKey: peerID) != nil // Clean up key exchange state


                print("MCSessionDelegate: Cleanup for \(peerID.displayName) (Hash: \(peerID.hashValue)) - Removed from list: \(removedFromList), map: \(removedFromMap), profile cache: \(removedProfile), time cache: \(removedTime), key state: \(removedKeyState)")

                if let profileIDString = profileID {
                    print("MCSessionDelegate: Disconnected peer Profile ID was: \(profileIDString)")
                    // Inform ArkavoClient about disconnection (if needed)
                    // Task { await self.arkavoClient.peerDidDisconnect(profileId: Data(base58Encoded: profileIDString)!) } // Example
                    print("Placeholder: Informing ArkavoClient about peer disconnection (Profile: \(profileIDString))")
                } else {
                    print("MCSessionDelegate: No profile ID mapping found for disconnected peer \(peerID.displayName) (Hash: \(peerID.hashValue)) during cleanup.")
                }

                // Close and remove associated input streams
                let streamsToRemove = self.activeInputStreams.filter { $1.hashValue == peerID.hashValue }.keys
                if !streamsToRemove.isEmpty {
                    print("MCSessionDelegate: Closing \(streamsToRemove.count) input stream(s) for disconnected peer \(peerID.displayName)")
                    for stream in streamsToRemove {
                        self.closeAndRemoveStream(stream) // Use the helper function
                    }
                }

                // Update overall connection status
                if self.connectedPeers.isEmpty {
                    print("MCSessionDelegate: No connected peers remaining.")
                    self.connectionStatus = self.isSearchingForPeers ? .searching : .idle
                } else {
                    print("MCSessionDelegate: \(self.connectedPeers.count) peers still connected.")
                    self.connectionStatus = .connected // Still connected to others
                }

                // Refresh status (e.g., update peer count display)
                await self.refreshKeyStoreStatus()

            @unknown default:
                print("MCSessionDelegate: Unknown peer state received: \(state) for peer \(peerID.displayName)")
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Pass received data to the main actor handler
        Task { @MainActor in
            handleIncomingData(data, from: peerID) // Now routes P2P messages or passes to ArkavoClient
        }
    }

    nonisolated func session(_: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received stream \(streamName) from peer \(peerID.displayName)")
        // Stream handling remains the same for now, but data read should also go to ArkavoClient
        Task { @MainActor in
            self.activeInputStreams[stream] = peerID
            print("Tracking input stream from \(peerID.displayName)")
            stream.delegate = self // Use nonisolated delegate
            stream.schedule(in: .main, forMode: .default)
            stream.open()
            print("Opened input stream from \(peerID.displayName) for \(streamName)")
        }
    }

    nonisolated func session(_: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            print("Started receiving resource \(resourceName) from \(peerID.displayName): \(progress.fractionCompleted * 100)%")
            resourceProgress[resourceName] = progress
        }
    }

    nonisolated func session(_: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            resourceProgress.removeValue(forKey: resourceName)
            if let error {
                print("Error receiving resource \(resourceName) from \(peerID.displayName): \(error)")
                return
            }
            guard let url = localURL else {
                print("No URL for received resource \(resourceName)")
                return
            }
            print("Successfully received resource \(resourceName) from \(peerID.displayName) at \(url.path)")
            // TODO: Consider if resources should be handled via ArkavoClient for encryption/decryption.
            // For now, we save the resource locally. Secure handling might require
            // passing the data/URL to ArkavoClient for decryption before saving or processing.
            saveReceivedResource(at: url, withName: resourceName)
        }
    }

    // Keep saveReceivedResource helper method
    private func saveReceivedResource(at url: URL, withName name: String) {
        do {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: url, to: destinationURL)
            print("Saved resource to: \(destinationURL.path)")
        } catch {
            print("Error saving resource: \(error)")
        }
    }
}

// MARK: - MCBrowserViewControllerDelegate

extension P2PGroupViewModel: MCBrowserViewControllerDelegate {
    nonisolated func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        print("Browser view controller finished")
        Task { @MainActor in
            browserViewController.dismiss(animated: true)
        }
    }

    nonisolated func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        print("Browser view controller cancelled")
        Task { @MainActor in
            browserViewController.dismiss(animated: true)
        }
    }

    nonisolated func browserViewController(_: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) -> Bool {
        print("MCBrowserDelegate: Found nearby peer: \(peerID.displayName) (Hash: \(peerID.hashValue)) with info: \(info ?? [:])")
        // Use Task to update MainActor-isolated properties
        Task { @MainActor in
            if let profileID = info?["profileID"] {
                print("MCBrowserDelegate: Peer \(peerID.displayName) has profile ID: \(profileID)")
                var discoveryInfo = info ?? [:] // Ensure info is mutable or create a new dict
                if discoveryInfo["timestamp"] == nil {
                    discoveryInfo["timestamp"] = "\(Date().timeIntervalSince1970)"
                }
                // Store mapping immediately when peer is discovered
                // Check if already mapped to avoid overwriting unnecessarily
                if self.peerIDToProfileID[peerID] == nil {
                    self.peerIDToProfileID[peerID] = profileID
                    print("MCBrowserDelegate: Associated peer \(peerID.displayName) (Hash: \(peerID.hashValue)) with profile ID \(profileID) from discovery info")
                } else if self.peerIDToProfileID[peerID] != profileID {
                    print("MCBrowserDelegate: Warning - Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) already mapped to a DIFFERENT profile ID (\(self.peerIDToProfileID[peerID]!)). Updating map.")
                    self.peerIDToProfileID[peerID] = profileID
                } else {
                    print("MCBrowserDelegate: Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) already correctly mapped to profile ID \(profileID).")
                }
                // Optionally fetch profile immediately
                // await self.refreshConnectedPeerProfiles() // Or fetch just this one
            } else {
                print("MCBrowserDelegate: Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) did not provide profileID in discovery info. Allowing connection.")
            }
        }
        // Always return true to allow the browser to display the peer
        return true
    }

    // Keep invitePeer method structure, but note it relies on browser selection
    func invitePeer(_ peerID: MCPeerID, context: Data? = nil) {
        guard mcSession != nil else {
            print("Error: No session available for invitation")
            return
        }
        var contextData: Data? = nil
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            let contextDict: [String: String] = [
                "profileID": profile.publicID.base58EncodedString,
                "name": profile.name,
            ]
            contextData = try? JSONSerialization.data(withJSONObject: contextDict, options: [])
        }
        print("Inviting peer: \(peerID.displayName)")
        _ = contextData ?? context // Use the generated context or the passed one
        Task { @MainActor in
            self.connectionStatus = .connecting
        }
        print("Programmatic invite function called for \(peerID.displayName). Relying on MCBrowserViewController selection for actual invite.")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension P2PGroupViewModel: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("MCAdvertiserDelegate: Received invitation from peer: \(peerID.displayName) (Hash: \(peerID.hashValue))")
        // Use Task to interact with MainActor properties
        Task { @MainActor in
            // Store the invitation handler associated with this specific peer invitation
            // Note: This assumes only one invitation is handled at a time. If multiple can arrive concurrently,
            // this needs a dictionary mapping peerID to handler. For simplicity, we assume one for now.
            self.invitationHandler = invitationHandler

            var peerInfo = [String: String]()
            var peerProfileID: String? = nil
            if let contextData = context {
                if let contextDict = try? JSONSerialization.jsonObject(with: contextData, options: []) as? [String: String] {
                    peerInfo = contextDict
                    print("MCAdvertiserDelegate: Invitation context: \(peerInfo)")
                    peerProfileID = peerInfo["profileID"]
                } else {
                    print("MCAdvertiserDelegate: Warning - Could not deserialize invitation context data.")
                }
            } else {
                print("MCAdvertiserDelegate: Invitation received with no context data.")
            }

            // Update peerID -> profileID map if necessary
            if let profileID = peerProfileID {
                if self.peerIDToProfileID[peerID] == nil {
                    self.peerIDToProfileID[peerID] = profileID
                    print("MCAdvertiserDelegate: Associated peer \(peerID.displayName) (Hash: \(peerID.hashValue)) with profile ID \(profileID) from invitation context")
                } else if self.peerIDToProfileID[peerID] != profileID {
                    print("MCAdvertiserDelegate: Warning - Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) already mapped to a DIFFERENT profile ID (\(self.peerIDToProfileID[peerID]!)). Updating map.")
                    self.peerIDToProfileID[peerID] = profileID
                } else {
                    print("MCAdvertiserDelegate: Peer \(peerID.displayName) (Hash: \(peerID.hashValue)) already correctly mapped to profile ID \(profileID).")
                }
            } else {
                print("MCAdvertiserDelegate: No profile ID found in invitation context for \(peerID.displayName) (Hash: \(peerID.hashValue))")
            }

            // Decision logic: Auto-accept if in a valid InnerCircle stream
            guard let selectedStream = self.selectedStream, selectedStream.isInnerCircleStream else {
                print("MCAdvertiserDelegate: No InnerCircle stream selected or stream invalid, declining invitation from \(peerID.displayName)")
                invitationHandler(false, nil)
                // Clear the handler as we've used it
                self.invitationHandler = nil
                return
            }

            print("MCAdvertiserDelegate: Auto-accepting invitation from \(peerID.displayName) for stream \(selectedStream.profile.name)")
            let sessionToUse = self.mcSession
            // Accept the invitation
            invitationHandler(true, sessionToUse)
            // It's generally recommended to clear the handler *after* the connection state changes (.connected or .notConnected)
            // in the MCSessionDelegate, but clearing it here is also common practice if assuming success.
            // Let's keep it here for now, but be aware of potential edge cases if the connection fails immediately.
            // self.invitationHandler = nil // Let delegate handle clearing
        }
    }

    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("MCAdvertiserDelegate: Failed to start advertising: \(error.localizedDescription)")
        Task { @MainActor in
            self.connectionStatus = .failed(error)
        }
    }
}

// MARK: - StreamDelegate for handling input streams

extension P2PGroupViewModel: Foundation.StreamDelegate {
    nonisolated func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }
        // Use Task to interact with MainActor properties/methods
        Task { @MainActor in
            // Find the peer associated with this stream *before* potential removal
            let peerID = self.activeInputStreams[inputStream]
            let peerDesc = peerID != nil ? "\(peerID!.displayName) (Hash: \(peerID!.hashValue))" : "Unknown Peer"

            switch eventCode {
            case .hasBytesAvailable:
                print("StreamDelegate: HasBytesAvailable for stream from \(peerDesc)")
                self.readInputStream(inputStream) // Reads data and passes to handleIncomingData -> ArkavoClient
            case .endEncountered:
                print("StreamDelegate: EndEncountered for stream from \(peerDesc)")
                self.closeAndRemoveStream(inputStream)
            case .errorOccurred:
                print("StreamDelegate: ErrorOccurred for stream from \(peerDesc): \(aStream.streamError?.localizedDescription ?? "unknown error")")
                self.closeAndRemoveStream(inputStream)
            case .openCompleted:
                print("StreamDelegate: OpenCompleted for stream from \(peerDesc)")
            case .hasSpaceAvailable:
                // Typically relevant for OutputStream
                print("StreamDelegate: HasSpaceAvailable for stream from \(peerDesc)")
            default:
                print("StreamDelegate: Unhandled stream event: \(eventCode) for stream from \(peerDesc)")
            }
        }
    }

    // Read stream and pass data to handleIncomingData
    private func readInputStream(_ stream: InputStream) {
        guard let peerID = activeInputStreams[stream] else {
            print("StreamDelegate Error: Received data from untracked stream. Closing.")
            closeAndRemoveStream(stream) // Close the unknown stream
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
                // Error reading
                let errorDesc = stream.streamError?.localizedDescription ?? "unknown error"
                print("StreamDelegate Error: Error reading from stream for peer \(peerID.displayName): \(errorDesc)")
                closeAndRemoveStream(stream) // Close stream on error
                return
            } else {
                // bytesRead == 0 usually means end of stream, but loop condition handles this.
                // Can also mean temporary pause, so just break the inner loop.
                break
            }
        }
        if !data.isEmpty {
            print("StreamDelegate: Read \(data.count) bytes from stream associated with peer \(peerID.displayName)")
            // Pass stream data to handleIncomingData
            handleIncomingData(data, from: peerID)
        } else {
            print("StreamDelegate: Read 0 bytes from stream associated with peer \(peerID.displayName) despite .hasBytesAvailable (might be temporary)")
        }
    }

    // Close and remove stream tracking
    private func closeAndRemoveStream(_ stream: InputStream) {
        // Ensure stream operations are done before removing from map
        stream.remove(from: .main, forMode: .default)
        stream.close()
        // Remove the stream from tracking
        if let peerID = activeInputStreams.removeValue(forKey: stream) {
            print("StreamDelegate: Closed and removed stream tracking for peer \(peerID.displayName) (Hash: \(peerID.hashValue))")
        } else {
            // This case should ideally not happen if called from stream delegate, but good for safety
            print("StreamDelegate: Closed and removed an untracked stream.")
        }
    }
}

// *** PLACEHOLDER EXTENSION: Replace with actual ArkavoClient methods ***
// This extension provides placeholder implementations for the methods
// we assume ArkavoClient might have, allowing the code to compile.
// These need to be replaced with the real ArkavoClient API calls.
extension ArkavoClient {
    // Placeholder for fetching detailed KeyStore status
    func getLocalKeyStoreDetails() async throws -> (validCount: Int, expiredCount: Int, capacity: Int, isRegenerating: Bool) {
        print("⚠️ WARNING: Using placeholder ArkavoClient.getLocalKeyStoreDetails()")
        // Simulate fetching data - replace with actual implementation
        // For testing, return some dummy values
        let capacity = 8192
        let validCount = Int.random(in: 6000...7000)
        let expiredCount = Int.random(in: 500...1000)
        let isRegenerating = false // Or toggle this for testing
        try await Task.sleep(nanoseconds: 100_000_000) // Simulate network delay
        // Simulate potential error
        // if Bool.random() { throw P2PGroupViewModel.P2PError.keyStoreInfoUnavailable("Simulated fetch error") }
        return (validCount, expiredCount, capacity, isRegenerating)
    }

    // Placeholder for triggering key regeneration
    func regenerateLocalKeys() async throws {
        print("⚠️ WARNING: Using placeholder ArkavoClient.regenerateLocalKeys()")
        // Simulate triggering regeneration
        try await Task.sleep(nanoseconds: 50_000_000) // Simulate call delay
        // Simulate potential error
        // if Bool.random() { throw P2PGroupViewModel.P2PError.arkavoClientError("Simulated regeneration trigger error") }
    }

    // Placeholder for rewrap method (already partially existed in P2PGroupViewModel)
    // func rewrapSessionKey(publicKey: Data, encryptedSessionKey: Data, senderProfileID: String?) async throws -> Data? {
    //     print("⚠️ WARNING: Using placeholder ArkavoClient.rewrapSessionKey()")
    //     try await Task.sleep(nanoseconds: 150_000_000) // Simulate work
    //     // Simulate success/failure
    //     if Bool.random() {
    //         return Data("simulated-rewrapped-key-\(UUID().uuidString)".utf8)
    //     } else {
    //         return nil // Simulate no key found
    //     }
    //     // Simulate error
    //     // throw P2PGroupViewModel.P2PError.arkavoClientError("Simulated rewrap error")
    // }

    // Placeholder for encrypting and sending P2P payload
    // Assumes this method handles the MCSession sending internally or via delegate callback
    func encryptAndSendPayload(payload: Data, policyData: Data) async throws -> Data {
        print("⚠️ WARNING: Using placeholder ArkavoClient.encryptAndSendPayload()")
        // Simulate encryption
        let encryptedData = Data("encrypted-\(payload.count)-bytes-with-policy".utf8)
        try await Task.sleep(nanoseconds: 20_000_000) // Simulate encryption time
        // This placeholder *returns* the encrypted data, assuming the caller (P2PGroupViewModel)
        // will send it via MCSession. If ArkavoClient handles sending directly,
        // this method might return Void or some confirmation.
        return encryptedData
    }

    // Placeholder for generating shared keys based on the key exchange protocol
    func generateSharedKeys(initiatorNonce: Data, responderNonce: Data, peerProfileID: Data) async throws {
        print("⚠️ WARNING: Using placeholder ArkavoClient.generateSharedKeys()")
        print("   Initiator Nonce: \(initiatorNonce.count) bytes")
        print("   Responder Nonce: \(responderNonce.count) bytes")
        print("   Peer Profile ID: \(peerProfileID.base58EncodedString)")
        // Simulate key generation work
        try await Task.sleep(nanoseconds: 300_000_000) // Simulate significant work
        // Simulate potential error
        // if Bool.random() { throw P2PGroupViewModel.P2PError.arkavoClientError("Simulated shared key generation error") }
        print("✅ Placeholder: Shared key generation simulation complete for peer \(peerProfileID.base58EncodedString).")
    }
}
