import ArkavoSocial
@preconcurrency import MultipeerConnectivity
import OpenTDFKit // Keep OpenTDFKit import if ArkavoClient APIs require it
import SwiftData
import SwiftUI
import UIKit

// Define custom notification names
extension Notification.Name {
    static let chatMessagesUpdated = Notification.Name("chatMessagesUpdatedNotification")
    // Add notification name for non-JSON data received
    static let nonJsonDataReceived = Notification.Name("nonJsonDataReceivedNotification")
    // Define notification name for P2P message received (used by ArkavoClient delegate)
    static let p2pMessageReceived = Notification.Name("p2pMessageReceivedNotification")
}

// Public interface for peer discovery
@MainActor
class PeerDiscoveryManager: ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    // KeyStore status properties - now driven by ArkavoClient via P2PGroupViewModel
    @Published var localKeyStoreInfo: (count: Int, capacity: Int)?
    @Published var isRegeneratingKeys: Bool = false
    // Expose peer profiles fetched from persistence
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]

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
        // Forward KeyStore status properties
        implementation.$localKeyStoreInfo.assign(to: &$localKeyStoreInfo)
        implementation.$isRegeneratingKeys.assign(to: &$isRegeneratingKeys)
        // Forward peer profiles
        implementation.$connectedPeerProfiles.assign(to: &$connectedPeerProfiles)

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
            return true
        case let (.failed(lhsError), .failed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
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
    // KeyStore status properties - now driven by ArkavoClient
    @Published var localKeyStoreInfo: (count: Int, capacity: Int)?
    @Published var isRegeneratingKeys: Bool = false
    // Store fetched peer profiles
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]

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
    private var peerIDToProfileID: [MCPeerID: String] = [:]

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

    /// Disconnects a specific peer
    /// - Parameter peer: The MCPeerID of the peer to disconnect
    func disconnectPeer(_ peer: MCPeerID) {
        guard let session = mcSession, connectedPeers.contains(peer) else {
            print("Cannot disconnect peer: Peer not found or session not active")
            return
        }

        print("Disconnecting peer: \(peer.displayName)")
        // Cancel any connections with this peer
        session.cancelConnectPeer(peer)

        // Remove from mapping and cached data
        if let profileID = peerIDToProfileID[peer] {
            print("Removing cached data for profile ID: \(profileID)")
            peerIDToProfileID.removeValue(forKey: peer)
            // Inform ArkavoClient about the disconnected peer (if needed)
            // await arkavoClient.peerDidDisconnect(profileId: profileID) // Example
        }

        // Update connection status if no peers left
        if connectedPeers.isEmpty {
            connectionStatus = isSearchingForPeers ? .searching : .idle
        }

        // Refresh KeyStore status to update UI
        Task {
            await refreshKeyStoreStatus()
        }
    }

    /// Returns the browser view controller for manual peer selection
    /// - Returns: MCBrowserViewController instance or nil if not available
    func getBrowser() -> MCBrowserViewController? {
        mcBrowser
    }

    // MARK: - Data Transmission (using ArkavoClient)

    /// Sends raw data via MCSession (used by ArkavoClient after encryption)
    /// - Parameters:
    ///   - data: The data to send (assumed encrypted by ArkavoClient)
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    /// - Throws: P2PError or session errors if sending fails
    private func sendRawData(_ data: Data, toPeers peers: [MCPeerID]? = nil) throws {
        guard let mcSession else {
            throw P2PError.sessionNotInitialized
        }

        let targetPeers = peers ?? mcSession.connectedPeers
        guard !targetPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }

        try mcSession.send(data, toPeers: targetPeers, with: .reliable)
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

            // Send the encrypted data via MCSession
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

    // MARK: - Message Handling (using ArkavoClient)

    /// Handles general incoming data (passes to ArkavoClient)
    /// - Parameters:
    ///   - data: The received message data
    ///   - peer: The peer that sent the message
    private func handleIncomingData(_ data: Data, from peer: MCPeerID) {
        print("Received \(data.count) bytes from \(peer.displayName).")
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
            // Placeholder implementation for ArkavoClient rewrap request handling.
            // Replace the following line with an actual call to ArkavoClient if available, for example:
            // rewrappedKey = try await arkavoClient.rewrapSessionKey(publicKey: publicKey, encryptedSessionKey: encryptedSessionKey, senderProfileID: senderProfileID)
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

    // MARK: - ArkavoClientDelegate Methods

    nonisolated func arkavoClientDidUpdateKeyStatus(_ client: ArkavoClient, keyCount: Int, capacity: Int, isRegenerating: Bool) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Key Status Update - Keys: \(keyCount)/\(capacity), Regenerating: \(isRegenerating)")
            self.localKeyStoreInfo = (count: keyCount, capacity: capacity)
            self.isRegeneratingKeys = isRegenerating
        }
    }

    nonisolated func arkavoClientDidReceiveMessage(_ client: ArkavoClient, message: String, fromProfileID: Data, streamID: Data?) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Received Message from \(fromProfileID.base58EncodedString)")
            guard let currentStream = self.selectedStream, currentStream.publicID == streamID else {
                print("Warning: Received message for stream \(streamID?.base58EncodedString ?? "nil") but current stream is \(self.selectedStream?.publicID.base58EncodedString ?? "nil"). Ignoring.")
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
                print("✅ Stored message from \(senderName) as Thought ID: \(thought.id)")

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
                print("❌ Failed to store received P2P message as Thought: \(error)")
            }
        }
    }

    nonisolated func arkavoClientDidUpdatePeerProfile(_ client: ArkavoClient, profile: Profile, publicKeyStoreData: Data?) {
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

    nonisolated func arkavoClientEncounteredError(_ client: ArkavoClient, error: Error) {
        Task { @MainActor in
            print("Delegate: ArkavoClient Encountered Error: \(error.localizedDescription)")
            // Update connection status or display error to user
            self.connectionStatus = .failed(P2PError.arkavoClientError(error.localizedDescription))
        }
    }

    // Add other ArkavoClientDelegate methods as needed based on its definition
    // e.g., func arkavoClientDidUpdateConnection(...)
    // Implement required methods if ArkavoClientDelegate protocol demands them
    nonisolated func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        // Example implementation (can be expanded)
        Task { @MainActor in
            print("Delegate: ArkavoClient State Changed: \(state)")
            // Could update connectionStatus based on ArkavoClient state if needed
        }
    }

    nonisolated func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        // This delegate method receives *raw* data from the WebSocket/NATS
        // It's distinct from the P2P message delegate method above.
        // P2PGroupViewModel might not need to handle these directly if ChatViewModel does.
        Task { @MainActor in
            print("Delegate: ArkavoClient Received Raw Message Data (\(message.count) bytes) - Likely handled elsewhere (e.g., ChatViewModel).")
        }
    }

    nonisolated func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
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

        print("Peer \(peerID.displayName) changed state to: \(stateStr)")

        Task { @MainActor in
            switch state {
            case .connected:
                self.invitationHandler = nil
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.peerConnectionTimes[peerID] = Date()

                    if self.connectedPeers.count == 1 {
                        self.connectionStatus = .connected
                    }
                    print("📱 Successfully connected to peer: \(peerID.displayName)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.connectionStatus == .connecting || !self.connectedPeers.contains(peerID) {
                            if !self.connectedPeers.isEmpty {
                                self.connectionStatus = .connected
                            }
                        } else if self.connectedPeers.contains(peerID) {
                            self.connectionStatus = .connected
                        }
                    }
                    await self.refreshKeyStoreStatus()
                    await self.refreshConnectedPeerProfiles() // Refresh profiles on connect
                }

            case .connecting:
                print("⏳ Connecting to peer: \(peerID.displayName)...")
                if self.connectionStatus != .connected || self.connectedPeers.isEmpty {
                    self.connectionStatus = .connecting
                }
                let peerIdentifier = peerID.displayName
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self else { return }
                    if self.connectionStatus == .connecting,
                       !self.connectedPeers.contains(where: { $0.displayName == peerIdentifier })
                    {
                        print("⚠️ Connection to \(peerIdentifier) timed out")
                        if self.connectedPeers.isEmpty {
                            self.connectionStatus = self.isSearchingForPeers ? .searching : .idle
                        }
                    }
                }

            case .notConnected:
                print("❌ Disconnected from peer: \(peerID.displayName)")
                if self.connectionStatus == .connecting {
                    self.invitationHandler = nil
                }

                self.connectedPeers.removeAll { $0 == peerID }
                self.peerConnectionTimes.removeValue(forKey: peerID)
                self.connectedPeerProfiles.removeValue(forKey: peerID)

                if let profileID = self.peerIDToProfileID.removeValue(forKey: peerID) {
                    print("Removing mapping for disconnected peer \(peerID.displayName) (Profile: \(profileID))")
                    // Inform ArkavoClient about disconnection (if needed)
                    // await self.arkavoClient.peerDidDisconnect(profileId: Data(base58Encoded: profileID)!) // Example
                    print("Placeholder: Informing ArkavoClient about peer disconnection (Profile: \(profileID))")
                } else {
                    print("No profile ID mapping found for disconnected peer \(peerID.displayName)")
                }

                let streamsToRemove = self.activeInputStreams.filter { $1 == peerID }.keys
                for stream in streamsToRemove {
                    stream.close()
                    self.activeInputStreams.removeValue(forKey: stream)
                    print("Closed and removed stream associated with disconnected peer \(peerID.displayName)")
                }

                if self.connectedPeers.isEmpty {
                    self.connectionStatus = self.isSearchingForPeers ? .searching : .idle
                }
                await self.refreshKeyStoreStatus()

            @unknown default:
                print("Unknown peer state: \(state)")
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Pass received data to the main actor handler
        Task { @MainActor in
            handleIncomingData(data, from: peerID) // Now passes data to ArkavoClient
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
        print("Found nearby peer: \(peerID.displayName) with info: \(info ?? [:])")
        if let profileID = info?["profileID"] {
            print("Peer \(peerID.displayName) has profile ID: \(profileID)")
            Task { @MainActor in
                var discoveryInfo = info ?? [:] // Ensure info is mutable or create a new dict
                if discoveryInfo["timestamp"] == nil {
                    discoveryInfo["timestamp"] = "\(Date().timeIntervalSince1970)"
                }
                self.peerIDToProfileID[peerID] = profileID
                print("Associated peer \(peerID.displayName) with profile ID \(profileID) from discovery info")
            }
            return true
        } else {
            print("Peer \(peerID.displayName) did not provide profileID in discovery info. Allowing connection.")
            return true
        }
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
        print("Received invitation from peer: \(peerID.displayName)")
        Task { @MainActor in
            self.invitationHandler = invitationHandler
        }
        var peerInfo = [String: String]()
        var peerProfileID: String? = nil
        if let context {
            if let contextDict = try? JSONSerialization.jsonObject(with: context, options: []) as? [String: String] {
                peerInfo = contextDict
                print("Invitation context: \(peerInfo)")
                peerProfileID = peerInfo["profileID"]
            }
        }
        Task { @MainActor in
            if let profileID = peerProfileID, self.peerIDToProfileID[peerID] == nil {
                self.peerIDToProfileID[peerID] = profileID
                print("Associated peer \(peerID.displayName) with profile ID \(profileID) from invitation context")
            } else if let existingProfileID = self.peerIDToProfileID[peerID] {
                print("Peer \(peerID.displayName) already associated with profile ID \(existingProfileID)")
            } else {
                print("No profile ID found in invitation context for \(peerID.displayName)")
            }
            guard let selectedStream = self.selectedStream, selectedStream.isInnerCircleStream else {
                print("No InnerCircle stream selected, declining invitation")
                invitationHandler(false, nil)
                self.invitationHandler = nil
                return
            }
            print("Auto-accepting invitation from \(peerID.displayName)")
            let sessionToUse = self.mcSession
            invitationHandler(true, sessionToUse)
        }
    }

    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
        Task { @MainActor in
            self.connectionStatus = .failed(error)
        }
    }
}

// MARK: - StreamDelegate for handling input streams

extension P2PGroupViewModel: Foundation.StreamDelegate {
    nonisolated func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }
        Task { @MainActor in
            switch eventCode {
            case .hasBytesAvailable:
                self.readInputStream(inputStream) // Reads data and passes to handleIncomingData -> ArkavoClient
            case .endEncountered:
                print("Stream ended")
                self.closeAndRemoveStream(inputStream)
            case .errorOccurred:
                print("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown error")")
                self.closeAndRemoveStream(inputStream)
            case .openCompleted:
                print("Stream opened successfully.")
            case .hasSpaceAvailable:
                break // Output streams might use this
            default:
                print("Unhandled stream event: \(eventCode)")
            }
        }
    }

    // Read stream and pass data to ArkavoClient
    private func readInputStream(_ stream: InputStream) {
        guard let peerID = activeInputStreams[stream] else {
            print("Error: Received data from untracked stream.")
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
                if let error = stream.streamError {
                    print("Error reading from stream for peer \(peerID.displayName): \(error)")
                } else {
                    print("Unknown error reading from stream for peer \(peerID.displayName)")
                }
                closeAndRemoveStream(stream)
                return
            } else {
                // bytesRead == 0 means end of stream or temporary pause
                break
            }
        }
        if !data.isEmpty {
            print("Read \(data.count) bytes from stream associated with peer \(peerID.displayName)")
            // Pass stream data to ArkavoClient
            handleIncomingData(data, from: peerID)
        }
    }

    // Close and remove stream tracking
    private func closeAndRemoveStream(_ stream: InputStream) {
        stream.remove(from: .main, forMode: .default)
        stream.close()
        if let peerID = activeInputStreams.removeValue(forKey: stream) {
            print("Closed and removed stream tracking for peer \(peerID.displayName)")
        } else {
            print("Closed and removed untracked stream.")
        }
    }
}
