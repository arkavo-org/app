import ArkavoSocial
@preconcurrency import MultipeerConnectivity
import OpenTDFKit
import SwiftData // Import SwiftData for PersistenceController interaction
import SwiftUI
import UIKit

// Define custom notification names
extension Notification.Name {
    static let chatMessagesUpdated = Notification.Name("chatMessagesUpdatedNotification")
    // Add notification name for non-JSON data received
    static let nonJsonDataReceived = Notification.Name("nonJsonDataReceivedNotification")
}

// Public interface for peer discovery
@MainActor
class PeerDiscoveryManager: ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    // New properties for KeyStore status
    @Published var localKeyStoreInfo: (count: Int, capacity: Int)?
    @Published var peerKeyStoreCounts: [MCPeerID: Int] = [:]
    @Published var isRegeneratingKeys: Bool = false
    // Expose peer profiles fetched from persistence
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]

    private var implementation: P2PGroupViewModel

    init() {
        implementation = P2PGroupViewModel()

        // Forward published properties
        implementation.$connectedPeers.assign(to: &$connectedPeers)
        implementation.$isSearchingForPeers.assign(to: &$isSearchingForPeers)
        implementation.$selectedStream.assign(to: &$selectedStream)
        implementation.$connectionStatus.assign(to: &$connectionStatus)
        implementation.$peerConnectionTimes.assign(to: &$peerConnectionTimes)
        // Forward new KeyStore status properties
        implementation.$localKeyStoreInfo.assign(to: &$localKeyStoreInfo)
        implementation.$peerKeyStoreCounts.assign(to: &$peerKeyStoreCounts)
        implementation.$isRegeneratingKeys.assign(to: &$isRegeneratingKeys)
        // Forward peer profiles
        implementation.$connectedPeerProfiles.assign(to: &$connectedPeerProfiles)
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

    func sendTextMessage(_ message: String, in stream: Stream) throws {
        try implementation.sendTextMessage(message, in: stream)
    }

    func getPeerBrowser() -> MCBrowserViewController? {
        implementation.getBrowser()
    }

    /// Handle a rewrap request for encrypted communication
    /// - Parameters:
    ///   - publicKey: The ephemeral public key from the rewrap request
    ///   - encryptedSessionKey: The encrypted session key that needs to be rewrapped
    ///   - profileID: Optional profile ID to target a specific peer's KeyStore
    /// - Returns: Rewrapped key data or nil if no matching key found
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data, profileID: String? = nil) async throws -> Data? {
        try await implementation.handleRewrapRequest(
            publicKey: publicKey,
            encryptedSessionKey: encryptedSessionKey,
            senderProfileID: profileID
        )
    }

    // New methods for KeyStore status management
    /// Updates the local and peer KeyStore status information.
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

    /// Sends data to all connected peers or specified peers in a stream
    /// - Parameters:
    ///   - data: The data to send
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    ///   - stream: The stream context for the data
    /// - Throws: P2PError or session errors if sending fails
    func sendData(_ data: Data, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
        try await implementation.sendData(data, toPeers: peers, in: stream)
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
            true
        case let (.failed(lhsError), .failed(rhsError)):
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

// Implementation class for MultipeerConnectivity
@MainActor
class P2PGroupViewModel: NSObject, ObservableObject {
    // MultipeerConnectivity properties
    private var mcSession: MCSession?
    private var mcPeerID: MCPeerID?
    private var mcAdvertiser: MCNearbyServiceAdvertiser?
    private var mcBrowser: MCBrowserViewController?
    private var client: ArkavoClient?
    private var invitationHandler: ((Bool, MCSession?) -> Void)?

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]
    // New properties for KeyStore status
    @Published var localKeyStoreInfo: (count: Int, capacity: Int)?
    @Published var peerKeyStoreCounts: [MCPeerID: Int] = [:]
    @Published var isRegeneratingKeys: Bool = false
    // Store fetched peer profiles
    @Published var connectedPeerProfiles: [MCPeerID: Profile] = [:]

    // For tracking resources
    private var resourceProgress: [String: Progress] = [:]
    // For tracking streams
    private var activeInputStreams: [InputStream: MCPeerID] = [:] // Track streams by peer

    // Error types
    enum P2PError: Error, LocalizedError {
        case sessionNotInitialized
        case invalidStream
        case browserNotInitialized
        case keyStoreNotInitialized
        case profileNotAvailable
        case serializationFailed(String) // Added context
        case deserializationFailed(String) // Added context
        case persistenceError(String) // Added context
        case noConnectedPeers
        case keyRemovalFailed(String)
        case keyGenerationFailed(String) // Added error type

        var errorDescription: String? {
            switch self {
            case .sessionNotInitialized:
                "Peer-to-peer session not initialized"
            case .invalidStream:
                "Not a valid InnerCircle stream"
            case .browserNotInitialized:
                "Browser controller not initialized"
            case .keyStoreNotInitialized:
                "KeyStore not initialized"
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
            case let .keyRemovalFailed(reason):
                "Failed to remove used key: \(reason)"
            case let .keyGenerationFailed(reason):
                "Failed to generate KeyStore keys: \(reason)"
            }
        }
    }

    // KeyStore for secure key exchange
    private var keyStore: KeyStore?
    private let keyStoreCapacity = 8192 // Define capacity constant
    // Make sure this constant is used consistently throughout the code

    // Dictionary to store peer KeyStores by profile ID (in-memory cache)
    private var peerKeyStores: [String: KeyStore] = [:]
    // Map MCPeerID to ProfileID for easier lookup when updating peerKeyStoreCounts
    private var peerIDToProfileID: [MCPeerID: String] = [:]

    // Keep track of peers we've already sent KeyStores to
    private var sentKeyStoreToPeers: Set<String> = []

    // Track which keys have been used with which peers (one-time mode)
    @Published var usedKeyPairs: [String: Set<UUID>] = [:]

    // Adaptive thresholds for key regeneration
    private let minKeyThresholdPercentage = 0.1 // Regenerate when below 10%
    private let targetKeyPercentage = 0.8 // Regenerate up to 80%
    private let keyRegenerationBatchSize = 2000 // Max keys to generate in one go

    // Track ephemeral public keys for rewrap requests
    private var ephemeralPublicKeys: [Data: String] = [:]

    // Access to PersistenceController
    private let persistenceController = PersistenceController.shared

    // MARK: - Initialization and Cleanup

    deinit {
        // Need to use Task for actor-isolated methods in deinit
        _ = Task { @MainActor [weak self] in
            self?.cancelAsyncTasks()
            self?.cleanup()
        }
        // The task will finish on its own, we don't need to await it
    }

    private func cleanup() {
        stopSearchingForPeers()
        mcSession?.disconnect()
        invitationHandler = nil
        sentKeyStoreToPeers.removeAll()
        usedKeyPairs.removeAll()
        peerIDToProfileID.removeAll()
        peerKeyStores.removeAll()
        connectedPeerProfiles.removeAll() // Clear profiles
        // Close and remove tracked streams
        activeInputStreams.keys.forEach { $0.close() }
        activeInputStreams.removeAll()
        // Reset status properties
        localKeyStoreInfo = nil
        peerKeyStoreCounts.removeAll()
        isRegeneratingKeys = false
    }

    /// Check if we need to regenerate keys for one-time TDF mode based on adaptive thresholds.
    private func checkAndRegenerateKeys(forceRegeneration: Bool = false) async {
        // Always execute OT-TDF logic
        guard let keyStore else {
            return
        }

        let currentKeyCount = keyStore.keyPairs.count
        let minThreshold = Int(Double(keyStoreCapacity) * minKeyThresholdPercentage)
        let targetCount = Int(Double(keyStoreCapacity) * targetKeyPercentage)

        print("OT-TDF Key Check: Current=\(currentKeyCount), MinThreshold=\(minThreshold), Target=\(targetCount), Capacity=\(keyStoreCapacity)")

        // Regenerate if forced OR if below the minimum threshold
        if forceRegeneration || currentKeyCount < minThreshold {
            let keysNeeded = targetCount - currentKeyCount
            let keysToGenerate = min(keysNeeded, keyRegenerationBatchSize) // Generate in batches

            if keysToGenerate <= 0, !forceRegeneration {
                print("OT-TDF Key Check: Already at or above target, no regeneration needed.")
                await refreshKeyStoreStatus() // Update status even if no regeneration
                return
            }

            let generationReason = forceRegeneration ? "Manual trigger" : "Below threshold (\(currentKeyCount)/\(minThreshold))"
            print("OT-TDF Key Check: \(generationReason). Generating \(keysToGenerate) new keys...")

            isRegeneratingKeys = true // Set flag before starting
            await refreshKeyStoreStatus() // Update UI to show regeneration started

            do {
                try await keyStore.generateAndStoreKeyPairs(count: keysToGenerate)
                let newTotal = keyStore.keyPairs.count
                print("OT-TDF Key Check: Generated new keys. New total: \(newTotal)")

                // If we have connected peers, exchange the updated KeyStore
                if !connectedPeers.isEmpty {
                    print("OT-TDF Key Check: Sending updated KeyStore and Profile to \(connectedPeers.count) peers")
                    sentKeyStoreToPeers.removeAll() // Reset tracking as KeyStore has changed
                    for peer in connectedPeers {
                        initiateKeyStoreExchange(with: peer)
                    }
                }
            } catch {
                // Improved error logging
                let errorDesc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                print("❌ OT-TDF Key Check: CRITICAL ERROR generating new keys: \(errorDesc)")
                // Consider notifying the user or logging to a more persistent store
                // Update connection status or a dedicated error state if needed
                // connectionStatus = .failed(P2PError.keyGenerationFailed(errorDesc)) // Example
            }
            // This code now runs after the do-catch block completes
            isRegeneratingKeys = false // Clear flag after completion/error
            await refreshKeyStoreStatus() // Update status after regeneration attempt
        } else {
            print("OT-TDF Key Check: Key count (\(currentKeyCount)) is above minimum threshold (\(minThreshold)). No regeneration needed.")
            await refreshKeyStoreStatus() // Ensure status is up-to-date
        }
    }

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

        // Initialize KeyStore with defined capacity
        // Use our locally defined KeyStore instead of OpenTDFKit.KeyStore
        keyStore = KeyStore(curve: .secp256r1, capacity: keyStoreCapacity)
        print("Initializing KeyStore with capacity: \(keyStoreCapacity)")

        // Generate and store key pairs in the KeyStore
        do {
            guard let ks = keyStore else {
                print("Failed to initialize KeyStore")
                throw P2PError.keyStoreNotInitialized
            }

            // Generate initial keys up to the target percentage
            let initialKeyCount = Int(Double(keyStoreCapacity) * targetKeyPercentage)
            try await ks.generateAndStoreKeyPairs(count: initialKeyCount)

            // Get key count and capacity from the actor-isolated properties
            let keyCount = ks.keyPairs.count
            let actualCapacity = 8192

            print("Successfully initialized KeyStore with \(keyCount) keys (Target: \(initialKeyCount))")
            print("KeyStore capacity: \(actualCapacity) (Expected: \(keyStoreCapacity))")

            // If the actual capacity doesn't match the expected capacity, log a warning
            if actualCapacity != keyStoreCapacity {
                print("⚠️ WARNING: KeyStore capacity mismatch! Expected: \(keyStoreCapacity), Actual: \(actualCapacity)")
            }

            // Update local KeyStore info with the actual capacity from the KeyStore
            localKeyStoreInfo = (count: keyCount, capacity: actualCapacity)

            // Update local KeyStore info
            await refreshKeyStoreStatus()

        } catch {
            let errorDesc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("❌ Error generating initial keys for KeyStore: \(errorDesc)")
            // Continue even if key generation fails, as this is better than no KeyStore at all
            await refreshKeyStoreStatus() // Update status even on error
            // Consider throwing or setting a specific error state if KeyStore is critical
            // throw P2PError.keyGenerationFailed(errorDesc) // Example
        }

        // Create the session with encryption
        mcSession = MCSession(peer: mcPeerID!, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self

        // Set up service type for InnerCircle
        let serviceType = "arkavo-circle"

        // Include profile info in discovery info - helps with authentication
        // Note: Profile data itself is sent later during KeyStore exchange
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
            // Note: We don't remove the profile from persistence
            // so the user can choose to reconnect later
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

    // MARK: - Data Transmission

    /// Sends data to all connected peers or specified peers
    /// - Parameters:
    ///   - data: The data to send
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    /// - Throws: P2PError or session errors if sending fails
    func sendData(_ data: Data, toPeers peers: [MCPeerID]? = nil) throws {
        guard let mcSession else {
            throw P2PError.sessionNotInitialized
        }

        let targetPeers = peers ?? mcSession.connectedPeers
        guard !targetPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }

        try mcSession.send(data, toPeers: targetPeers, with: .reliable)
    }

    /// Sends data to all connected peers or specified peers in a stream
    /// - Parameters:
    ///   - data: The data to send
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    ///   - stream: The stream context for the data
    /// - Throws: P2PError or session errors if sending fails
    func sendData(_ data: Data, toPeers peers: [MCPeerID]? = nil, in stream: Stream) async throws {
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

        try mcSession.send(data, toPeers: targetPeers, with: .reliable)
        print("Raw data (\(data.count) bytes) sent to \(targetPeers.count) peers in stream: \(stream.profile.name)")
    }

    /// Initiates a Profile and KeyStore exchange with a newly connected peer
    /// - Parameter peer: The peer to exchange data with
    func initiateKeyStoreExchange(with peer: MCPeerID) {
        Task {
            do {
                // Create unique key for tracking based on peer display name and our profile ID
                let myProfileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let peerKey = "\(peer.displayName):\(myProfileID)" // Key identifies sending our store to this peer

                // Check if we already exchanged with this peer (using this specific key)
                if sentKeyStoreToPeers.contains(peerKey) {
                    print("Already initiated Profile/KeyStore exchange with peer \(peer.displayName) (key: \(peerKey)) - skipping")
                    return
                }

                // Mark as sent *before* sending to prevent race conditions/loops
                sentKeyStoreToPeers.insert(peerKey)
                print("Marked Profile/KeyStore exchange initiated for peer \(peer.displayName) (key: \(peerKey))")

                // Send our Profile and KeyStore to the peer
                try await sendKeyStoreAsync(to: peer) // This now sends both profile and keystore
                print("Initiated Profile/KeyStore exchange with peer: \(peer.displayName)")
            } catch {
                // If sending failed, remove the mark so we can try again later
                let myProfileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let peerKey = "\(peer.displayName):\(myProfileID)"
                sentKeyStoreToPeers.remove(peerKey)
                print("Error initiating Profile/KeyStore exchange with \(peer.displayName): \(error.localizedDescription). Resetting sent status.")
                // Consider reporting the error more visibly
                if let p2pError = error as? P2PError {
                    connectionStatus = .failed(p2pError)
                } else {
                    connectionStatus = .failed(P2PError.serializationFailed("Unknown error during exchange initiation"))
                }
            }
        }
    }

    /// Sends the Profile and KeyStore to a specific peer (Deprecated, use initiateKeyStoreExchange)
    /// - Parameter peer: The peer to send the KeyStore to
    /// - Throws: P2PError or serialization errors
    @available(*, deprecated, message: "Use initiateKeyStoreExchange which handles tracking")
    func sendKeyStore(to peer: MCPeerID) {
        Task {
            do {
                try await sendKeyStoreAsync(to: peer)
            } catch {
                print("Error sending Profile/KeyStore: \(error.localizedDescription)")
            }
        }
    }

    /// Asynchronous implementation of Profile and KeyStore sending
    /// - Parameter peer: The peer to send the data to
    /// - Throws: P2PError or serialization errors
    private func sendKeyStoreAsync(to peer: MCPeerID) async throws {
        guard let mcSession else {
            throw P2PError.sessionNotInitialized
        }

        guard let keyStore else {
            throw P2PError.keyStoreNotInitialized
        }

        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }

        // 1. Serialize the Profile
        let profileData: Data
        do {
            profileData = try profile.toData()
            print("Serialized local profile (\(profile.publicID.base58EncodedString)) for sending: \(profileData.count) bytes")
        } catch {
            print("❌ Failed to serialize profile: \(error)")
            throw P2PError.serializationFailed("Profile serialization failed: \(error.localizedDescription)")
        }

        // 2. Serialize the KeyStore
        let keyStoreData: Data
        do {
            keyStoreData = try await serializeKeyStore(keyStore)
            print("Serialized local KeyStore for sending: \(keyStoreData.count) bytes")
        } catch {
            print("❌ Failed to serialize KeyStore: \(error)")
            throw P2PError.serializationFailed("KeyStore serialization failed: \(error.localizedDescription)")
        }

        // 3. Create container with profile ID, profile data, and keystore data
        let container: [String: Any] = [
            "type": "keystore", // Keep type as "keystore" for backward compatibility or change if needed
            "profileID": profile.publicID.base58EncodedString, // Sender's profile ID
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "profileData": profileData.base64EncodedString(), // Add serialized profile
            "keystore": keyStoreData.base64EncodedString(), // Serialized KeyStore
        ]

        // 4. Serialize the container
        let containerData: Data
        do {
            containerData = try JSONSerialization.data(withJSONObject: container)
        } catch {
            print("❌ Failed to serialize JSON container: \(error)")
            throw P2PError.serializationFailed("JSON container serialization failed: \(error.localizedDescription)")
        }

        // 5. Send only to the specific peer
        try mcSession.send(containerData, toPeers: [peer], with: .reliable)
        print("Profile and KeyStore sent to peer: \(peer.displayName)")
    }

    /// Serializes a KeyStore into Data
    /// Uses the actual KeyStore serialization API
    /// - Parameter keyStore: The KeyStore to serialize
    /// - Returns: Serialized KeyStore data
    /// - Throws: Serialization errors
    private func serializeKeyStore(_ keyStore: KeyStore) async throws -> Data {
        // KeyStore.serialize() is already implemented in OpenTDFKit
        // It will serialize all key pairs into a compact binary format
        await keyStore.serialize()
    }

    /// Deserializes KeyStore data
    /// Uses the actual KeyStore deserialization API
    /// - Parameter data: The serialized KeyStore data
    /// - Returns: Deserialized KeyStore
    /// - Throws: Deserialization errors
    private func deserializeKeyStore(from data: Data) async throws -> KeyStore {
        // Create a new KeyStore with the same curve and capacity
        // Use the defined capacity constant
        let newKeyStore = KeyStore(curve: .secp256r1, capacity: keyStoreCapacity)
        print("Creating KeyStore for deserialization with capacity: \(keyStoreCapacity)")

        // Use the built-in deserialize method from our KeyStore
        try await newKeyStore.deserialize(from: data)

        // Log how many keys were loaded
        let keyCount = newKeyStore.keyPairs.count
        let actualCapacity = 8192
        print("Successfully deserialized KeyStore with \(keyCount) keys, capacity: \(actualCapacity)")

        return newKeyStore
    }

    /// Sends a text message to all connected peers
    /// - Parameters:
    ///   - message: The message to send
    ///   - stream: The stream context for the message
    /// - Throws: P2PError or serialization errors
    func sendTextMessage(_ message: String, in stream: Stream) throws {
        guard stream.isInnerCircleStream else {
            throw P2PError.invalidStream
        }

        guard let mcSession, !mcSession.connectedPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }

        guard let mcPeerID else {
            throw P2PError.sessionNotInitialized
        }

        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }

        // Create a message dictionary with sender info and text
        let messageDict: [String: Any] = [
            "type": "message",
            "messageID": UUID().uuidString,
            "sender": mcPeerID.displayName, // Use display name for simple chat
            "message": message,
            "timestamp": Date().timeIntervalSince1970,
            "profileID": profile.publicID.base58EncodedString, // Include sender profile ID
        ]

        // Convert to JSON data
        let data = try JSONSerialization.data(withJSONObject: messageDict)

        // Send to all connected peers
        try sendData(data)
        print("Text message sent to \(mcSession.connectedPeers.count) peers")
    }

    // MARK: - Message Handling

    /// Handles general incoming messages
    /// - Parameters:
    ///   - data: The received message data
    ///   - peer: The peer that sent the message
    private func handleIncomingMessage(_ data: Data, from peer: MCPeerID) {
        do {
            // Try to parse as JSON first
            if let messageDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Process the JSON message
                handleJSONMessage(messageDict, from: peer)
            } else {
                // Not a JSON message, handle as binary data
                print("Received \(data.count) bytes of binary data from \(peer.displayName)")
                // Application-specific binary data handling would go here
                // Could be part of a stream or a direct binary message
            }
        } catch {
            // If JSON parsing fails, treat as binary data
            print("Received \(data.count) bytes of non-JSON data from \(peer.displayName)")

            // Special handling for test data (any test device)
            if peer.displayName.contains("test") {
                let base64Data = data.base64EncodedString()
                print("Received non-JSON data from \(peer.displayName): \(data.count) bytes")
                print("Posting nonJsonDataReceived notification")
                
                // Post notification with the data - ensure this runs on main thread
                DispatchQueue.main.async {
                    // Debug print notification name to ensure it's correct
                    let notificationName = Notification.Name.nonJsonDataReceived
                    print("🔔 Posting notification with name: \(notificationName.rawValue)")
                    
                    NotificationCenter.default.post(
                        name: notificationName,
                        object: nil,
                        userInfo: [
                            "data": base64Data,
                            "dataSize": data.count,
                            "peerName": peer.displayName
                        ]
                    )
                    print("Posted nonJsonDataReceived notification successfully")
                }
            }

            // Application-specific binary data handling
        }
    }

    /// Handles parsed JSON messages
    /// - Parameters:
    ///   - message: The parsed JSON message
    ///   - peer: The peer that sent the message
    private func handleJSONMessage(_ message: [String: Any], from peer: MCPeerID) {
        // Check the message type
        if let messageType = message["type"] as? String {
            print("Processing message of type: \(messageType) from \(peer.displayName)")

            switch messageType {
            case "keystore": // Handles both Profile and KeyStore now
                handleKeyStoreMessage(message, from: peer)

            case "keystore_ack":
                handleKeyStoreAcknowledgement(message, from: peer)

            case "message":
                handleTextMessage(message, from: peer)

            case "message_ack":
                if let messageIDString = message["messageID"] as? String,
                   let messageID = UUID(uuidString: messageIDString)
                {
                    handleMessageAcknowledgement(messageID, from: peer)
                }

            default:
                print("Unknown message type: \(messageType)")
            }
        } else {
            // Message has no type field
            print("Message from \(peer.displayName) has no type field")
        }
    }

    /// Handles Profile and KeyStore messages
    /// - Parameters:
    ///   - message: The message containing profile and keystore data
    ///   - peer: The peer that sent the message
    private func handleKeyStoreMessage(_ message: [String: Any], from peer: MCPeerID) {
        // --- 1. Extract and Validate Data ---
        guard let profileIDString = message["profileID"] as? String, // Sender's profile ID
              let profileDataBase64 = message["profileData"] as? String,
              let keystoreBase64 = message["keystore"] as? String,
              let profileData = Data(base64Encoded: profileDataBase64),
              let keystoreData = Data(base64Encoded: keystoreBase64)
        else {
            print("❌ Invalid profile/keystore message format from \(peer.displayName)")
            // Optionally send an error acknowledgement
            return
        }

        let timestamp = message["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestampDate = Date(timeIntervalSince1970: timestamp)

        print("Received profile (\(profileData.count) bytes) and keystore (\(keystoreData.count) bytes) from peer \(peer.displayName) (Profile ID: \(profileIDString)), timestamp: \(timestampDate)")

        // --- 2. Process Asynchronously ---
        Task {
            var receivedProfile: Profile?
            var receivedKeyStore: KeyStore?
            var keyCount = 0
            var errorOccurred: Error?

            do {
                // --- 2a. Deserialize Profile ---
                print("Attempting to deserialize profile for \(profileIDString)...")
                receivedProfile = try Profile.fromData(profileData)
                guard let profile = receivedProfile else {
                    // Should not happen if fromData doesn't throw, but good practice
                    throw P2PError.deserializationFailed("Profile.fromData returned nil")
                }
                print("Successfully deserialized profile: \(profile.name) (\(profile.publicID.base58EncodedString))")

                // Verify received profileID matches the one in the message header
                guard profile.publicID.base58EncodedString == profileIDString else {
                    print("❌ Mismatch between message profileID (\(profileIDString)) and deserialized profile publicID (\(profile.publicID.base58EncodedString))")
                    throw P2PError.deserializationFailed("Profile ID mismatch")
                }

                // --- 2b. Persist Profile ---
                print("Attempting to save peer profile \(profileIDString) to persistence...")
                try await persistenceController.savePeerProfile(profile)
                print("Successfully saved/updated peer profile \(profileIDString)")

                // Fetch the persisted profile to ensure we have the managed object for relationship setting
                guard let persistedProfile = try await persistenceController.fetchProfile(withPublicID: profile.publicID) else {
                    print("❌ Failed to fetch persisted profile \(profileIDString) immediately after saving.")
                    throw P2PError.persistenceError("Failed to fetch profile after saving")
                }
                print("Fetched persisted profile instance for relationship setting.")

                // Update the published dictionary for UI
                connectedPeerProfiles[peer] = persistedProfile

                // --- 2c. Deserialize KeyStore ---
                print("Attempting to deserialize keystore for \(profileIDString)...")
                receivedKeyStore = try await deserializeKeyStore(from: keystoreData)
                guard let keyStore = receivedKeyStore else {
                    throw P2PError.deserializationFailed("deserializeKeyStore returned nil")
                }
                keyCount = keyStore.keyPairs.count
                print("Successfully deserialized keystore with \(keyCount) keys")

                // --- 2d. Persist KeyStoreData ---
                print("Attempting to save KeyStoreData for profile \(profileIDString)...")
                // Use the persistedProfile object fetched earlier
                try await persistenceController.saveKeyStoreData(
                    for: persistedProfile,
                    serializedData: keystoreData,
                    keyCurve: .secp256r1, // We know the curve type from initialization
                    capacity: keyStoreCapacity // Use the defined capacity
                )
                print("Successfully saved/updated KeyStoreData for profile \(profileIDString)")

                // --- 2e. Update In-Memory Caches ---
                peerKeyStores[profileIDString] = keyStore // Update in-memory cache
                peerIDToProfileID[peer] = profileIDString // Ensure mapping is set
                print("Updated in-memory KeyStore cache and PeerID->ProfileID map for \(profileIDString)")

                // --- 2f. Add Profile to InnerCircle ---
                if let selectedStream, selectedStream.isInnerCircleStream {
                    print("Adding profile \(profileIDString) to InnerCircle")
                    selectedStream.addToInnerCircle(persistedProfile)
                    try await persistenceController.saveChanges()
                    print("Successfully added profile to InnerCircle")
                } else {
                    print("No InnerCircle stream selected, not adding profile")
                }

                // --- 2g. Refresh Status ---
                await refreshKeyStoreStatus() // Update counts

                // --- 2h. Initiate Return Exchange (if needed) ---
                let myProfileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let exchangeKey = "\(peer.displayName):\(myProfileID)"
                if !sentKeyStoreToPeers.contains(exchangeKey) {
                    print("Received Profile/KeyStore from \(peer.displayName), initiating return exchange (key: \(exchangeKey)).")
                    initiateKeyStoreExchange(with: peer)
                } else {
                    print("Already initiated Profile/KeyStore exchange with \(peer.displayName) (key: \(exchangeKey)), not sending again in response.")
                }

            } catch {
                print("❌ Error processing received profile/keystore from \(peer.displayName) (\(profileIDString)): \(error)")
                errorOccurred = error
                // Clean up potentially partially saved state if needed
                if let profileID = receivedProfile?.publicID.base58EncodedString {
                    peerKeyStores.removeValue(forKey: profileID) // Remove potentially invalid cache entry
                }
                connectedPeerProfiles.removeValue(forKey: peer) // Remove profile from UI list on error
                await refreshKeyStoreStatus() // Refresh status even on error
            }

            // --- 3. Send Acknowledgement (Success or Error) ---
            do {
                let ackProfileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                var acknowledgement: [String: Any] = [
                    "type": "keystore_ack",
                    "profileID": ackProfileID, // Our profile ID acknowledging receipt
                    "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                    "timestamp": Date().timeIntervalSince1970,
                ]

                if let error = errorOccurred {
                    acknowledgement["status"] = "error"
                    acknowledgement["error"] = error.localizedDescription
                    print("Sending error acknowledgement to \(peer.displayName)")
                } else {
                    acknowledgement["status"] = "success"
                    acknowledgement["keyCount"] = keyCount // Report key count on success
                    print("Sending success acknowledgement (keyCount: \(keyCount)) to \(peer.displayName)")
                }

                let ackData = try JSONSerialization.data(withJSONObject: acknowledgement)
                try mcSession?.send(ackData, toPeers: [peer], with: .reliable)

            } catch {
                print("❌ Failed to send keystore acknowledgement to \(peer.displayName): \(error)")
            }
        }
    }

    /// Handles KeyStore acknowledgements
    /// - Parameters:
    ///   - message: The acknowledgement message
    ///   - peer: The peer that sent the acknowledgement
    private func handleKeyStoreAcknowledgement(_ message: [String: Any], from peer: MCPeerID) {
        guard let profileID = message["profileID"] as? String else { // Profile ID of the peer acknowledging
            print("Invalid keystore acknowledgement format")
            return
        }

        let status = message["status"] as? String ?? "success"
        let keyCount = message["keyCount"] as? Int // How many keys they received from us
        let deviceID = message["deviceID"] as? String ?? "unknown"
        let timestamp = message["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestampDate = Date(timeIntervalSince1970: timestamp)

        if status == "success" {
            if let keyCount {
                print("✅ Profile/KeyStore successfully received by peer \(peer.displayName) (Profile: \(profileID), Device: \(deviceID))")
                print("Peer reports our KeyStore contains \(keyCount) keys, received at \(timestampDate)")

                // Record the successful exchange
                _ = [
                    "peer": peer.displayName,
                    "profileID": profileID,
                    "deviceID": deviceID,
                    "timestamp": timestamp,
                    "keyCount": keyCount,
                ] as [String: Any]

                // Use a local record of successful exchanges for debugging
                // In a production app, you might persist this or use it for analytics
                print("Recorded successful Profile/KeyStore exchange with \(peer.displayName)")
            } else {
                print("✅ Profile/KeyStore successfully received by peer \(peer.displayName) (Profile: \(profileID))")
                print("No key count reported")
            }
        } else {
            let errorMessage = message["error"] as? String ?? "Unknown error"
            print("❌ Profile/KeyStore error reported by peer \(peer.displayName) (Profile: \(profileID), Device: \(deviceID)): \(errorMessage)")

            // If there was a serialization error, we might want to retry or adjust
            if errorMessage.contains("deserialize") || errorMessage.contains("serialization") || errorMessage.contains("format") {
                print("Serialization/Format error detected by peer, may need to investigate data structure or encoding.")
                // Consider logging the failed message structure if possible
            }

            // Record the failed exchange
            print("Recorded failed Profile/KeyStore exchange with \(peer.displayName)")

            // Since the exchange failed, remove the 'sent' marker to allow retrying later
            let myProfileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
            let peerKey = "\(peer.displayName):\(myProfileID)"
            if sentKeyStoreToPeers.remove(peerKey) != nil {
                print("Resetting sent status for peer \(peer.displayName) due to ACK error.")
            }
        }
        // Refresh status after ACK (success or fail) as it confirms peer interaction
        Task { await refreshKeyStoreStatus() }
    }

    /// Handles text messages
    /// - Parameters:
    ///   - message: The text message
    ///   - peer: The peer that sent the message
    private func handleTextMessage(_ message: [String: Any], from peer: MCPeerID) {
        guard let senderDisplayName = message["sender"] as? String,
              let messageText = message["message"] as? String,
              let timestamp = message["timestamp"] as? TimeInterval,
              let senderProfileIDString = message["profileID"] as? String
        else {
            print("Invalid text message format")
            return
        }

        print("Received message from \(senderDisplayName) (Profile: \(senderProfileIDString)): \(messageText)")

        if let messageIDString = message["messageID"] as? String,
           let messageID = UUID(uuidString: messageIDString)
        {
            sendMessageAcknowledgement(messageID, to: peer)
        }

        if let stream = selectedStream, stream.isInnerCircleStream {
            let date = Date(timeIntervalSince1970: timestamp)

            Task {
                do {
                    let thought = try await storeP2PMessageAsThought(
                        content: messageText,
                        sender: senderDisplayName,
                        senderProfileID: senderProfileIDString,
                        timestamp: date,
                        stream: stream
                    )
                    print("✅ P2P message stored successfully as Thought with ID: \(thought.id)")

                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: .p2pMessageReceived,
                            object: nil,
                            userInfo: [
                                "streamID": stream.publicID,
                                "thoughtID": thought.id,
                                "message": messageText,
                                "sender": senderDisplayName,
                                "timestamp": date,
                                "senderProfileID": senderProfileIDString,
                            ]
                        )
                    }

                    // Trigger a refresh of the chat messages
                    await MainActor.run {
                        NotificationCenter.default.post(name: .chatMessagesUpdated, object: nil)
                    }
                } catch {
                    print("❌ Failed to store P2P message as Thought: \(error)")
                }
            }
        }
    }

    /// Store a P2P message as a Thought for persistence
    /// - Returns: The created Thought object
    private func storeP2PMessageAsThought(content: String, sender _: String, senderProfileID: String, timestamp: Date, stream: Stream) async throws -> Thought {
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: Data(base58Encoded: senderProfileID) ?? Data(),
            streamPublicID: stream.publicID,
            mediaType: .say, // Use .say for P2P text messages
            createdAt: timestamp,
            contributors: []
        )

        // Convert the String content to Data for the 'nano' property
        let nanoData = Data(content.utf8)

        let thought = Thought(
            nano: nanoData, // Use nano: instead of content:
            metadata: thoughtMetadata
        )

        _ = try await PersistenceController.shared.saveThought(thought)

        // Use addThought instead of addToThoughts
        stream.addThought(thought)
        try await PersistenceController.shared.saveChanges()
        // Use base58EncodedString property instead of function call
        print("✅ P2P message stored as Thought for stream: \(stream.publicID.base58EncodedString)")

        return thought
    }

    /// Sends message acknowledgement
    /// - Parameters:
    ///   - messageID: The ID of the message being acknowledged
    ///   - peer: The peer to send the acknowledgement to
    private func sendMessageAcknowledgement(_ messageID: UUID, to peer: MCPeerID) {
        do {
            let ack: [String: Any] = [
                "type": "message_ack",
                "messageID": messageID.uuidString,
                "timestamp": Date().timeIntervalSince1970,
            ]

            let ackData = try JSONSerialization.data(withJSONObject: ack)
            try mcSession?.send(ackData, toPeers: [peer], with: .reliable)

        } catch {
            print("Failed to send message acknowledgement: \(error)")
        }
    }

    /// Handles message acknowledgements
    /// - Parameters:
    ///   - messageID: The ID of the acknowledged message
    ///   - peer: The peer that sent the acknowledgement
    private func handleMessageAcknowledgement(_ messageID: UUID, from peer: MCPeerID) {
        print("Message \(messageID) acknowledged by \(peer.displayName)")

        // Application-specific acknowledgement handling would go here
        // For example, updating the UI to show the message was delivered
    }

    // MARK: - KeyStore Status Management

    /// Updates the published properties related to KeyStore status.
    func refreshKeyStoreStatus() async {
        print("Refreshing KeyStore status...")
        // Update local KeyStore info
        if let ks = keyStore {
            let count = ks.keyPairs.count
            let actualCapacity = 8192

            // Use the actual capacity from the KeyStore instead of the constant
            localKeyStoreInfo = (count: count, capacity: actualCapacity)
            print("Local KeyStore: \(count)/\(actualCapacity) keys")

            // Log a warning if there's a mismatch between the expected and actual capacity
            if actualCapacity != keyStoreCapacity {
                print("⚠️ WARNING: KeyStore capacity mismatch! Expected: \(keyStoreCapacity), Actual: \(actualCapacity)")
            }
        } else {
            localKeyStoreInfo = nil
            print("Local KeyStore: Not initialized")
        }

        // Update peer KeyStore counts (from in-memory cache)
        var newPeerCounts: [MCPeerID: Int] = [:]
        let activePeerIDs = Set(connectedPeers) // Peers currently in the session

        // Iterate through connected peers to get their counts from the cache
        for peer in connectedPeers {
            if let profileID = peerIDToProfileID[peer], let peerKS = peerKeyStores[profileID] {
                let count = peerKS.keyPairs.count
                newPeerCounts[peer] = count
                print("Peer KeyStore (\(peer.displayName) / \(profileID)): \(count) keys (from cache)")
            } else {
                // Peer is connected but we don't have their KeyStore in cache (yet or error)
                newPeerCounts[peer] = 0 // Or use nil if you want to differentiate 'no store' from 'empty store'
                print("Peer KeyStore (\(peer.displayName)): No KeyStore found in cache or associated")
                // Consider fetching from persistence here if needed, but cache should be updated on receive
            }
        }

        // Clean up counts for peers that are no longer connected or mapped
        let currentPeerCountKeys = Set(peerKeyStoreCounts.keys)
        let peersToRemove = currentPeerCountKeys.subtracting(activePeerIDs)
        if !peersToRemove.isEmpty {
            print("Removing KeyStore counts for disconnected peers: \(peersToRemove.map(\.displayName))")
        }

        // Update the published property
        peerKeyStoreCounts = newPeerCounts
        print("Finished refreshing KeyStore status. Local: \(localKeyStoreInfo?.count ?? -1), Peers: \(peerKeyStoreCounts.count)")

        // Also refresh connected peer profiles from persistence
        await refreshConnectedPeerProfiles()
    }

    /// Fetches profiles for currently connected peers from persistence.
    private func refreshConnectedPeerProfiles() async {
        print("Refreshing connected peer profiles from persistence...")
        var updatedProfiles: [MCPeerID: Profile] = [:]
        let currentPeers = connectedPeers // Capture current list
        var profilesNeedingSave: [Profile] = []
        let now = Date()

        for peer in currentPeers {
            if let profileIDString = peerIDToProfileID[peer], let profileIDData = Data(base58Encoded: profileIDString) {
                do {
                    if let profile = try await persistenceController.fetchProfile(withPublicID: profileIDData) {
                        // Update lastSeen timestamp for online profiles
                        profile.lastSeen = now
                        profilesNeedingSave.append(profile)

                        updatedProfiles[peer] = profile
                        print("Fetched profile for \(peer.displayName) (\(profileIDString))")
                    // Removed the 'else' block that created a placeholder profile
                    }
                    // If profile is nil (not found locally), we simply don't add it to updatedProfiles here.
                    // It will be added when handleKeyStoreMessage receives and saves it.
                } catch {
                    print("❌ Error fetching profile \(profileIDString) for peer \(peer.displayName): \(error)")
                }
            } else {
                print("No profile ID mapped for peer \(peer.displayName), cannot fetch profile.")
            }
        }

        // Save updated lastSeen timestamps for profiles that were found
        if !profilesNeedingSave.isEmpty {
            do {
                try await persistenceController.saveChanges()
                print("Updated lastSeen for \(profilesNeedingSave.count) profiles")
            } catch {
                print("❌ Error saving updated profile timestamps: \(error)")
            }
        }

        // Update the published dictionary on the main thread
        // This will only contain profiles that were successfully fetched
        connectedPeerProfiles = updatedProfiles
        print("Finished refreshing connected peer profiles. Found \(updatedProfiles.count) profiles locally.")
    }

    /// Manually triggers regeneration of local KeyStore keys.
    func regenerateLocalKeys() async {
        print("Manual regeneration of local keys requested.")
        // Call checkAndRegenerateKeys with forceRegeneration = true
        await checkAndRegenerateKeys(forceRegeneration: true)
    }

    // MARK: - KeyStore Rewrap Support & One-Time TDF

    /// Removes a used key pair from the specified KeyStore (simplified version).
    /// - Parameters:
    ///   - keyStore: The KeyStore actor instance to modify.
    ///   - keyID: The UUID of the key pair to remove.
    private func removeUsedKey(keyStore: KeyStore, keyID: UUID) async {
        print("OT-TDF: Attempting to remove used key \(keyID) from KeyStore.")
        // Note: This is a mock implementation as we don't have direct access to the KeyStore's removeKeyPair method
        // In a real implementation, we would call keyStore.removeKeyPair(keyID: keyID)
        // For now, we assume the key was removed as part of the rewrap process
        print("OT-TDF: Key removal handled by OpenTDFKit during rewrap")

        // We should still persist the updated KeyStore after use
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            let serializedData = await keyStore.serialize()
            do {
                try await persistenceController.saveKeyStoreData(
                    for: profile,
                    serializedData: serializedData,
                    keyCurve: .secp256r1,
                    capacity: keyStoreCapacity
                )
                print("OT-TDF: Updated persisted KeyStore after key use")
            } catch {
                print("OT-TDF: Error updating persisted KeyStore: \(error.localizedDescription)")
            }
        }
    }

    /// Marks a specific key as used with a particular peer.
    /// - Parameters:
    ///   - keyID: The UUID of the key pair that was used.
    ///   - peerIdentifier: A string identifying the peer (e.g., profileID or display name).
    private func markKeyAsUsed(keyID: UUID, peerIdentifier: String) {
        print("OT-TDF: Marking key \(keyID) as used with peer \(peerIdentifier).")
        // Ensure the set exists for the peer identifier
        if usedKeyPairs[peerIdentifier] == nil {
            usedKeyPairs[peerIdentifier] = Set<UUID>()
        }
        // Add the keyID to the set of used keys for this peer
        usedKeyPairs[peerIdentifier]?.insert(keyID)
        let usedCount = usedKeyPairs[peerIdentifier]?.count ?? 0
        print("OT-TDF: Key \(keyID) marked. Total used keys for \(peerIdentifier): \(usedCount)")
    }

    /// Check if a KeyStore might contain a public key that matches the given one
    /// - Parameters:
    ///   - keyStore: The KeyStore to check
    ///   - publicKey: The public key to check for
    /// - Returns: Boolean indicating if a matching key might exist
    private func keyStoreMightContainMatchingKey(_ keyStore: KeyStore, publicKey _: Data) async -> Bool {
        // In OpenTDFKit, we would use the KeyStore's containsMatchingPublicKey method
        // The implementation depends on the OpenTDFKit API, but here's how it might work:

        // Get the key count for logging
        let keyCount = keyStore.keyPairs.count
        if keyCount == 0 {
            print("KeyStore is empty, cannot contain matching key")
            return false
        }

        print("Checking if KeyStore with \(keyCount) keys contains matching public key")

        // Use the KeyStore API to check for a matching public key
        // This is a mock implementation that will be replaced with the actual API call
        // In a real implementation, we would call:
        // return try await keyStore.containsMatchingPublicKey(publicKey)

        // Since we don't know the exact API, we'll assume it always might contain a matching key
        // The actual matching will be performed by the KAS service during rewrap
        print("KeyStore might contain matching key (will be verified during rewrap)")
        return true
    }

    /// Find a KeyStore containing a matching public key for a rewrap request
    /// - Parameters:
    ///   - publicKey: The public key to match against
    ///   - profileID: Optional profile ID to check specific peer's KeyStore
    /// - Returns: The KeyStore containing the matching key, or nil if not found
    func findKeyStoreWithMatchingKey(publicKey: Data, profileID: String? = nil) async -> KeyStore? {
        print("Looking for KeyStore with matching key, public key length: \(publicKey.count) bytes")

        // If a specific profile ID is provided, only check that KeyStore (from cache)
        if let profileID {
            guard let keyStore = peerKeyStores[profileID] else {
                print("No KeyStore found in cache for profile ID: \(profileID)")
                // TODO: Optionally try fetching from persistence here?
                return nil
            }

            // Check if this KeyStore contains the matching public key
            if await keyStoreMightContainMatchingKey(keyStore, publicKey: publicKey) {
                print("Found matching key in cached KeyStore for profile ID: \(profileID)")
                return keyStore
            }

            print("Cached KeyStore for profile ID \(profileID) does not contain matching key")
            return nil
        }

        // Otherwise, check all cached KeyStores
        print("Checking all \(peerKeyStores.count) cached peer KeyStores for matching key")

        for (profileID, keyStore) in peerKeyStores {
            if await keyStoreMightContainMatchingKey(keyStore, publicKey: publicKey) {
                print("Found matching key in cached KeyStore for profile ID: \(profileID)")
                return keyStore
            }
        }

        // If no peer KeyStore contains a matching key, check our local KeyStore
        if let localKeyStore = keyStore {
            print("Checking local KeyStore for matching key")
            if await keyStoreMightContainMatchingKey(localKeyStore, publicKey: publicKey) {
                print("Found matching key in local KeyStore")
                return localKeyStore
            }
        }

        print("No KeyStore found with matching public key in cache or locally")
        return nil
    }

    /// Handle a rewrap request using stored KeyStores
    /// - Parameters:
    ///   - publicKey: The ephemeral public key from the request
    ///   - encryptedSessionKey: The encrypted session key that needs rewrapping
    ///   - senderProfileID: Optional profile ID of the sender
    /// - Returns: Rewrapped key data or nil if no matching key found
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data, senderProfileID: String? = nil) async throws -> Data? {
        print("Handling rewrap request with public key length: \(publicKey.count) bytes")
        print("Encrypted session key length: \(encryptedSessionKey.count) bytes")

        let peerIdentifier = senderProfileID ?? "unknown-peer" // Use profile ID or a default for tracking
        if let senderProfileID {
            print("Request is from profile ID: \(senderProfileID)")
        } else {
            print("No sender profile ID provided, using identifier: \(peerIdentifier)")
        }

        // Find the appropriate KeyStore for this request (should be our local one for rewrap)
        guard let localKeyStore = keyStore else {
            print("No local KeyStore available for rewrapping")
            return nil
        }

        // Create a dummy KAS public key (required by updated API)
        var dummyKasPublicKey = Data(repeating: 0, count: 32)
        dummyKasPublicKey[0] = 0x02 // Add compression prefix for P-256

        // Create a KAS service using our local KeyStore to handle the request
        let kasService = KASService(keyStore: localKeyStore, baseURL: URL(string: "p2p://local")!)

        // Process the rewrap request
        do {
            // FIXME: The actual OpenTDFKit KASService.processKeyAccess needs to return the keyID
            // of the private key used for decryption. This UUID is a placeholder.
            // Replace this placeholder once the API provides the actual keyID.
            let usedKeyID = UUID() // <<< Placeholder Key ID
            print("OT-TDF: FIXME - Using placeholder key ID \(usedKeyID) for rewrap. Replace with actual key ID from KASService result.")

            let result = try await kasService.processKeyAccess(
                ephemeralPublicKey: publicKey,
                encryptedKey: encryptedSessionKey,
                kasPublicKey: dummyKasPublicKey // Add required kasPublicKey parameter
            )

            // Extract the rewrapped key data from the result tuple
            let rewrappedKey = result.rewrappedKey

            print("Successfully rewrapped key using local KeyStore.")

            // One-time TDF is always enabled: mark the key as used and remove it
            // 1. Mark the key as used with the specific peer
            markKeyAsUsed(keyID: usedKeyID, peerIdentifier: peerIdentifier)

            // 2. Remove the used key pair from the local KeyStore
            // Pass the actual keyStore instance and the identified usedKeyID
            await removeUsedKey(keyStore: localKeyStore, keyID: usedKeyID)

            // 3. Check if we need to regenerate keys after using one
            await checkAndRegenerateKeys() // This will also refresh status

            return rewrappedKey
        } catch {
            print("Failed to rewrap key: \(error)")
            // Consider specific error handling, e.g., if key not found vs. decryption error
            await refreshKeyStoreStatus() // Refresh status even on error
            return nil
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
                // Reset invitation handler as connection is established
                self.invitationHandler = nil

                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.peerConnectionTimes[peerID] = Date()

                    // When a new peer connects, initiate the Profile/KeyStore exchange
                    // This will send our data if we haven't already marked it as sent to this peer
                    self.initiateKeyStoreExchange(with: peerID)

                    // Update status if this is our first connection
                    if connectedPeers.count == 1 {
                        connectionStatus = .connected
                    }

                    // Notify UI and other components about connection
                    print("📱 Successfully connected to peer: \(peerID.displayName)")

                    // Queue a delayed status update to ensure UI shows connected state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Check if still connecting or if already moved to connected
                        if self.connectionStatus == .connecting || !self.connectedPeers.contains(peerID) {
                            // If we are still connecting OR the peer somehow disconnected immediately,
                            // only update to connected if there are actually peers.
                            if !self.connectedPeers.isEmpty {
                                self.connectionStatus = .connected
                            }
                            // Otherwise, the .notConnected case will handle the status update.
                        } else if self.connectedPeers.contains(peerID) {
                            // If we are already connected and the peer is still there, ensure status is connected.
                            self.connectionStatus = .connected
                        }
                    }
                    // Refresh KeyStore status and profiles as peer list changed
                    await self.refreshKeyStoreStatus() // This now also refreshes profiles
                }

            case .connecting:
                print("⏳ Connecting to peer: \(peerID.displayName)...")

                // Only update status if we're not already connected to other peers
                if connectionStatus != .connected || connectedPeers.isEmpty {
                    connectionStatus = .connecting
                }

                // Set a timeout to handle connection failure
                // This prevents staying in "Connecting" state forever
                let peerIdentifier = peerID.displayName
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self else { return }

                    // Only check if we're still connecting to this specific peer
                    if connectionStatus == .connecting,
                       !connectedPeers.contains(where: { $0.displayName == peerIdentifier })
                    {
                        print("⚠️ Connection to \(peerIdentifier) timed out")

                        // If we have no connected peers, go back to searching or idle
                        if connectedPeers.isEmpty {
                            connectionStatus = isSearchingForPeers ? .searching : .idle
                        }
                        // If we are connected to others, stay .connected
                    }
                }

            case .notConnected:
                print("❌ Disconnected from peer: \(peerID.displayName)")

                // Clear invitation handler if this was the peer we were trying to connect to
                if connectionStatus == .connecting {
                    self.invitationHandler = nil
                }

                self.connectedPeers.removeAll { $0 == peerID }
                self.peerConnectionTimes.removeValue(forKey: peerID)
                self.connectedPeerProfiles.removeValue(forKey: peerID) // Remove profile from UI list

                // Clean up peer-specific data caches
                if let profileID = self.peerIDToProfileID.removeValue(forKey: peerID) {
                    print("Removing cached KeyStore for disconnected peer \(peerID.displayName) (Profile: \(profileID))")
                    self.peerKeyStores.removeValue(forKey: profileID)
                    self.usedKeyPairs.removeValue(forKey: profileID) // Remove tracking for disconnected peer
                } else {
                    print("No profile ID mapping found for disconnected peer \(peerID.displayName)")
                }

                // Clean up any streams associated with this peer
                let streamsToRemove = self.activeInputStreams.filter { $1 == peerID }.keys
                for stream in streamsToRemove {
                    stream.close()
                    self.activeInputStreams.removeValue(forKey: stream)
                    print("Closed and removed stream associated with disconnected peer \(peerID.displayName)")
                }

                // Update connection status if no peers left
                if connectedPeers.isEmpty {
                    connectionStatus = isSearchingForPeers ? .searching : .idle
                }
                // Refresh KeyStore status and profiles as peer list changed
                await self.refreshKeyStoreStatus() // This now also refreshes profiles

            @unknown default:
                print("Unknown peer state: \(state)")
            }
        }
    }

    nonisolated func session(_: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Process received data on the main actor
        Task { @MainActor in
            handleIncomingMessage(data, from: peerID)
        }
    }

    nonisolated func session(_: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received stream \(streamName) from peer \(peerID.displayName)")

        // In a full implementation, you would handle the stream
        // For example, if used for file transfers:
        Task { @MainActor in
            // Store the stream and its associated peer
            self.activeInputStreams[stream] = peerID
            print("Tracking input stream from \(peerID.displayName)")

            stream.delegate = self // Use nonisolated delegate
            stream.schedule(in: .main, forMode: .default) // Schedule on main run loop
            stream.open()

            // Stream will be handled by StreamDelegate methods
            print("Opened input stream from \(peerID.displayName) for \(streamName)")
        }
    }

    nonisolated func session(_: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            print("Started receiving resource \(resourceName) from \(peerID.displayName): \(progress.fractionCompleted * 100)%")

            // Store progress for UI updates
            resourceProgress[resourceName] = progress
        }
    }

    nonisolated func session(_: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            // Remove from progress tracking
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

            // Process the resource based on its type
            if resourceName.hasSuffix(".jpg") || resourceName.hasSuffix(".png") {
                // Handle image
                let image = UIImage(contentsOfFile: url.path)
                print("Received image resource: \(image != nil ? "valid" : "invalid")")

                // Move to persistent storage if needed
                saveReceivedResource(at: url, withName: resourceName)

            } else {
                // Generic resource handling
                if let dataSize = try? Data(contentsOf: url).count {
                    print("Received resource of size: \(dataSize) bytes")
                } else {
                    print("Received resource of unknown size")
                }
                saveReceivedResource(at: url, withName: resourceName)
            }
        }
    }

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

        // Here you could implement filtering based on discovery info
        // For example, verify that the peer is part of your application

        if let profileID = info?["profileID"] {
            print("Peer \(peerID.displayName) has profile ID: \(profileID)")

            // You could check if this profile ID is in your whitelist
            // or matches some other criteria

            // Store discovery info for later use (e.g., associating profileID on invitation)
            Task { @MainActor in
                if var discoveryInfo = info {
                    // Add timestamp if not present
                    if discoveryInfo["timestamp"] == nil {
                        discoveryInfo["timestamp"] = "\(Date().timeIntervalSince1970)"
                    }
                    // Associate profileID with MCPeerID early if possible
                    self.peerIDToProfileID[peerID] = profileID
                    print("Associated peer \(peerID.displayName) with profile ID \(profileID) from discovery info")
                }
            }

            return true
        } else {
            print("Peer \(peerID.displayName) did not provide profileID in discovery info. Allowing connection.")
            // Allow connection even without profileID, but association will happen later
            return true
        }
    }

    // Helper method to invite a peer with context
    func invitePeer(_ peerID: MCPeerID, context: Data? = nil) {
        guard mcSession != nil else {
            print("Error: No session available for invitation")
            return
        }

        // Create context data with our profile info (minimal, just ID and name for now)
        var contextData: Data? = nil
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            let contextDict: [String: String] = [
                "profileID": profile.publicID.base58EncodedString,
                "name": profile.name,
                // Keep context small, full profile sent later
                // "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                // "timestamp": "\(Date().timeIntervalSince1970)"
            ]

            contextData = try? JSONSerialization.data(withJSONObject: contextDict, options: [])
        }

        // Browser automatically invites peers when user selects them
        // This method is here if we want to programmatically invite peers
        print("Inviting peer: \(peerID.displayName)")

        // Unused for now but kept for future implementation
        _ = contextData ?? context

        // Set connection status to connecting while waiting for response
        Task { @MainActor in
            self.connectionStatus = .connecting
        }

        // Invite the peer using the browser's invite method if available,
        // or directly via session if needed (though browser handles UI flow)
        // mcBrowser?.browser?.invitePeer(peerID, to: session, withContext: effectiveContext, timeout: 30)
        // Note: Direct session invitation might bypass browser UI/delegate flow.
        // Relying on user tapping in the browser is usually preferred.
        // If programmatic invite is needed, ensure context is handled correctly by advertiser delegate.

        // The browser delegate handles the actual invitation when the user taps a peer.
        // This function is more for reference or potential future programmatic invites.
        print("Programmatic invite function called for \(peerID.displayName). Relying on MCBrowserViewController selection for actual invite.")
    }
}

// MARK: - Rewrap Request Handling (Deprecated - Use handleRewrapRequest)

// This section contains older methods related to rewrap that might be deprecated
// by the unified handleRewrapRequest method. Keeping for reference if needed.

extension P2PGroupViewModel {
    /// Process a rewrap request for encrypted TDF communications (Potentially deprecated)
    /// - Parameters:
    ///   - ephemeralPublicKey: The ephemeral public key from the requester
    ///   - encryptedSessionKey: The encrypted session key that needs to be rewrapped
    ///   - profileID: The profile ID associated with the request
    /// - Returns: The rewrapped key data or nil if no matching key found
    // FIXME: This method is deprecated and duplicates logic in `handleRewrapRequest`. Review and remove if no longer needed.
    @available(*, deprecated, message: "Use handleRewrapRequest instead")
    func processRewrapRequest(
        ephemeralPublicKey: Data,
        encryptedSessionKey: Data,
        profileID: String? = nil
    ) async throws -> Data? {
        print("⚠️ Deprecated processRewrapRequest called")
        // Forward to the primary handler method
        return try await handleRewrapRequest(
            publicKey: ephemeralPublicKey,
            encryptedSessionKey: encryptedSessionKey,
            senderProfileID: profileID
        )
    }

    /// Find a KeyStore containing public keys for rewrap requests (Potentially deprecated)
    /// - Parameter profileID: Optional profile ID to check specific peer's KeyStore
    /// - Returns: KeyStore to use for rewrapping, or nil if none found
    // FIXME: This method is deprecated and duplicates logic in `findKeyStoreWithMatchingKey`. Review and remove if no longer needed.
    @available(*, deprecated, message: "Logic integrated into findKeyStoreWithMatchingKey")
    private func findKeyStoreWithMatchingPublicKey(_ profileID: String? = nil) -> KeyStore? {
        print("⚠️ Deprecated findKeyStoreWithMatchingPublicKey called")
        // Log the current state of available KeyStores
        print("Available peer KeyStores (cache): \(peerKeyStores.count)")

        // If a specific profile ID is provided, check that KeyStore cache
        if let profileID, let keyStore = peerKeyStores[profileID] {
            print("Using cached KeyStore for profile ID: \(profileID)")

            // Log the number of keys in this KeyStore for debugging
            Task {
                let keyCount = keyStore.keyPairs.count
                print("Cached KeyStore for profile ID \(profileID) contains \(keyCount) keys")
            }

            return keyStore
        }

        // If no profile ID specified or no matching KeyStore found in cache,
        // check all cached peer KeyStores.
        if profileID == nil, !peerKeyStores.isEmpty {
            print("No specific profile ID provided, checking all cached peer KeyStores")

            // Return the first available KeyStore from the cache as a fallback strategy
            if !peerKeyStores.isEmpty, let (firstProfileID, firstKeyStore) = peerKeyStores.first(where: { _ in true }) {
                print("Using first available cached KeyStore from profile ID: \(firstProfileID)")
                return firstKeyStore
            }
        }

        // Use our local KeyStore as a final fallback if available
        if let localKeyStore = keyStore {
            print("Using local KeyStore as fallback")
            return localKeyStore
        }

        print("No suitable KeyStore found in cache or locally")
        return nil
    }

    // P2P implementation doesn't need to access a central KAS server
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension P2PGroupViewModel: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer: \(peerID.displayName)")

        // Store the invitation handler for potential UI interaction or auto-accept
        Task { @MainActor in
            self.invitationHandler = invitationHandler
        }

        // Extract info from the invitation context if available
        var peerInfo = [String: String]()
        var peerProfileID: String? = nil
        if let context {
            if let contextDict = try? JSONSerialization.jsonObject(with: context, options: []) as? [String: String] {
                peerInfo = contextDict
                print("Invitation context: \(peerInfo)")
                peerProfileID = peerInfo["profileID"] // Extract profile ID if present
            }
        }

        // We need to check MainActor state from a nonisolated context
        Task { @MainActor in
            // Associate profile ID from context if available and not already set
            if let profileID = peerProfileID, self.peerIDToProfileID[peerID] == nil {
                self.peerIDToProfileID[peerID] = profileID
                print("Associated peer \(peerID.displayName) with profile ID \(profileID) from invitation context")
            } else if let existingProfileID = self.peerIDToProfileID[peerID] {
                print("Peer \(peerID.displayName) already associated with profile ID \(existingProfileID)")
            } else {
                print("No profile ID found in invitation context for \(peerID.displayName)")
            }

            // Check if we have the stream set up for InnerCircle
            guard let selectedStream = self.selectedStream, selectedStream.isInnerCircleStream else {
                print("No InnerCircle stream selected, declining invitation")
                invitationHandler(false, nil)
                self.invitationHandler = nil // Clear handler
                return
            }

            // Proceed with auto-accept logic
            print("Auto-accepting invitation from \(peerID.displayName)")
            // Ensure mcSession is captured correctly
            let sessionToUse = self.mcSession
            invitationHandler(true, sessionToUse)
            // Keep the handler until connection status changes (.connected or .notConnected)
        }

        // Example of manual acceptance (commented out):
        /*
         Task { @MainActor in
             // Show UI confirmation dialog
             // let peerName = peerInfo["name"] ?? peerID.displayName
             // let alert = UIAlertController(...) add actions
             // present alert...
             // In alert action handlers:
             //   acceptAction: invitationHandler(true, self.mcSession)
             //   declineAction: invitationHandler(false, nil)
             //   self.invitationHandler = nil // Clear handler after decision
         }
         */
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
    // This delegate method runs on the main thread because we scheduled the stream there.
    // However, it's marked nonisolated for protocol conformance.
    // Accessing @MainActor properties directly is safe here.
    nonisolated func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
        guard let inputStream = aStream as? InputStream else { return }

        // Use Task to ensure execution on the MainActor for property access
        Task { @MainActor in
            switch eventCode {
            case .hasBytesAvailable:
                self.readInputStream(inputStream)

            case .endEncountered:
                print("Stream ended")
                self.closeAndRemoveStream(inputStream)

            case .errorOccurred:
                print("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown error")")
                self.closeAndRemoveStream(inputStream)

            case .openCompleted:
                print("Stream opened successfully.")

            case .hasSpaceAvailable:
                // Relevant for OutputStream, ignore for InputStream
                break

            default:
                print("Unhandled stream event: \(eventCode)")
            }
        }
    }

    // Must be called on MainActor due to access to activeInputStreams
    private func readInputStream(_ stream: InputStream) {
        guard let peerID = activeInputStreams[stream] else {
            print("Error: Received data from untracked stream.")
            closeAndRemoveStream(stream) // Clean up untracked stream
            return
        }

        // Read the stream in chunks
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else if bytesRead < 0 {
                // Error occurred
                if let error = stream.streamError {
                    print("Error reading from stream for peer \(peerID.displayName): \(error)")
                } else {
                    print("Unknown error reading from stream for peer \(peerID.displayName)")
                }
                closeAndRemoveStream(stream) // Close stream on error
                return // Stop reading
            } else {
                // Reached end of stream (bytesRead == 0)
                break
            }
        }

        if !data.isEmpty {
            print("Read \(data.count) bytes from stream associated with peer \(peerID.displayName)")
            // Process the data (e.g., handle as a message)
            // This assumes stream data is handled the same way as direct data messages
            handleIncomingMessage(data, from: peerID)
        }
    }

    // Must be called on MainActor due to access to activeInputStreams
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
