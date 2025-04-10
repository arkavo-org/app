import Combine 
import Foundation
import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import SwiftUI

// Define stub types for OpenTDFKit integration components
// These provide controlled behavior for KeyStore interactions.

// --- Curve Stub ---
// Assuming Curve exists in OpenTDFKit or is defined elsewhere
enum Curve: String {
    case secp256r1 // Example curve
    // Add other curves as needed
}

// --- KeyStore Stub ---
// KeyPairIdentifier is UUID (Typealias from OpenTDFKit or defined here if needed)
typealias KeyPairIdentifier = UUID 

class KeyStore {
    let curve: Curve
    var capacity: Int // Made var to potentially update from deserialization if needed
    var keyPairs: [(key: KeyPairIdentifier, publicKey: Data)] = []

    init(curve: Curve, capacity: Int) {
        self.curve = curve
        self.capacity = capacity
        print("KeyStore (Stub): Initialized with curve \(curve.rawValue), capacity \(capacity)")
    }

    // Async because OpenTDFKit's version is async
    func generateAndStoreKeyPairs(count: Int) async throws {
        print("KeyStore (Stub): Generating \(count) key pairs...")
        for _ in 0..<count {
            if keyPairs.count < capacity {
                let newKeyID = UUID()
                // Generate a more realistic dummy public key if needed, e.g., 65 bytes for uncompressed P256
                let dummyPublicKey = Data("pubkey-\(newKeyID.uuidString)".utf8)
                keyPairs.append((key: newKeyID, publicKey: dummyPublicKey))
            } else {
                print("KeyStore (Stub): Capacity reached (\(capacity)), cannot generate more keys.")
                break // Stop generating if capacity is reached
            }
        }
    }

    // Async because OpenTDFKit's version is async
    func serialize() async -> Data {
        // Simple stub serialization including curve and capacity
        print("KeyStore (Stub): Serializing \(keyPairs.count) keys...")
        let keysString = keyPairs.map { $0.key.uuidString }.joined(separator: ",")
        // Include curve and capacity in serialization
        return Data("curve=\(curve.rawValue);capacity=\(capacity);keys=\(keysString)".utf8)
    }

    // Async because OpenTDFKit's version is async
    func deserialize(from data: Data) async throws {
        // Simple stub deserialization
        print("KeyStore (Stub): Deserializing data...")
        guard let dataString = String(data: data, encoding: .utf8) else {
            throw P2PError.keyManagementError("Failed to decode KeyStore data string")
        }
        let components = dataString.split(separator: ";").reduce(into: [String: String]()) { result, part in
            let keyValue = part.split(separator: "=", maxSplits: 1)
            if keyValue.count == 2 {
                result[String(keyValue[0])] = String(keyValue[1])
            }
        }

        // --- Stub Enhancement: Use deserialized capacity if present ---
        if let storedCapacityString = components["capacity"], let storedCapacity = Int(storedCapacityString) {
             print("KeyStore (Stub): Found capacity \(storedCapacity) in data. Current capacity is \(self.capacity).")
             // Optionally update capacity: self.capacity = storedCapacity
        }
        if let storedCurveString = components["curve"] {
            print("KeyStore (Stub): Found curve '\(storedCurveString)' in data. Current curve is '\(self.curve.rawValue)'.")
            // A real implementation might validate `storedCurveString == self.curve.rawValue`
        }
        // --- End Enhancement ---

        if let keysString = components["keys"], !keysString.isEmpty {
            let keyUUIDs = keysString.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            // Regenerate dummy public keys based on deserialized IDs
            keyPairs = keyUUIDs.map { (key: $0, publicKey: Data("pubkey-\($0.uuidString)".utf8)) }
            print("KeyStore (Stub): Deserialized \(keyPairs.count) keys.")
        } else {
            keyPairs = [] // Clear keys if "keys=" part is missing or empty
            print("KeyStore (Stub): Deserialized 0 keys (or keys field missing/empty).")
        }

        // Ensure count doesn't exceed capacity after deserialization
        if keyPairs.count > capacity {
            print("KeyStore (Stub): WARNING - Deserialized key count (\(keyPairs.count)) exceeds capacity (\(capacity)). Truncating.")
            keyPairs = Array(keyPairs.prefix(capacity))
        }
    }

    // Async because OpenTDFKit's version is async
    func removeKeyPair(keyID: KeyPairIdentifier) async throws {
        print("KeyStore (Stub): Attempting to remove key \(keyID)...")
        let initialCount = keyPairs.count
        keyPairs.removeAll { $0.key == keyID }
        if keyPairs.count < initialCount {
            print("KeyStore (Stub): Successfully removed key \(keyID). New count: \(keyPairs.count)")
        } else {
            print("KeyStore (Stub): Key \(keyID) not found for removal.")
            // Decide if not finding the key should be an error in a real scenario
            // throw P2PError.keyManagementError("Key \(keyID) not found for removal")
        }
    }
}

// --- TDFParams Stub ---
// Assuming TDFParams exists in OpenTDFKit or is defined elsewhere.
// Keeping stub if specific control or simplified init is needed.
class TDFParams {
    var enableEncryption: Bool = true
    var offline: Bool = true
    var preferredCipher: TDFCipher = .GCM // Use stubbed enum
    var integrity: TDFIntegrity = .HS256 // Use stubbed enum
    var signAlgorithm: TDFSignatureAlgorithm = .ES256 // Use stubbed enum
    var policy: String // Store the policy string

    init(policy: String) {
        self.policy = policy
        print("TDFParams (Stub): Initialized with policy: \(policy.prefix(50))...")
    }
}

// --- Enum Stubs ---
// Assuming these enums exist in OpenTDFKit or are defined elsewhere.
// Keeping stubs if OpenTDFKit isn't fully imported or for control.
enum TDFCipher {
    case GCM
    // Add other ciphers if needed
}

enum TDFIntegrity {
    case HS256
    // Add other integrity algorithms if needed
}

enum TDFSignatureAlgorithm {
    case ES256
    // Add other signature algorithms if needed
}

// --- TDFCryptoService Stub ---
// Assuming TDFCryptoService exists in OpenTDFKit or is defined elsewhere.
// Keeping stub for controlled encryption/decryption behavior.
class TDFCryptoService {
    private let keyStore: KeyStore? // Use our KeyStore stub

    init(keyStore: KeyStore?) {
        self.keyStore = keyStore
    }

    /// Encrypts data and returns the encrypted data along with the ID of the key used.
    /// Async because OpenTDFKit's version is async.
    func encrypt(data: Data, tdfParams: TDFParams) async throws -> (encryptedData: Data, usedKeyID: UUID) {
        // Access KeyStore properties directly (no await)
        guard let keyStore = keyStore, let keyPair = keyStore.keyPairs.first else {
            throw P2PError.encryptionError("No keys available in KeyStore for encryption.")
        }
        print("TDFCryptoService (Stub): Simulating encryption using key \(keyPair.key) with policy \(tdfParams.policy.prefix(50))...")
        // Return original data (as it's a stub) and the KeyPairIdentifier (UUID)
        // In a real scenario, this would return actual NanoTDF data.
        let nanoTDFHeader = "NANO_TDF_HEADER_STUB:" // Simulate a header
        let nanoTDFPayload = data // Simulate payload (unencrypted in stub)
        let simulatedNanoTDF = Data(nanoTDFHeader.utf8) + nanoTDFPayload
        return (simulatedNanoTDF, keyPair.key)
    }

    /// Decrypts data and returns the decrypted data along with the ID of the key used.
    /// Async because OpenTDFKit's version is async.
    func decrypt(data: Data) async throws -> (decryptedData: Data, usedKeyID: UUID) {
        // Access KeyStore properties directly (no await)
        guard let keyStore = keyStore, let keyPair = keyStore.keyPairs.first else {
             throw P2PError.decryptionError("No keys available in KeyStore for decryption.")
        }
        print("TDFCryptoService (Stub): Simulating decryption using key \(keyPair.key)")
        // Note: In a real scenario, the correct key would be identified from the NanoTDF header.
        // We simulate removing the stub header.
        let headerString = "NANO_TDF_HEADER_STUB:"
        let headerData = Data(headerString.utf8)
        var decryptedPayload = data
        if data.starts(with: headerData) {
            decryptedPayload = data.dropFirst(headerData.count)
        } else {
            print("TDFCryptoService (Stub): WARNING - Received data doesn't have expected stub header.")
        }
        // Return simulated decrypted data and the KeyPairIdentifier (UUID)
        return (decryptedPayload, keyPair.key)
    }
}

// --- KASService Stub ---
// Assuming KASService exists in OpenTDFKit or is defined elsewhere.
// Keeping stub for controlled rewrap behavior.
class KASService {
    private let keyStore: KeyStore? // Use our KeyStore stub
    private let baseURL: URL

    init(keyStore: KeyStore?, baseURL: URL) {
        self.keyStore = keyStore
        self.baseURL = baseURL
    }

    /// Processes a key access request (rewrap) and returns the rewrapped key
    /// along with the ID of the local key pair used for the operation.
    /// Async because OpenTDFKit's version is async.
    func processKeyAccess(ephemeralPublicKey: Data, encryptedKey: Data, kasPublicKey: Data) async throws -> (rewrappedKey: Data, usedKeyID: UUID) {
        // Access KeyStore properties directly (no await)
        guard let keyStore = keyStore, let keyPair = keyStore.keyPairs.first else {
            throw P2PError.keyManagementError("No keys available in KeyStore for rewrap.")
        }
        print("KASService (Stub): Simulating rewrap using key \(keyPair.key) for ephemeral key \(ephemeralPublicKey.count) bytes, base URL \(baseURL)")
        // Return dummy rewrapped key and the KeyPairIdentifier (UUID)
        let dummyRewrappedKey = Data("rewrappedKey-\(UUID().uuidString)".utf8)
        return (dummyRewrappedKey, keyPair.key)
    }
}

// --- P2PError Enum --- 
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
            return "User profile not available or invalid"
        case .invalidStream:
            return "Stream is not valid for P2P communication"
        case .invalidKeyStore:
            return "KeyStore is not available or invalid"
        case let .encryptionError(reason):
            return "Failed to encrypt message: \(reason)"
        case let .decryptionError(reason):
            return "Failed to decrypt message: \(reason)"
        case let .peerConnectionError(reason):
            return "Peer connection error: \(reason)"
        case let .persistenceError(reason):
            return "Persistence error: \(reason)"
        case let .keyManagementError(reason):
            return "Key management error: \(reason)"
        case .missingPeerID:
            return "Could not find peer identifier"
        case let .messageTooLarge(size):
            return "Message size (\(size) bytes) exceeds maximum allowed"
        case .messageNotForThisReceiver:
            return "Message not intended for this receiver"
        case .invalidNanoTDF:
            return "Invalid NanoTDF data structure"
        }
    }
}

// --- P2PClientDelegate Protocol ---
/// Protocol for handling P2PClient events
@MainActor
protocol P2PClientDelegate: AnyObject {
    // Note: Ensure Profile type is the actual Profile class from your project
    func clientDidReceiveMessage(_ client: P2PClient, streamID: Data, messageData: Data, from: Profile)
    func clientDidChangeConnectionStatus(_ client: P2PClient, status: P2PConnectionStatus)
    func clientDidUpdateKeyStatus(_ client: P2PClient, localKeys: Int, totalCapacity: Int)
    func clientDidEncounterError(_ client: P2PClient, error: Error)
}

// --- P2PConnectionStatus Enum ---
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
            return true
        case let (.connected(lhsCount), .connected(rhsCount)):
            return lhsCount == rhsCount
        case let (.failed(lhsError), .failed(rhsError)):
            // Compare descriptions for basic equality check
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Main P2PClient class handling peer-to-peer encryption and communication
@MainActor
class P2PClient {
    // MARK: - Properties

    // Core dependencies (Using actual types defined elsewhere)
    // Ensure these types (PeerDiscoveryManager, Profile, PersistenceController)
    // match the actual definitions in your project.
    private let peerManager: PeerDiscoveryManager
    private let profile: Profile
    private let persistenceController: PersistenceController

    // KeyStore management (Using KeyStore stub defined above)
    private var keyStore: KeyStore?
    private let keyStoreCapacity = 8192 // Default capacity for new stores
    private var usedKeys: Set<UUID> = [] // Tracks keys marked as used but potentially not yet removed

    // Connection state
    private(set) var connectionStatus: P2PConnectionStatus = .disconnected {
        didSet {
            // Avoid redundant updates if status hasn't actually changed
            if oldValue != connectionStatus {
                delegate?.clientDidChangeConnectionStatus(self, status: connectionStatus)
            }
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

    // Combine publisher for peer manager status (Requires Combine import)
    private var peerManagerStatusCancellable: AnyCancellable?
    // Import Combine at the top if not already present

    // MARK: - Initialization

    init(peerManager: PeerDiscoveryManager, profile: Profile, persistenceController: PersistenceController) {
        self.peerManager = peerManager
        self.profile = profile
        self.persistenceController = persistenceController

        // Subscribe to connection status changes from peer manager
        // Ensure PeerDiscoveryManager's connectionStatus is @Published
        peerManagerStatusCancellable = peerManager.$connectionStatus
            .receive(on: DispatchQueue.main) // Ensure updates are on the main thread
            .sink { [weak self] newStatus in
                self?.updateConnectionStatus(from: newStatus)
            }

        // Initial status check based on current peerManager state
        updateConnectionStatus(from: peerManager.connectionStatus)

        // Load or create KeyStore asynchronously
        Task {
            await loadOrCreateKeyStore()
        }
    }

    deinit {
        peerManagerStatusCancellable?.cancel() // Cancel subscription

        // Cleanup resources if needed
        let pc = persistenceController
        let p = profile
        let ks = keyStore // Capture reference to keyStore

        // Save KeyStore in a detached task if it exists
        Task.detached { [ks] in // Capture ks by value
            if let keyStoreToSave = ks {
                // Call static saveKeyStore which correctly handles capacity and curve
                await P2PClient.saveKeyStore(keyStore: keyStoreToSave, persistenceController: pc, profile: p)
            }
        }
    }

    // Static helper for saving KeyStore, used by deinit
    private static func saveKeyStore(keyStore: KeyStore, persistenceController: PersistenceController, profile: Profile) async {
        do {
            // Serialize the KeyStore (async)
            let serializedData = await keyStore.serialize()
            // Access properties directly (no await)
            let curve = keyStore.curve
            let capacity = keyStore.capacity

            // Save using persistence controller (async)
            // Ensure PersistenceController.saveKeyStoreData uses the correct Curve type
            // and accepts the stubbed Curve enum or its rawValue.
            try await persistenceController.saveKeyStoreData(
                for: profile,
                serializedData: serializedData,
                keyCurve: curve, // Pass the Curve enum directly
                capacity: capacity // Use the actual capacity from the KeyStore instance
            )
            print("P2PClient (Static Save): Saved KeyStore data to persistence (Curve: \(curve.rawValue), Capacity: \(capacity))")
        } catch {
            print("P2PClient (Static Save): Error saving KeyStore: \(error)")
            // Cannot easily call delegate from static context/deinit
        }
    }


    // MARK: - KeyStore Management

    /// Loads existing KeyStore from persistence or creates a new one
    private func loadOrCreateKeyStore() async {
        do {
            // Try to load details from persistence (async)
            // Assumes PersistenceController.getKeyStoreDetails returns (Data, String, Int)?
            if let (keyStoreData, keyStoreCurveRawValue, keyStoreCapacityValue) = try await persistenceController.getKeyStoreDetails(for: profile) {
                print("P2PClient: Found existing KeyStore details for profile \(profile.name)")

                // Create Curve from raw value, handle invalid
                let curve = Curve(rawValue: keyStoreCurveRawValue) ?? .secp256r1 // Use stubbed Curve enum
                if Curve(rawValue: keyStoreCurveRawValue) == nil {
                    print("P2PClient: WARNING - Invalid stored curve raw value '\(keyStoreCurveRawValue)', using default \(Curve.secp256r1.rawValue).")
                }

                // Initialize KeyStore stub with loaded capacity and curve
                keyStore = KeyStore(curve: curve, capacity: keyStoreCapacityValue)
                print("P2PClient: Initialized KeyStore with Curve: \(curve.rawValue), Capacity: \(keyStoreCapacityValue)")

                // Deserialize the data into the KeyStore (async)
                try await keyStore?.deserialize(from: keyStoreData)

                // Access keyPairs count directly (no await)
                localKeyCount = keyStore?.keyPairs.count ?? 0
                print("P2PClient: Loaded KeyStore with \(localKeyCount) keys.")

            } else {
                // Create new KeyStore if none exists
                print("P2PClient: No existing KeyStore found, creating new one.")
                // Use the default capacity constant and a default curve
                let defaultCurve = Curve.secp256r1 // Use stubbed Curve enum
                keyStore = KeyStore(curve: defaultCurve, capacity: keyStoreCapacity) // Use default capacity and curve
                print("P2PClient: Initialized new KeyStore with Curve: \(defaultCurve.rawValue), Capacity: \(keyStoreCapacity)")

                // Generate initial keys based on the new store's capacity (async)
                let initialKeyCount = Int(Double(keyStoreCapacity) * 0.8) // 80% of capacity
                do {
                    try await keyStore?.generateAndStoreKeyPairs(count: initialKeyCount)
                } catch {
                    print("P2PClient: Error generating initial keys: \(error)")
                    keyStore = nil
                }

                print("P2PClient: Generated \(keyStore?.keyPairs.count ?? 0) initial keys.")

                // Persist the new KeyStore (async)
                await saveKeyStoreIfNeeded()
            }

        } catch {
            print("P2PClient: Error loading/creating KeyStore: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.keyManagementError("Failed to initialize KeyStore: \(error.localizedDescription)"))
            keyStore = nil
            localKeyCount = 0
            delegate?.clientDidUpdateKeyStatus(self, localKeys: 0, totalCapacity: 0)
        }
    }

    /// Saves the current KeyStore to persistence if it exists
    private func saveKeyStoreIfNeeded() async {
        guard let keyStoreToSave = keyStore else {
            print("P2PClient: No KeyStore instance to save.")
            return
        }

        do {
            // Serialize the KeyStore (async)
            let serializedData = await keyStoreToSave.serialize()
            // Access properties directly (no await)
            let curve = keyStoreToSave.curve
            let capacity = keyStoreToSave.capacity

            // Save using persistence controller (async)
            // Ensure PersistenceController.saveKeyStoreData uses the correct Curve type
            // and accepts the stubbed Curve enum or its rawValue.
            try await persistenceController.saveKeyStoreData(
                for: profile,
                serializedData: serializedData,
                keyCurve: curve,     // Pass the Curve enum directly
                capacity: capacity   // Use the actual capacity from the instance
            )
            print("P2PClient: Saved KeyStore data to persistence (Curve: \(curve.rawValue), Capacity: \(capacity))")
        } catch {
            print("P2PClient: Error saving KeyStore: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.persistenceError("Failed to save KeyStore: \(error.localizedDescription)"))
        }
    }


    /// Checks KeyStore key count and regenerates keys if needed
    func checkAndRegenerateKeys(force: Bool = false) async {
        guard let keyStore = keyStore else {
            print("P2PClient: No KeyStore available for key regeneration check.")
            return
        }

        // Access properties directly (no await)
        let actualCapacity = keyStore.capacity
        let currentKeyCount = keyStore.keyPairs.count
        let minThreshold = Int(Double(actualCapacity) * minKeyThresholdPercentage)
        let targetCount = Int(Double(actualCapacity) * targetKeyPercentage)

        print("P2PClient: Key check - Current: \(currentKeyCount), Min: \(minThreshold), Target: \(targetCount), Capacity: \(actualCapacity)")

        // Determine if regeneration is needed
        let needsRegeneration = force || currentKeyCount < minThreshold
        if !needsRegeneration {
            print("P2PClient: Key count (\(currentKeyCount)) is sufficient. No regeneration needed.")
            // Ensure delegate has up-to-date info even if no regeneration
            delegate?.clientDidUpdateKeyStatus(self, localKeys: currentKeyCount, totalCapacity: actualCapacity)
            return
        }

        // Calculate how many keys to generate
        let keysNeeded = targetCount - currentKeyCount
        // Generate 0 keys if already at or above target, unless forced
        let keysToGenerate = (force && keysNeeded <= 0) ? keyRegenerationBatchSize : min(max(0, keysNeeded), keyRegenerationBatchSize)

        if keysToGenerate <= 0 {
            print("P2PClient: Already at or above target (\(currentKeyCount)/\(targetCount)), no new keys needed.")
            // Update delegate status as a sanity check
             delegate?.clientDidUpdateKeyStatus(self, localKeys: currentKeyCount, totalCapacity: actualCapacity)
            return
        }

        // Prevent concurrent regeneration
        guard !isRegeneratingKeys else {
            print("P2PClient: Key regeneration already in progress.")
            return
        }

        // Start regeneration
        let reason = force ? "Forced" : "Below threshold (\(currentKeyCount)/\(minThreshold))"
        print("P2PClient: \(reason). Regenerating \(keysToGenerate) keys...")
        isRegeneratingKeys = true
        // Update delegate immediately to show regeneration started (optional)
        // delegate?.clientDidUpdateKeyStatus(self, localKeys: currentKeyCount, totalCapacity: actualCapacity)

        do {
            // Generate keys (async)
            try await keyStore.generateAndStoreKeyPairs(count: keysToGenerate)

            // Access keyPairs count directly (no await)
            let newCount = keyStore.keyPairs.count
            localKeyCount = newCount // Update local count tracker
            print("P2PClient: Key generation complete. New count: \(newCount)")

            // Save updated KeyStore state (async)
            await saveKeyStoreIfNeeded()

            // Notify delegate about the final key status
            delegate?.clientDidUpdateKeyStatus(self, localKeys: newCount, totalCapacity: actualCapacity)

        } catch {
            print("P2PClient: CRITICAL ERROR generating keys: \(error)")
            delegate?.clientDidEncounterError(self, error: P2PError.keyManagementError("Failed to generate keys: \(error.localizedDescription)"))
            // Update delegate with potentially unchanged count on error
            // Access keyPairs count directly (no await)
            let errorCount = keyStore.keyPairs.count
            localKeyCount = errorCount
            delegate?.clientDidUpdateKeyStatus(self, localKeys: errorCount, totalCapacity: actualCapacity)
        }

        isRegeneratingKeys = false // Reset flag after completion or error
    }

    /// Marks a key as used and removes it from the KeyStore
    private func markKeyAsUsed(_ keyID: KeyPairIdentifier) async {
        guard let keyStore = keyStore else {
            print("P2PClient: Cannot mark key \(keyID) as used, KeyStore not available.")
            return
        }

        // Prevent marking the same key multiple times if called rapidly
        guard !usedKeys.contains(keyID) else {
            print("P2PClient: Key \(keyID) already marked as used or removal pending.")
            return
        }

        print("P2PClient: Marking key as used and removing: \(keyID)")
        usedKeys.insert(keyID) // Track locally first

        do {
            // Remove the used key from KeyStore (async)
            try await keyStore.removeKeyPair(keyID: keyID)
            print("P2PClient: Successfully removed key \(keyID) from KeyStore.")
            usedKeys.remove(keyID) // Remove from local tracking set after successful removal

            // Update key count
            // Access properties directly (no await)
            localKeyCount = keyStore.keyPairs.count
            let actualCapacity = keyStore.capacity

            // Save the updated KeyStore state (async)
            await saveKeyStoreIfNeeded()

            // Notify delegate about the key status change
            delegate?.clientDidUpdateKeyStatus(self, localKeys: localKeyCount, totalCapacity: actualCapacity)

            // Check if we need to regenerate keys *after* saving and updating delegate
            let minThreshold = Int(Double(actualCapacity) * minKeyThresholdPercentage)
            if localKeyCount < minThreshold {
                 print("P2PClient: Key count \(localKeyCount) below threshold \(minThreshold) after removal, triggering regeneration check.")
                 // Run regeneration check in a separate task to avoid blocking
                 Task {
                     await checkAndRegenerateKeys()
                 }
            }

        } catch {
            // Handle potential errors during key removal
            print("P2PClient: Error removing key \(keyID) from KeyStore: \(error)")
            // Keep the key in the usedKeys set? Or remove it anyway?
            // If removal failed, the key might still be in the store.
            // For now, keep it in usedKeys to avoid retrying immediately.
            delegate?.clientDidEncounterError(self, error: P2PError.keyManagementError("Failed to remove used key \(keyID): \(error.localizedDescription)"))
            // Update delegate with potentially unchanged count
            // Access properties directly (no await)
            localKeyCount = keyStore.keyPairs.count
            let actualCapacity = keyStore.capacity
            delegate?.clientDidUpdateKeyStatus(self, localKeys: localKeyCount, totalCapacity: actualCapacity)
        }
    }


    // MARK: - Connection Management

    /// Updates the internal connection status based on the PeerDiscoveryManager's status.
    /// Called by the Combine subscriber.
    private func updateConnectionStatus(from managerStatus: ConnectionStatus) {
        let newP2PStatus: P2PConnectionStatus

        switch managerStatus {
        case .idle:
            newP2PStatus = .disconnected
        case .searching, .connecting:
            newP2PStatus = .connecting
        case .connected:
            // Get peer count from the manager
            let peerCount = peerManager.connectedPeers.count
            newP2PStatus = .connected(peerCount: peerCount)
        case let .failed(error):
            newP2PStatus = .failed(error)
        }

        // Update our internal state, which triggers the delegate via didSet
        if connectionStatus != newP2PStatus {
             print("P2PClient: Updating connection status from \(connectionStatus) to \(newP2PStatus)")
             connectionStatus = newP2PStatus
        }
    }

    /// Connects to a stream for P2P communication
    func connect(to stream: Stream) async throws {
        // Ensure stream is the actual Stream type from your project
        // and has the 'isInnerCircleStream' property.
        guard stream.isInnerCircleStream else {
            throw P2PError.invalidStream
        }

        print("P2PClient: Connecting to stream \(stream.profile.name)...")
        // Status will be updated via the Combine sink when peerManager changes state

        // Ensure KeyStore is available (loads or creates if needed)
        if keyStore == nil {
            print("P2PClient: KeyStore not loaded, initializing...")
            await loadOrCreateKeyStore()
        }
        // Check if KeyStore initialization failed
        guard keyStore != nil else {
            let error = P2PError.invalidKeyStore
            // Manually update status here as peerManager might not have failed yet
            connectionStatus = .failed(error)
            throw error
        }

        // Setup peerManager for the stream (async)
        // Assumes PeerDiscoveryManager has these methods.
        do {
            try await peerManager.setupMultipeerConnectivity(for: stream)
            try peerManager.startSearchingForPeers()
            // Status update will happen via the sink observing peerManager.$connectionStatus
            print("P2PClient: Started searching for peers on stream \(stream.profile.name)")
        } catch {
            print("P2PClient: Error setting up or starting peer discovery: \(error)")
            // Manually update status on setup/start error
            connectionStatus = .failed(error)
            // Rethrow as a specific P2PError
            throw P2PError.peerConnectionError("Failed to setup/start peer discovery: \(error.localizedDescription)")
        }
    }

    /// Disconnects from the current P2P session
    func disconnect() {
        print("P2PClient: Disconnecting...")
        peerManager.stopSearchingForPeers()
        // Status update will happen via the sink when peerManager transitions to idle/disconnected
        print("P2PClient: Disconnect requested.")
        // Optionally save KeyStore on disconnect? Deinit already handles this.
        // Task { await saveKeyStoreIfNeeded() }
    }

    // MARK: - Message Sending

    /// Encrypts and sends a message to all peers in a stream
    func sendMessage(_ content: String, toStream streamID: Data) async throws -> Data {
        // Validate state
        guard let keyStore = keyStore else {
            print("P2PClient: Cannot send message, KeyStore not available.")
            throw P2PError.invalidKeyStore
        }
        guard case .connected = connectionStatus else {
            print("P2PClient: Cannot send message, not connected to peers.")
            throw P2PError.peerConnectionError("Not connected")
        }

        // Use actual Stream and ThoughtServiceModel types from your project.
        // Ensure PersistenceController.fetchStream returns the correct Stream type.
        guard let stream = try await persistenceController.fetchStream(withPublicID: streamID) else {
            print("P2PClient: Cannot send message, invalid stream ID.")
            throw P2PError.invalidStream
        }

        print("P2PClient: Preparing to send message to stream \(stream.profile.name)")

        // Create the message payload
        let messageData = content.data(using: .utf8) ?? Data()

        // Create metadata for the message (using actual ThoughtServiceModel)
        // Ensure ThoughtServiceModel init matches this structure and MediaType enum exists.
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say, // Use actual MediaType enum
            content: messageData
        )

        // Serialize payload (assuming ThoughtServiceModel has serialize method)
        let payload: Data
        do {
             payload = try thoughtModel.serialize()
        } catch {
             print("P2PClient: Failed to serialize ThoughtServiceModel: \(error)")
             throw P2PError.encryptionError("Payload serialization failed: \(error.localizedDescription)")
        }


        // Define policy for stream-wide access
        // Ensure Data.base58EncodedString is available (e.g., via an extension).
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

        // Encrypt payload using TDFCryptoService (async)
        let nanoTDFData: Data
        let usedKeyID: KeyPairIdentifier // Variable to store the used key ID
        do {
            // Use TDFCryptoService for encryption instead of direct OpenTDFKit calls
            let cryptoService = TDFCryptoService(keyStore: keyStore)
            
            // Create TDFParams with the policy string
            let tdfParams = TDFParams(policy: policy)
            
            // Encrypt the data using our stub service
            let (encryptedData, usedKeyPairID) = try await cryptoService.encrypt(data: payload, tdfParams: tdfParams)
            
            nanoTDFData = encryptedData
            usedKeyID = usedKeyPairID

            // Mark the actual key as used (async)
            print("P2PClient: Payload encrypted using key \(usedKeyID). Marking key as used.")
            await markKeyAsUsed(usedKeyID)

        } catch {
            print("P2PClient: Encryption failed: \(error)")
            throw P2PError.encryptionError(error.localizedDescription)
        }

        // Send the encrypted message to peers (async)
        do {
            // Send the raw NanoTDF data
            print("P2PClient: Sending encrypted data (\(nanoTDFData.count) bytes) to peers...")
            // Use actual PeerDiscoveryManager and Stream types.
            // Assumes PeerDiscoveryManager.sendData exists with this signature.
            try await peerManager.sendData(nanoTDFData, toPeers: peerManager.connectedPeers, in: stream)
            print("P2PClient: Data sent successfully.")
        } catch {
            print("P2PClient: Failed to send data to peers: \(error)")
            throw P2PError.peerConnectionError("Failed to send data: \(error.localizedDescription)")
        }

        // Create and save Thought for persistence (async)
        // Use actual Thought and Thought.Metadata types from your project.
        print("P2PClient: Saving message as Thought...")
        // Ensure Thought.Metadata init matches this structure and MediaType enum exists.
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say, // Use actual MediaType enum
            createdAt: Date(),
            contributors: [] // Assuming contributors is [Contributor] or similar
        )

        // Initialize actual Thought with correct parameters.
        // Ensure Thought init matches this structure.
        let thought = Thought(
            // id: UUID(), // ID might be assigned by SwiftData or init
            nano: nanoTDFData, // Store the encrypted data
            metadata: thoughtMetadata
        )

        // Set publicID and stream properties if needed by model structure
        // thought.publicID = thoughtModel.publicID // publicID might be derived or set differently
        thought.stream = stream // Set relationship (ensure Thought has 'stream' property)

        // Assumes PersistenceController.saveThought and Stream.addThought exist.
        _ = try await persistenceController.saveThought(thought)
        stream.addThought(thought) // Assuming Stream has this method
        try await persistenceController.saveChanges()
        print("P2PClient: Thought saved successfully.")

        return nanoTDFData // Return the encrypted data
    }

    /// Sends a direct message to a specific peer
    func sendDirectMessage(_ content: String, toPeer peerProfileID: Data, inStream streamID: Data) async throws -> Data {
        // Validate state
        guard let keyStore = keyStore else {
            print("P2PClient: Cannot send direct message, KeyStore not available.")
            throw P2PError.invalidKeyStore
        }
         guard case .connected = connectionStatus else {
             print("P2PClient: Cannot send direct message, not connected to peers.")
             throw P2PError.peerConnectionError("Not connected")
         }

        // Use actual Stream and Profile types from your project.
        // Ensure PersistenceController fetch methods return correct types.
        guard let stream = try await persistenceController.fetchStream(withPublicID: streamID) else {
            print("P2PClient: Cannot send direct message, invalid stream ID.")
            throw P2PError.invalidStream
        }

        guard let peerProfile = try await persistenceController.fetchProfile(withPublicID: peerProfileID) else {
            print("P2PClient: Cannot send direct message, invalid peer profile ID.")
            throw P2PError.invalidProfile
        }

        // Get peer's MCPeerID by finding the matching profile in the peer manager
        // Use actual PeerDiscoveryManager and Profile types.
        // Assumes PeerDiscoveryManager.getProfile returns the correct Profile type.
        guard let peerMCID = peerManager.connectedPeers.first(where: { mcPeerID in
            if let profile = peerManager.getProfile(for: mcPeerID), profile.publicID == peerProfileID {
                return true
            }
            return false
        }) else {
            print("P2PClient: Cannot send direct message, peer \(peerProfile.name) not found among connected peers.")
            throw P2PError.missingPeerID
        }

        print("P2PClient: Preparing to send direct message to peer \(peerProfile.name) (\(peerMCID.displayName))")

        // Create the message payload
        let messageData = content.data(using: .utf8) ?? Data()

        // Create metadata for the message (using actual ThoughtServiceModel)
        // Ensure ThoughtServiceModel init matches this structure and MediaType enum exists.
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say, // Or a different type for DMs? Use actual MediaType
            content: messageData
        )

        // Serialize payload (assuming ThoughtServiceModel has serialize method)
         let payload: Data
         do {
              payload = try thoughtModel.serialize()
         } catch {
              print("P2PClient: Failed to serialize ThoughtServiceModel: \(error)")
              throw P2PError.encryptionError("Payload serialization failed: \(error.localizedDescription)")
         }

        // Define policy that only grants access to the specific peer
        // Ensure Data.base58EncodedString is available (e.g., via an extension).
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

        // Encrypt payload using TDFCryptoService (async)
        let nanoTDFData: Data
        let usedKeyID: UUID // Variable to store the used key ID
        do {
            // Use TDFCryptoService for encryption instead of direct OpenTDFKit calls
            let cryptoService = TDFCryptoService(keyStore: keyStore)
            
            // Create TDFParams with the policy string
            let tdfParams = TDFParams(policy: policy)
            
            // Encrypt the data using our stub service
            let (encryptedData, usedKeyPairID) = try await cryptoService.encrypt(data: payload, tdfParams: tdfParams)
            
            nanoTDFData = encryptedData
            usedKeyID = usedKeyPairID

            // Mark the actual key as used (async)
            print("P2PClient: Direct message payload encrypted using key \(usedKeyID). Marking key as used.")
            await markKeyAsUsed(usedKeyID)

        } catch {
            print("P2PClient: Direct message encryption failed: \(error)")
            throw P2PError.encryptionError(error.localizedDescription)
        }

        // Send the encrypted message directly to the peer (async)
        do {
            // Send the raw NanoTDF data directly to the specific peer
            print("P2PClient: Sending encrypted direct message (\(nanoTDFData.count) bytes) to peer \(peerMCID.displayName)...")
            // Use actual PeerDiscoveryManager and Stream types.
            // Assumes PeerDiscoveryManager.sendData exists with this signature.
            try await peerManager.sendData(nanoTDFData, toPeers: [peerMCID], in: stream)
            print("P2PClient: Direct message sent successfully.")
        } catch {
            print("P2PClient: Failed to send direct message to peer: \(error)")
            throw P2PError.peerConnectionError("Failed to send direct message: \(error.localizedDescription)")
        }

        // Create and save Thought for persistence (async)
        // Use actual Thought and Thought.Metadata types from your project.
        print("P2PClient: Saving direct message as Thought...")
        // Ensure Thought.Metadata init matches this structure and MediaType enum exists.
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: streamID,
            mediaType: .say, // Or a specific DM type? Use actual MediaType
            createdAt: Date(),
            contributors: [] // Define contributors based on actual Thought.Metadata structure
            // contributors: [peerProfile.publicID] // Example if contributors is [Data]
            // contributors: [Contributor(profileID: peerProfile.publicID)] // Example if Contributor struct exists
        )

        // Initialize actual Thought with correct parameters.
        // Ensure Thought init matches this structure.
        let thought = Thought(
            // id: UUID(), // ID might be assigned by SwiftData or init
            nano: nanoTDFData, // Store the encrypted data
            metadata: thoughtMetadata
        )

        // Set publicID and stream properties if needed
        // thought.publicID = thoughtModel.publicID // publicID might be derived or set differently
        thought.stream = stream // Set relationship (ensure Thought has 'stream' property)

        // Assumes PersistenceController.saveThought and Stream.addThought exist.
        _ = try await persistenceController.saveThought(thought)
        stream.addThought(thought) // Assuming Stream has this method
        try await persistenceController.saveChanges()
        print("P2PClient: Direct message Thought saved successfully.")

        return nanoTDFData // Return the encrypted data
    }

    // MARK: - Message Decryption

    /// Decrypts a received NanoTDF message
    func decryptMessage(_ nanoTDFData: Data) async throws -> Data {
        guard let keyStore = keyStore else {
            print("P2PClient: Cannot decrypt message, KeyStore not available.")
            throw P2PError.invalidKeyStore
        }

        print("P2PClient: Attempting to decrypt received data (\(nanoTDFData.count) bytes)...")

        let decryptedData: Data
        let usedKeyID: KeyPairIdentifier // Variable to store the used key ID
        do {
            // Use TDFCryptoService for decryption
            let cryptoService = TDFCryptoService(keyStore: keyStore)
            let (decrypted, usedKey) = try await cryptoService.decrypt(data: nanoTDFData)
            
            decryptedData = decrypted
            usedKeyID = usedKey

            // Mark the actual key as used (async)
            print("P2PClient: Message decrypted successfully using key \(usedKeyID). Marking key as used.")
            await markKeyAsUsed(usedKeyID)

            return decryptedData
        } catch {
            print("P2PClient: Decryption failed: \(error)")
            throw P2PError.decryptionError("Decryption failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Rewrap Request Handling

    /// Handles a key rewrap request for P2P key exchange (e.g., from NanoTDF header)
    /// This assumes the request contains the necessary info for KASService.
    func handleRewrapRequest(publicKey: Data, encryptedSessionKey: Data) async throws -> Data? {
        guard let keyStore = keyStore else {
            print("P2PClient: Cannot handle rewrap request, KeyStore not available.")
            throw P2PError.invalidKeyStore
        }

        print("P2PClient: Handling rewrap request...")

        let rewrappedKey: Data
        let usedKeyID: UUID // Variable to store the used key ID
        do {
            // Create a dummy KAS public key as required by API stub
            // A real implementation might get this from configuration or elsewhere.
            // Size depends on the curve (e.g., 65 bytes for uncompressed P-256)
            var dummyKasPublicKey = Data(repeating: 0, count: 65)
            dummyKasPublicKey[0] = 0x04 // Uncompressed prefix for P-256

            // Create a KAS service stub using our local KeyStore stub
            // BaseURL is likely irrelevant for local P2P rewrap but required by stub/API
            let kasService = KASService(keyStore: keyStore, baseURL: URL(string: "p2p://local")!)

            // Process the rewrap request and capture the result tuple (async)
            // Assumes KASService.processKeyAccess returns (Data, UUID)
            print("P2PClient: Processing key access via KASService stub...")
            let rewrapResult = try await kasService.processKeyAccess(
                ephemeralPublicKey: publicKey,
                encryptedKey: encryptedSessionKey,
                kasPublicKey: dummyKasPublicKey
            )
            rewrappedKey = rewrapResult.rewrappedKey // Dummy data from stub
            usedKeyID = rewrapResult.usedKeyID // Key ID used by stub

            // Mark the actual key as used (async)
            print("P2PClient: Rewrap request processed successfully using key \(usedKeyID). Marking key as used.")
            await markKeyAsUsed(usedKeyID)

            return rewrappedKey // Return the (stub) rewrapped key
        } catch {
            // If rewrap fails, we don't know which key was *supposed* to be used,
            // so we can't mark it. The error is thrown.
            print("P2PClient: Rewrap request failed: \(error)")
            // Map to P2PError.keyManagementError for consistency
            throw P2PError.keyManagementError("Rewrap request failed: \(error.localizedDescription)")
        }
    }


    // MARK: - Public Utilities

    /// Returns the current key statistics
    func getKeyStatistics() -> (current: Int, capacity: Int) {
        // Access properties directly (no await)
        let current = keyStore?.keyPairs.count ?? 0
        let capacity = keyStore?.capacity ?? 0 // Use actual capacity or 0 if no store
        print("P2PClient: getKeyStatistics - Current: \(current), Capacity: \(capacity)")
        return (current, capacity)
    }

    /// Manually triggers key regeneration
    func regenerateKeys() async {
        print("P2PClient: Manual key regeneration triggered.")
        await checkAndRegenerateKeys(force: true)
    }
}

// Extension to provide additional utility methods for the P2PClient
// Ensure these use the actual types from your project
extension P2PClient {
    /// Creates a browser view controller for manual peer selection
    func getPeerBrowser() -> MCBrowserViewController? {
        // Use actual PeerDiscoveryManager
        // Assumes PeerDiscoveryManager.getPeerBrowser exists.
        peerManager.getPeerBrowser()
    }

    /// Returns all currently connected peers
    var connectedPeers: [MCPeerID] {
        // Use actual PeerDiscoveryManager
        // Assumes PeerDiscoveryManager.connectedPeers exists.
        peerManager.connectedPeers
    }

    /// Returns profiles for connected peers
    var connectedPeerProfiles: [Profile] {
        // Use actual PeerDiscoveryManager and Profile types.
        // Assumes PeerDiscoveryManager.getProfile returns the correct Profile type.
        peerManager.connectedPeers.compactMap { peerID in
            peerManager.getProfile(for: peerID)
        }
    }
}

// MARK: - Factory Integration (No changes needed based on request)

// Assuming ViewModelFactory is defined elsewhere and provides necessary methods
// like getCurrentProfile(), getPeerDiscoveryManager(), etc.
// Also assumes Profile, PersistenceController, Stream, Thought, etc. are defined.

// Example structure - replace with your actual ViewModelFactory
/*
 class ViewModelFactory {
     // Shared storage dictionary - simplified example
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
         let clientKey = "p2pClient"
         // Check if we already have a P2PClient in the shared objects
         if let existingClient = getSharedObject(forKey: clientKey) as? P2PClient {
             print("ViewModelFactory: Returning existing P2PClient instance.")
             return existingClient
         }

         // Create a new P2PClient
         print("ViewModelFactory: Creating new P2PClient instance.")
         guard let currentProfile = getCurrentProfile() else {
             // Consider returning nil or throwing instead of fatalError in production
             fatalError("Cannot create P2PClient without a current profile")
         }

         // Assuming getPeerDiscoveryManager() and PersistenceController.shared are available
         let peerManager = getPeerDiscoveryManager()
         let persistence = PersistenceController.shared // Use actual shared instance
         let client = P2PClient(peerManager: peerManager, profile: currentProfile, persistenceController: persistence)

         // Store in shared objects for reuse
         setSharedObject(client, forKey: clientKey)
         print("ViewModelFactory: Stored new P2PClient instance.")

         return client
     }

     // Provide actual implementations for these:
     @MainActor func getCurrentProfile() -> Profile? { /* ... */ }
     @MainActor func getPeerDiscoveryManager() -> PeerDiscoveryManager { /* ... */ }
 }
 */

// Note: Ensure necessary imports like Combine are added at the top of the file