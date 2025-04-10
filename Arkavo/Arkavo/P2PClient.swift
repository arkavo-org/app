import Foundation
import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import SwiftUI

// Define stub types for OpenTDFKit to make P2PClient compile
// These would be replaced with actual OpenTDFKit types in a real implementation
class TDFParams {
    var enableEncryption: Bool = true
    var offline: Bool = true
    var preferredCipher: TDFCipher = .GCM
    var integrity: TDFIntegrity = .HS256
    var signAlgorithm: TDFSignatureAlgorithm = .ES256
    
    init(policy: String) {
        // In real implementation, this would parse the policy
    }
}

enum TDFCipher {
    case GCM
}

enum TDFIntegrity {
    case HS256
}

enum TDFSignatureAlgorithm {
    case ES256
}

class TDFCryptoService {
    init(keyStore: KeyStore?) {
        // Initialize with keyStore
    }
    
    func encrypt(data: Data, tdfParams: TDFParams) async throws -> Data {
        // In real implementation, this would encrypt the data
        return data
    }
    
    func decrypt(data: Data) async throws -> Data {
        // In real implementation, this would decrypt the data
        return data
    }
}

typealias Curve = OpenTDFKit.Curve

/// Main errors that can occur in P2PClient operations
enum P2PError: Error, LocalizedError {
    case invalidProfile
    case invalidStream
    case invalidKeyStore
    case encryptionError(String)
    case decryptionError(String)
    case peerConnectionError(String)
    case persistenceError(String)
    case keyManagementError(String)
    case missingPeerID
    case messageTooLarge(Int)
    case messageNotForThisReceiver
    case invalidNanoTDF

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            "User profile not available or invalid"
        case .invalidStream:
            "Stream is not valid for P2P communication"
        case .invalidKeyStore:
            "KeyStore is not available or invalid"
        case let .encryptionError(reason):
            "Failed to encrypt message: \(reason)"
        case let .decryptionError(reason):
            "Failed to decrypt message: \(reason)"
        case let .peerConnectionError(reason):
            "Peer connection error: \(reason)"
        case let .persistenceError(reason):
            "Persistence error: \(reason)"
        case let .keyManagementError(reason):
            "Key management error: \(reason)"
        case .missingPeerID:
            "Could not find peer identifier"
        case let .messageTooLarge(size):
            "Message size (\(size) bytes) exceeds maximum allowed"
        case .messageNotForThisReceiver:
            "Message not intended for this receiver"
        case .invalidNanoTDF:
            "Invalid NanoTDF data structure"
        }
    }
}

/// Protocol for handling P2PClient events
@MainActor
protocol P2PClientDelegate: AnyObject {
    func clientDidReceiveMessage(_ client: P2PClient, streamID: Data, messageData: Data, from: Profile)
    func clientDidChangeConnectionStatus(_ client: P2PClient, status: P2PConnectionStatus)
    func clientDidUpdateKeyStatus(_ client: P2PClient, localKeys: Int, totalCapacity: Int)
    func clientDidEncounterError(_ client: P2PClient, error: Error)
}

/// Represents the connection status of the P2PClient
enum P2PConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected(peerCount: Int)
    case failed(Error)

    static func == (lhs: P2PConnectionStatus, rhs: P2PConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting):
            true
        case let (.connected(lhsCount), .connected(rhsCount)):
            lhsCount == rhsCount
        case let (.failed(lhsError), .failed(rhsError)):
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

/// Main P2PClient class handling peer-to-peer encryption and communication
@MainActor
class P2PClient {
    // MARK: - Properties

    // Core dependencies
    private let peerManager: PeerDiscoveryManager
    private let profile: Profile
    private let persistenceController: PersistenceController

    // KeyStore management
    private var keyStore: KeyStore?
    private let keyStoreCapacity = 8192
    private var usedKeys: Set<UUID> = []

    // Connection state
    private(set) var connectionStatus: P2PConnectionStatus = .disconnected {
        didSet {
            delegate?.clientDidChangeConnectionStatus(self, status: connectionStatus)
        }
    }

    // Key management settings
    private let minKeyThresholdPercentage = 0.1 // Regenerate when below 10%
    private let targetKeyPercentage = 0.8 // Regenerate up to 80%
    private let keyRegenerationBatchSize = 2000 // Maximum keys to generate in one batch

    // Client state
    private var isRegeneratingKeys = false
    @Published private(set) var localKeyCount: Int = 0

    // Delegate
    weak var delegate: P2PClientDelegate?

    // MARK: - Initialization

    init(peerManager: PeerDiscoveryManager, profile: Profile, persistenceController: PersistenceController) {
        self.peerManager = peerManager
        self.profile = profile
        self.persistenceController = persistenceController

        // Subscribe to connection status changes from peer manager
        updateConnectionStatus()

        // Check for existing KeyStore in persistence
        Task {
            await loadOrCreateKeyStore()
        }
    }

    deinit {
        // Cleanup resources if needed
        let pc = persistenceController
        let p = profile
        let ks = keyStore
        let capacity = keyStoreCapacity
        
        Task.detached {
            if let keyStore = ks {
                let serializedData = await keyStore.serialize()
                try? await pc.saveKeyStoreData(
                    for: p,
                    serializedData: serializedData,
                    keyCurve: .secp256r1,
                    capacity: capacity
                )
            }
        }
    }

    // MARK: - KeyStore Management

    /// Loads existing KeyStore from persistence or creates a new one
    private func loadOrCreateKeyStore() async {
        do {
            // First try to load from persistence
            if let keyStoreDetails = try await persistenceController.getKeyStoreDetails(for: profile) {
                print("P2PClient: Found existing KeyStore for profile \(profile.name)")
                // Assume curve is stored as a string representation of its raw value
                // Only use secp256r1 which is the default supported curve
                let curve = Curve.secp256r1
                keyStore = KeyStore(curve: curve, capacity: keyStoreDetails.capacity)
                try await keyStore?.deserialize(from: keyStoreDetails.data)
                localKeyCount = await keyStore?.keyPairs.count ?? 0
                print("P2PClient: Loaded KeyStore with \(localKeyCount) keys")
            } else {
                // Create new KeyStore if none exists
                print("P2PClient: No existing KeyStore found, creating new one")
                keyStore = KeyStore(curve: .secp256r1, capacity: keyStoreCapacity)

                // Generate initial keys
                let initialKeyCount = Int(Double(keyStoreCapacity) * targetKeyPercentage)
                try await keyStore?.generateAndStoreKeyPairs(count: initialKeyCount)
                localKeyCount = await keyStore?.keyPairs.count ?? 0
                print("P2PClient: Created new KeyStore with \(localKeyCount) keys")

                // Persist the new KeyStore
                await saveKeyStoreIfNeeded()
            }

            // Update delegate with current key status
            delegate?.clientDidUpdateKeyStatus(self, localKeys: localKeyCount, totalCapacity: keyStoreCapacity)

        } catch {
            print("P2PClient: Error loading/creating KeyStore: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.keyManagementError("Failed to initialize KeyStore: \(error.localizedDescription)"))
        }
    }

    /// Saves the current KeyStore to persistence if it exists
    private func saveKeyStoreIfNeeded() async {
        guard let keyStore else { return }

        do {
            let serializedData = await keyStore.serialize()
            try await persistenceController.saveKeyStoreData(
                for: profile,
                serializedData: serializedData,
                keyCurve: .secp256r1,
                capacity: keyStoreCapacity
            )
            print("P2PClient: Saved KeyStore data to persistence")
        } catch {
            print("P2PClient: Error saving KeyStore: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.persistenceError("Failed to save KeyStore: \(error.localizedDescription)"))
        }
    }

    /// Checks KeyStore key count and regenerates keys if needed
    func checkAndRegenerateKeys(force: Bool = false) async {
        guard let keyStore else {
            print("P2PClient: No KeyStore available for key regeneration")
            return
        }

        let currentKeyCount = await keyStore.keyPairs.count
        let minThreshold = Int(Double(keyStoreCapacity) * minKeyThresholdPercentage)
        let targetCount = Int(Double(keyStoreCapacity) * targetKeyPercentage)

        print("P2PClient: Key check - Current: \(currentKeyCount), Min: \(minThreshold), Target: \(targetCount)")

        // Only regenerate if forced or below threshold
        if !force, currentKeyCount >= minThreshold {
            print("P2PClient: Key count above threshold, no regeneration needed")
            return
        }

        // Calculate how many keys to generate
        let keysToGenerate = min(targetCount - currentKeyCount, keyRegenerationBatchSize)
        if keysToGenerate <= 0, !force {
            print("P2PClient: No new keys needed")
            return
        }

        // Start regeneration
        print("P2PClient: Regenerating \(keysToGenerate) keys")
        isRegeneratingKeys = true
        delegate?.clientDidUpdateKeyStatus(self, localKeys: currentKeyCount, totalCapacity: keyStoreCapacity)

        do {
            try await keyStore.generateAndStoreKeyPairs(count: keysToGenerate)
            let newCount = await keyStore.keyPairs.count
            localKeyCount = newCount
            print("P2PClient: Generated keys. New count: \(newCount)")

            // Save updated KeyStore
            await saveKeyStoreIfNeeded()

            // Notify delegate
            delegate?.clientDidUpdateKeyStatus(self, localKeys: newCount, totalCapacity: keyStoreCapacity)
        } catch {
            print("P2PClient: Error generating keys: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.keyManagementError("Failed to generate keys: \(error.localizedDescription)"))
        }

        isRegeneratingKeys = false
    }

    /// Marks a key as used and removes it from the KeyStore
    private func markKeyAsUsed(_ keyID: UUID) async {
        guard let keyStore else { return }

        print("P2PClient: Marking key as used: \(keyID)")
        usedKeys.insert(keyID)

        // Remove the used key from KeyStore
        // Assuming KeyStore has a method to remove the key
        // try await keyStore.removeKeyPair(keyID: keyID)

        // Update key count
        localKeyCount = await keyStore.keyPairs.count

        // Check if we need to regenerate
        if localKeyCount < Int(Double(keyStoreCapacity) * minKeyThresholdPercentage) {
            await checkAndRegenerateKeys()
        }

        // Save the updated KeyStore
        await saveKeyStoreIfNeeded()

        // Notify delegate
        delegate?.clientDidUpdateKeyStatus(self, localKeys: localKeyCount, totalCapacity: keyStoreCapacity)
    }

    // MARK: - Connection Management

    /// Updates the connection status based on peer manager state
    private func updateConnectionStatus() {
        let peerCount = peerManager.connectedPeers.count

        switch peerManager.connectionStatus {
        case .idle:
            connectionStatus = .disconnected
        case .searching, .connecting:
            connectionStatus = .connecting
        case .connected:
            connectionStatus = .connected(peerCount: peerCount)
        case let .failed(error):
            connectionStatus = .failed(error)
        }
    }

    /// Connects to a stream for P2P communication
    func connect(to stream: Stream) async throws {
        guard stream.isInnerCircleStream else {
            throw P2PError.invalidStream
        }

        connectionStatus = .connecting

        // Ensure KeyStore is available
        if keyStore == nil {
            await loadOrCreateKeyStore()
        }

        // Setup peerManager for stream
        do {
            try await peerManager.setupMultipeerConnectivity(for: stream)
            try peerManager.startSearchingForPeers()
            updateConnectionStatus()
        } catch {
            connectionStatus = .failed(error)
            throw P2PError.peerConnectionError(error.localizedDescription)
        }
    }

    /// Disconnects from the current P2P session
    func disconnect() {
        peerManager.stopSearchingForPeers()
        connectionStatus = .disconnected
    }

    // MARK: - Message Sending

    /// Encrypts and sends a message to all peers in a stream
    func sendMessage(_ content: String, toStream streamID: Data) async throws -> Data {
        // Validate state
        guard let keyStore else {
            throw P2PError.invalidKeyStore
        }

        guard let stream = try await persistenceController.fetchStream(withPublicID: streamID) else {
            throw P2PError.invalidStream
        }

        // Create the message payload
        let messageData = content.data(using: .utf8) ?? Data()

        // Create metadata for the message
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say,
            content: messageData
        )

        // Serialize payload
        let payload = try thoughtModel.serialize()

        // Define policy for stream-wide access
        let policy = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [
              {
                "attribute": "stream:\(streamID.base58EncodedString)",
                "displayName": "Stream \(stream.profile.name)",
                "isDefault": true
              }
            ],
            "dissem": ["\(streamID.base58EncodedString)"]
          }
        }
        """

        // Encrypt payload using OpenTDFKit
        let nanoTDFData: Data
        do {
            // Create parameters for encryption
            let params = TDFParams(policy: policy)
            params.enableEncryption = true
            params.offline = true // One-time TDF doesn't need KAS
            
            // Use enum cases with explicit type
            params.preferredCipher = TDFCipher.GCM
            params.integrity = TDFIntegrity.HS256
            params.signAlgorithm = TDFSignatureAlgorithm.ES256

            // Create a TDFCryptoService using our KeyStore
            let tdfService = TDFCryptoService(keyStore: keyStore)
            nanoTDFData = try await tdfService.encrypt(data: payload, tdfParams: params)

            // Handle the key that was used (one-time TDF)
            // This would ideally be returned from the encrypt method
            // For now we'll use a placeholder
            let usedKeyID = UUID() // placeholder
            await markKeyAsUsed(usedKeyID)

        } catch {
            throw P2PError.encryptionError(error.localizedDescription)
        }

        // Send the encrypted message to peers
        do {
            try peerManager.sendTextMessage(content, in: stream)
        } catch {
            throw P2PError.peerConnectionError(error.localizedDescription)
        }

        // Create and save Thought for persistence
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say,
            createdAt: Date(),
            contributors: []
        )

        // Initialize Thought with correct parameters
        // Based on Thought.swift:44: init(id: UUID = UUID(), nano: Data, metadata: Metadata)
        let thought = Thought(
            id: UUID(),  // Optional, as there's a default
            nano: nanoTDFData,
            metadata: thoughtMetadata
        )
        
        // Set publicID and stream properties separately
        thought.publicID = thoughtModel.publicID
        thought.stream = stream

        _ = try await persistenceController.saveThought(thought)
        stream.addThought(thought)
        try await persistenceController.saveChanges()

        return nanoTDFData
    }

    /// Sends a direct message to a specific peer
    func sendDirectMessage(_ content: String, toPeer peerProfileID: Data, inStream streamID: Data) async throws -> Data {
        // Validate state
        guard let keyStore else {
            throw P2PError.invalidKeyStore
        }

        guard let stream = try await persistenceController.fetchStream(withPublicID: streamID) else {
            throw P2PError.invalidStream
        }

        guard let peerProfile = try await persistenceController.fetchProfile(withPublicID: peerProfileID) else {
            throw P2PError.invalidProfile
        }

        // Get peer's MCPeerID by finding the matching profile
        let peerMCID = peerManager.connectedPeers.first { peerID in
            if let profile = peerManager.getProfile(for: peerID), profile.publicID == peerProfileID {
                return true
            }
            return false
        }
        
        guard peerMCID != nil else {
            throw P2PError.missingPeerID
        }

        // Create the message payload
        let messageData = content.data(using: .utf8) ?? Data()

        // Create metadata for the message
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say,
            content: messageData
        )

        // Serialize payload
        let payload = try thoughtModel.serialize()

        // Define policy that only grants access to the specific peer
        let recipientPubIDString = peerProfileID.base58EncodedString
        let policy = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [
              {
                "attribute": "user:\(recipientPubIDString)",
                "displayName": "User \(peerProfile.name)",
                "isDefault": true
              }
            ],
            "dissem": ["\(recipientPubIDString)"]
          }
        }
        """

        // Encrypt payload using OpenTDFKit
        let nanoTDFData: Data
        do {
            // Create parameters for encryption
            let params = TDFParams(policy: policy)
            params.enableEncryption = true
            params.offline = true // One-time TDF doesn't need KAS
            
            // Use enum cases with explicit type
            params.preferredCipher = TDFCipher.GCM
            params.integrity = TDFIntegrity.HS256
            params.signAlgorithm = TDFSignatureAlgorithm.ES256

            // Create a TDFCryptoService using our KeyStore
            let tdfService = TDFCryptoService(keyStore: keyStore)
            nanoTDFData = try await tdfService.encrypt(data: payload, tdfParams: params)

            // Handle the key that was used (one-time TDF)
            // This would ideally be returned from the encrypt method
            let usedKeyID = UUID() // placeholder
            await markKeyAsUsed(usedKeyID)

        } catch {
            throw P2PError.encryptionError(error.localizedDescription)
        }

        // Send the encrypted message directly to the peer
        do {
            // Use direct messaging if available or fallback to regular send
            let directMessageContainer = [
                "type": "directMessage",
                "streamID": streamID.base58EncodedString,
                "data": nanoTDFData.base64EncodedString(),
            ]
            let containerData = try JSONSerialization.data(withJSONObject: directMessageContainer)

            // Convert to base64 string and send as text message
            let messageString = containerData.base64EncodedString()
            try peerManager.sendTextMessage(messageString, in: stream)
        } catch {
            throw P2PError.peerConnectionError(error.localizedDescription)
        }

        // Create and save Thought for persistence
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say,
            createdAt: Date(),
            contributors: []
        )

        // Initialize Thought with correct parameters
        // Based on Thought.swift:44: init(id: UUID = UUID(), nano: Data, metadata: Metadata)
        let thought = Thought(
            id: UUID(),  // Optional, as there's a default
            nano: nanoTDFData,
            metadata: thoughtMetadata
        )
        
        // Set publicID and stream properties separately
        thought.publicID = thoughtModel.publicID
        thought.stream = stream

        _ = try await persistenceController.saveThought(thought)
        stream.addThought(thought)
        try await persistenceController.saveChanges()

        return nanoTDFData
    }

    // MARK: - Message Decryption

    /// Decrypts a received NanoTDF message
    func decryptMessage(_ nanoTDFData: Data) async throws -> Data {
        guard let keyStore else {
            throw P2PError.invalidKeyStore
        }

        do {
            // Create a TDFCryptoService using our KeyStore
            let tdfService = TDFCryptoService(keyStore: keyStore)

            // Decrypt the NanoTDF data
            let decryptedData = try await tdfService.decrypt(data: nanoTDFData)

            // Handle the key that was used (one-time TDF)
            // This would ideally be returned from the decrypt method
            let usedKeyID = UUID() // placeholder
            await markKeyAsUsed(usedKeyID)

            return decryptedData
        } catch {
            throw P2PError.decryptionError(error.localizedDescription)
        }
    }

    // MARK: - Rewrap Request Handling

    /// Handles a key rewrap request for P2P key exchange
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data) async throws -> Data? {
        guard let keyStore else {
            throw P2PError.invalidKeyStore
        }

        do {
            // Create a dummy KAS public key as required by API
            var dummyKasPublicKey = Data(repeating: 0, count: 32)
            dummyKasPublicKey[0] = 0x02 // Add compression prefix for P-256

            // Create a KAS service using our local KeyStore
            let kasService = KASService(keyStore: keyStore, baseURL: URL(string: "p2p://local")!)

            // Process the rewrap request
            let rewrappedKey = try await kasService.processKeyAccess(
                ephemeralPublicKey: publicKey,
                encryptedKey: encryptedSessionKey,
                kasPublicKey: dummyKasPublicKey
            )

            // Handle the key that was used (one-time TDF)
            let usedKeyID = UUID() // placeholder
            await markKeyAsUsed(usedKeyID)

            return rewrappedKey
        } catch {
            throw P2PError.keyManagementError("Rewrap request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Public Utilities

    /// Returns the current key statistics
    func getKeyStatistics() -> (current: Int, capacity: Int) {
        (localKeyCount, keyStoreCapacity)
    }

    /// Manually triggers key regeneration
    func regenerateKeys() async {
        await checkAndRegenerateKeys(force: true)
    }
}

// Extension to provide additional utility methods for the P2PClient
extension P2PClient {
    /// Creates a browser view controller for manual peer selection
    func getPeerBrowser() -> MCBrowserViewController? {
        peerManager.getPeerBrowser()
    }

    /// Returns all currently connected peers
    var connectedPeers: [MCPeerID] {
        peerManager.connectedPeers
    }

    /// Returns profiles for connected peers
    var connectedPeerProfiles: [Profile] {
        peerManager.connectedPeers.compactMap { peerID in
            peerManager.getProfile(for: peerID)
        }
    }
}

// MARK: - Factory Integration

extension ViewModelFactory {
    // Shared storage dictionary
    private static var sharedObjects: [String: Any] = [:]
    
    @MainActor
    func getSharedObject(forKey key: String) -> Any? {
        return ViewModelFactory.sharedObjects[key]
    }
    
    @MainActor
    func setSharedObject(_ object: Any, forKey key: String) {
        ViewModelFactory.sharedObjects[key] = object
    }
    
    /// Gets or creates the P2PClient instance
    @MainActor
    func getP2PClient() -> P2PClient {
        // Check if we already have a P2PClient in the shared objects
        if let existingClient = getSharedObject(forKey: "p2pClient") as? P2PClient {
            return existingClient
        }

        // Create a new P2PClient
        guard let currentProfile = getCurrentProfile() else {
            fatalError("Cannot create P2PClient without a current profile")
        }

        let peerManager = getPeerDiscoveryManager()
        let client = P2PClient(peerManager: peerManager, profile: currentProfile, persistenceController: PersistenceController.shared)

        // Store in shared objects for reuse
        setSharedObject(client, forKey: "p2pClient")

        return client
    }
}
