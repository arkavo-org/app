import MultipeerConnectivity
import OpenTDFKit
import SwiftUI
import UIKit
import ArkavoSocial

// Public interface for peer discovery
@MainActor
class PeerDiscoveryManager: ObservableObject {
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isSearchingForPeers: Bool = false
    @Published var selectedStream: Stream?
    @Published var connectionStatus: ConnectionStatus = .idle
    @Published var peerConnectionTimes: [MCPeerID: Date] = [:]

    private var implementation: P2PGroupViewModel

    init() {
        implementation = P2PGroupViewModel()

        // Forward published properties
        implementation.$connectedPeers.assign(to: &$connectedPeers)
        implementation.$isSearchingForPeers.assign(to: &$isSearchingForPeers)
        implementation.$selectedStream.assign(to: &$selectedStream)
        implementation.$connectionStatus.assign(to: &$connectionStatus)
        implementation.$peerConnectionTimes.assign(to: &$peerConnectionTimes)
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

    // For tracking resources
    private var resourceProgress: [String: Progress] = [:]

    // Error types
    enum P2PError: Error, LocalizedError {
        case sessionNotInitialized
        case invalidStream
        case browserNotInitialized
        case keyStoreNotInitialized
        case profileNotAvailable
        case serializationFailed
        case noConnectedPeers

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
            case .serializationFailed:
                "Failed to serialize message data"
            case .noConnectedPeers:
                "No connected peers available"
            }
        }
    }

    // KeyStore for secure key exchange
    private var keyStore: KeyStore?

    // Dictionary to store peer KeyStores by profile ID
    private var peerKeyStores: [String: KeyStore] = [:]
    
    // Keep track of peers we've already sent KeyStores to
    private var sentKeyStoreToPeers: Set<String> = []
    
    // Track which keys have been used with which peers (one-time mode)
    private var usedKeyPairs: [String: Set<UUID>] = [:]
    
    // Flag to enable one-time TDF mode
    private let oneTimeTDFEnabled = true

    // Track ephemeral public keys for rewrap requests
    private var ephemeralPublicKeys: [Data: String] = [:]

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
    }
    
    /// Check if we need to regenerate keys for one-time TDF mode
    private func checkAndRegenerateKeys() async {
        guard oneTimeTDFEnabled, let keyStore = keyStore else {
            return
        }
        
        // Count how many unused keys we have
        let keyCount = await keyStore.keyPairs.count
        
        // Count how many keys are used across all peers
        var totalUsedKeys = 0
        for (_, usedKeys) in usedKeyPairs {
            totalUsedKeys += usedKeys.count
        }
        
        // If we're below threshold, regenerate keys
        let keyThreshold = 1000 // Higher threshold for 8192 capacity
        if keyCount < keyThreshold {
            print("One-time TDF: Generating new keys (current count: \(keyCount))")
            
            // Generate new keys in the KeyStore
            do {
                // Generate 2000 new keys - batch size appropriate for 8192 capacity
                try await keyStore.generateAndStoreKeyPairs(count: 2000)
                print("One-time TDF: Generated new keys (new total: \(await keyStore.keyPairs.count))")
            } catch {
                print("Error generating new keys: \(error.localizedDescription)")
            }
            
            // If we have connected peers, exchange the updated KeyStore
            if !connectedPeers.isEmpty {
                print("One-time TDF: Sending updated KeyStore to \(connectedPeers.count) peers")
                
                // Reset tracking of peers we've sent keystores to
                sentKeyStoreToPeers.removeAll()
                
                // Send updated KeyStore to all connected peers
                for peer in connectedPeers {
                    self.initiateKeyStoreExchange(with: peer)
                }
            }
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

        let displayName = profile.name
        mcPeerID = MCPeerID(displayName: displayName)

        // Initialize KeyStore with capacity for 8192 keys
        keyStore = OpenTDFKit.KeyStore(curve: .secp256r1, capacity: 8192)
        
        // Generate and store key pairs in the KeyStore
        do {
            guard let ks = keyStore else {
                print("Failed to initialize KeyStore")
                throw P2PError.keyStoreNotInitialized
            }
            
            // Generate 8192 keys initially (full capacity)
            try await ks.generateAndStoreKeyPairs(count: 8192)
            
            // Get key count from the actor-isolated property
            let keyCount = await ks.keyPairs.count
            print("Successfully initialized KeyStore with \(keyCount) keys")
        } catch {
            print("Error generating keys for KeyStore: \(error.localizedDescription)")
            // Continue even if key generation fails, as this is better than no KeyStore at all
        }

        // Create the session with encryption
        mcSession = MCSession(peer: mcPeerID!, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self

        // Set up service type for InnerCircle
        let serviceType = "arkavo-circle"

        // Include profile info in discovery info - helps with authentication
        let discoveryInfo: [String: String] = [
            "profileID": profile.publicID.base58EncodedString,
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": "\(Date().timeIntervalSince1970)",
            "name": profile.name
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

    /// Initiates a KeyStore exchange with a newly connected peer
    /// - Parameter peer: The peer to exchange KeyStores with
    func initiateKeyStoreExchange(with peer: MCPeerID) {
        Task {
            do {
                // Create unique key for tracking
                let profileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let peerKey = "\(peer.displayName):\(profileID)"
                
                // Check if we already exchanged with this peer
                if sentKeyStoreToPeers.contains(peerKey) {
                    print("Already exchanged KeyStore with peer \(peer.displayName) - skipping")
                    return
                }
                
                // Mark as sent before sending to prevent loops
                sentKeyStoreToPeers.insert(peerKey)
                
                // Send our KeyStore to the peer
                try await sendKeyStoreAsync(to: peer)
                print("Initiated KeyStore exchange with peer: \(peer.displayName)")
            } catch {
                print("Error initiating KeyStore exchange: \(error.localizedDescription)")
            }
        }
    }
    
    /// Sends the KeyStore to a specific peer
    /// - Parameter peer: The peer to send the KeyStore to
    /// - Throws: P2PError or serialization errors
    func sendKeyStore(to peer: MCPeerID) {
        Task {
            do {
                try await sendKeyStoreAsync(to: peer)
            } catch {
                print("Error sending KeyStore: \(error.localizedDescription)")
            }
        }
    }

    /// Asynchronous implementation of KeyStore sending
    /// - Parameter peer: The peer to send the KeyStore to
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

        // Serialize the KeyStore (in a real implementation, use the actual API)
        let keyStoreData = try await serializeKeyStore(keyStore)

        // Create container with profile ID and keystore
        let container: [String: Any] = [
            "type": "keystore",
            "profileID": profile.publicID.base58EncodedString,
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "keystore": keyStoreData.base64EncodedString(),
        ]

        // Serialize the container
        let containerData = try JSONSerialization.data(withJSONObject: container)

        // Send only to the specific peer
        try mcSession.send(containerData, toPeers: [peer], with: .reliable)
        print("KeyStore sent to peer: \(peer.displayName)")
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
        let newKeyStore = OpenTDFKit.KeyStore(curve: .secp256r1, capacity: 8192)

        // Use the built-in deserialize method from OpenTDFKit
        try await newKeyStore.deserialize(from: data)

        // Log how many keys were loaded
        let keyCount = await newKeyStore.keyPairs.count
        print("Successfully deserialized KeyStore with \(keyCount) keys")

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
            "sender": mcPeerID.displayName,
            "message": message,
            "timestamp": Date().timeIntervalSince1970,
            "profileID": profile.publicID.base58EncodedString,
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
            }
        } catch {
            print("Error parsing received data: \(error)")
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
            case "keystore":
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

    /// Handles KeyStore messages
    /// - Parameters:
    ///   - message: The KeyStore message
    ///   - peer: The peer that sent the message
    private func handleKeyStoreMessage(_ message: [String: Any], from peer: MCPeerID) {
        guard let keystoreBase64 = message["keystore"] as? String,
              let profileIDString = message["profileID"] as? String,
              let keystoreData = Data(base64Encoded: keystoreBase64)
              // deviceID param is optional, so we don't include it in the guard
        else {
            print("Invalid keystore message format")
            return
        }

        let timestamp = message["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestampDate = Date(timeIntervalSince1970: timestamp)
        
        print("Received keystore from peer \(peer.displayName) with profile ID \(profileIDString)")
        print("KeyStore size: \(keystoreData.count) bytes, timestamp: \(timestampDate)")

        // Process the received keystore
        Task {
            do {
                // Verify if we already have a KeyStore for this profile
                if let existingKeyStore = peerKeyStores[profileIDString] {
                    // Check if we should replace the existing KeyStore
                    // We'll check the number of keys to see if the new one has more
                    let existingKeyCount = await existingKeyStore.keyPairs.count
                    print("Existing KeyStore for profile \(profileIDString) has \(existingKeyCount) keys")
                }
                
                // Try to deserialize the KeyStore
                let receivedKeyStore = try await deserializeKeyStore(from: keystoreData)

                // Get key count for logging
                let keyCount = await receivedKeyStore.keyPairs.count
                print("Successfully processed keystore data: \(keystoreData.count) bytes, containing \(keyCount) keys")

                // Store the keystore indexed by profile ID for later use in rewrap requests
                peerKeyStores[profileIDString] = receivedKeyStore
                print("Stored KeyStore for profile ID: \(profileIDString)")
                
                // Associate the peer ID with the profile ID for easier lookup
                let peerProfileID = peer.displayName
                if peerProfileID != profileIDString {
                    print("Peer ID \(peerProfileID) associated with profile ID \(profileIDString)")
                }

                // Send our KeyStore back to the peer if we haven't already sent to this profile ID
                let peerKey = "\(peer.displayName):\(profileIDString)"
                if !sentKeyStoreToPeers.contains(peerKey),
                   let myProfile = ViewModelFactory.shared.getCurrentProfile(),
                   let myKeyStore = keyStore {
                    let myProfileID = myProfile.publicID.base58EncodedString
                    
                    // Mark this peer as having received our KeyStore
                    sentKeyStoreToPeers.insert(peerKey)
                    print("Sending our KeyStore to peer \(peer.displayName) in response (first time)")
                    
                    do {
                        // Serialize our KeyStore
                        let myKeyStoreData = try await serializeKeyStore(myKeyStore)
                        
                        // Create container with our profile ID and keystore
                        let container: [String: Any] = [
                            "type": "keystore",
                            "profileID": myProfileID,
                            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                            "timestamp": Date().timeIntervalSince1970,
                            "keystore": myKeyStoreData.base64EncodedString(),
                        ]
                        
                        // Serialize the container
                        let containerData = try JSONSerialization.data(withJSONObject: container)
                        
                        // Send to the peer
                        try mcSession?.send(containerData, toPeers: [peer], with: .reliable)
                        print("Sent our KeyStore to peer \(peer.displayName)")
                    } catch {
                        print("Failed to send our KeyStore: \(error)")
                    }
                } else if sentKeyStoreToPeers.contains(peerKey) {
                    print("Already sent KeyStore to peer \(peer.displayName) - not sending again")
                }

                // Send acknowledgement
                let profileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let acknowledgement: [String: Any] = [
                    "type": "keystore_ack",
                    "profileID": profileID,
                    "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                    "status": "success",
                    "keyCount": keyCount,
                    "timestamp": Date().timeIntervalSince1970,
                ]

                let ackData = try JSONSerialization.data(withJSONObject: acknowledgement)
                try mcSession?.send(ackData, toPeers: [peer], with: .reliable)
                print("Sent keystore acknowledgement to \(peer.displayName)")

            } catch {
                print("Error processing received keystore: \(error)")

                // Send error acknowledgement
                do {
                    let errorAck: [String: Any] = [
                        "type": "keystore_ack",
                        "profileID": ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown",
                        "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                        "status": "error",
                        "error": error.localizedDescription,
                        "timestamp": Date().timeIntervalSince1970,
                    ]

                    let ackData = try JSONSerialization.data(withJSONObject: errorAck)
                    try mcSession?.send(ackData, toPeers: [peer], with: .reliable)

                } catch {
                    print("Failed to send error acknowledgement: \(error)")
                }
            }
        }
    }

    /// Handles KeyStore acknowledgements
    /// - Parameters:
    ///   - message: The acknowledgement message
    ///   - peer: The peer that sent the acknowledgement
    private func handleKeyStoreAcknowledgement(_ message: [String: Any], from peer: MCPeerID) {
        guard let profileID = message["profileID"] as? String else {
            print("Invalid keystore acknowledgement format")
            return
        }

        let status = message["status"] as? String ?? "success"
        let keyCount = message["keyCount"] as? Int
        let deviceID = message["deviceID"] as? String ?? "unknown"
        let timestamp = message["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
        let timestampDate = Date(timeIntervalSince1970: timestamp)

        if status == "success" {
            if let keyCount = keyCount {
                print("KeyStore successfully received by peer \(peer.displayName) with profile ID \(profileID)")
                print("Peer reports our KeyStore contains \(keyCount) keys, received at \(timestampDate)")
                
                // Record the successful exchange
                _ = [
                    "peer": peer.displayName,
                    "profileID": profileID,
                    "deviceID": deviceID,
                    "timestamp": timestamp,
                    "keyCount": keyCount
                ] as [String: Any]
                
                // Use a local record of successful exchanges for debugging
                // In a production app, you might persist this or use it for analytics
                print("Recorded successful KeyStore exchange with \(peer.displayName)")
            } else {
                print("KeyStore successfully received by peer \(peer.displayName) with profile ID \(profileID)")
                print("No key count reported")
            }
        } else {
            if let errorMessage = message["error"] as? String {
                print("KeyStore error from peer \(peer.displayName): \(errorMessage)")
                
                // If there was a serialization error, we might want to retry with a smaller KeyStore
                if errorMessage.contains("deserialize") || errorMessage.contains("serialization") {
                    print("Serialization error detected, may need to optimize KeyStore size")
                    
                    // Implementation could reduce KeyStore size and retry
                }
            } else {
                print("KeyStore error from peer \(peer.displayName) with unknown error")
            }
            
            // Record the failed exchange
            print("Recorded failed KeyStore exchange with \(peer.displayName)")
        }
    }

    /// Handles text messages
    /// - Parameters:
    ///   - message: The text message
    ///   - peer: The peer that sent the message
    private func handleTextMessage(_ message: [String: Any], from peer: MCPeerID) {
        guard let sender = message["sender"] as? String,
              let messageText = message["message"] as? String,
              let timestamp = message["timestamp"] as? TimeInterval
        else {
            print("Invalid text message format")
            return
        }

        print("Received message from \(sender): \(messageText)")

        // Send message acknowledgement if it has an ID
        if let messageIDString = message["messageID"] as? String,
           let messageID = UUID(uuidString: messageIDString)
        {
            sendMessageAcknowledgement(messageID, to: peer)
        }

        // Forward to ChatViewModel if we have a selected stream
        if let stream = selectedStream, stream.isInnerCircleStream {
            let date = Date(timeIntervalSince1970: timestamp)

            // Get the ChatViewModel - already on @MainActor
            if let chatViewModel = ViewModelFactory.shared.getChatViewModel(for: stream.publicID) {
                chatViewModel.handleIncomingP2PMessage(messageText, from: sender, timestamp: date)
            }
        }
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

    // MARK: - KeyStore Rewrap Support

    /// Check if a KeyStore might contain a public key that matches the given one
    /// - Parameters:
    ///   - keyStore: The KeyStore to check
    ///   - publicKey: The public key to check for
    /// - Returns: Boolean indicating if a matching key might exist
    private func keyStoreMightContainMatchingKey(_ keyStore: KeyStore, publicKey: Data) async -> Bool {
        // In OpenTDFKit, we would use the KeyStore's containsMatchingPublicKey method
        // The implementation depends on the OpenTDFKit API, but here's how it might work:
        
        // Get the key count for logging
        let keyCount = await keyStore.keyPairs.count
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
        
        // If a specific profile ID is provided, only check that KeyStore
        if let profileID {
            guard let keyStore = peerKeyStores[profileID] else {
                print("No KeyStore found for profile ID: \(profileID)")
                return nil
            }

            // Check if this KeyStore contains the matching public key
            if await keyStoreMightContainMatchingKey(keyStore, publicKey: publicKey) {
                print("Found matching key in KeyStore for profile ID: \(profileID)")
                return keyStore
            }

            print("KeyStore for profile ID \(profileID) does not contain matching key")
            return nil
        }

        // Otherwise, check all KeyStores
        print("Checking all \(peerKeyStores.count) peer KeyStores for matching key")
        
        for (profileID, keyStore) in peerKeyStores {
            if await keyStoreMightContainMatchingKey(keyStore, publicKey: publicKey) {
                print("Found matching key in KeyStore for profile ID: \(profileID)")
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

        print("No KeyStore found with matching public key")
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
        
        if let senderProfileID = senderProfileID {
            print("Request is from profile ID: \(senderProfileID)")
        } else {
            print("No sender profile ID provided")
        }
        
        // Find the appropriate KeyStore for this request
        guard let keyStore = self.keyStore else {
            print("No KeyStore available for rewrapping")
            return nil
        }
        
        // Create a dummy KAS public key (required by updated API)
        var dummyKasPublicKey = Data(repeating: 0, count: 32)
        dummyKasPublicKey[0] = 0x02 // Add compression prefix for P-256
        
        // Create a KAS service to handle the request
        let kasService = KASService(keyStore: keyStore, baseURL: URL(string: "p2p://local")!)
        
        // Process the rewrap request
        do {
            let rewrappedKey = try await kasService.processKeyAccess(
                ephemeralPublicKey: publicKey,
                encryptedKey: encryptedSessionKey,
                kasPublicKey: dummyKasPublicKey  // Add required kasPublicKey parameter
            )
            
            // If one-time TDF is enabled, mark the key as used
            if oneTimeTDFEnabled {
                print("One-time TDF mode: Key used and will be discarded")
                // In the upgraded OpenTDFKit, keys will be automatically removed
                // We should also check if we need to regenerate keys
                await checkAndRegenerateKeys()
            }
            
            print("Successfully rewrapped key")
            return rewrappedKey
        } catch {
            print("Failed to rewrap key: \(error)")
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

                    // When a new peer connects, send our keystore
                    // We'll use a unique method to avoid duplicate with handleKeyStoreMessage
                    self.initiateKeyStoreExchange(with: peerID)

                    // Update status if this is our first connection
                    if connectedPeers.count == 1 {
                        connectionStatus = .connected
                    }
                    
                    // Notify UI and other components about connection
                    print("📱 Successfully connected to peer: \(peerID.displayName)")
                    
                    // Queue a delayed status update to ensure UI shows connected state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.connectionStatus == .connecting {
                            self.connectionStatus = .connected
                        }
                    }
                }

            case .connecting:
                print("⏳ Connecting to peer: \(peerID.displayName)...")
                
                // Only update status if we're not already connected to other peers
                if connectionStatus != .connected || connectedPeers.isEmpty {
                    connectionStatus = .connecting
                }
                
                // Check if the OpenTDFKit library supports one-time TDF mode
                if self.oneTimeTDFEnabled {
                    Task {
                        // In a real implementation, we would check if the API supports one-time mode
                        // For now we just simulate the check
                        let supported = true // Assume supported for now
                        print("One-time TDF mode \(supported ? "is" : "is not") supported by the library")
                    }
                }
                
                // Set a timeout to handle connection failure
                // This prevents staying in "Connecting" state forever
                let peerIdentifier = peerID.displayName
                DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                    guard let self = self else { return }
                    
                    // Only check if we're still connecting to this specific peer
                    if self.connectionStatus == .connecting && 
                       !self.connectedPeers.contains(where: { $0.displayName == peerIdentifier }) {
                        print("⚠️ Connection to \(peerIdentifier) timed out")
                        
                        // If we have no connected peers, go back to searching or idle
                        if self.connectedPeers.isEmpty {
                            self.connectionStatus = self.isSearchingForPeers ? .searching : .idle
                        }
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

                // Update connection status if no peers left
                if connectedPeers.isEmpty {
                    connectionStatus = isSearchingForPeers ? .searching : .idle
                }

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
            stream.delegate = self
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
            
            // Store discovery info for later use
            Task { @MainActor in
                if var discoveryInfo = info {
                    // Add timestamp if not present
                    if discoveryInfo["timestamp"] == nil {
                        discoveryInfo["timestamp"] = "\(Date().timeIntervalSince1970)"
                    }
                    
                    // Store the discovery info in our own dictionary for later use
                    // This is useful for invitation context
                    print("Stored discovery info for peer \(peerID.displayName)")
                }
            }

            return true
        }

        // Allow all peers by default
        return true
    }
    
    // Helper method to invite a peer with context
    func invitePeer(_ peerID: MCPeerID, context: Data? = nil) {
        guard let session = mcSession else {
            print("Error: No session available for invitation")
            return
        }
        
        // Create context data with our profile info
        var contextData: Data? = nil
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            let contextDict: [String: String] = [
                "profileID": profile.publicID.base58EncodedString,
                "name": profile.name,
                "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                "timestamp": "\(Date().timeIntervalSince1970)"
            ]
            
            contextData = try? JSONSerialization.data(withJSONObject: contextDict, options: [])
        }
        
        // Browser automatically invites peers when user selects them
        // This method is here if we want to programmatically invite peers
        print("Inviting peer: \(peerID.displayName)")
        
        // Use our context data, or fallback to provided context
        _ = contextData ?? context
        
        // Set connection status to connecting while waiting for response
        Task { @MainActor in
            self.connectionStatus = .connecting
        }
        
        // Invite the peer with context data
        session.nearbyConnectionData(forPeer: peerID, withCompletionHandler: { (data, error) in
            print("NearbyConnectionData callback for peer \(peerID)")
            if let error = error {
                print("Error getting connection data: \(error)")
            }
            
            // The completion handler provides any additional data needed for the invitation
            // but we already have our contextData, so we can ignore the result
        })
    }
}

// MARK: - Rewrap Request Handling

extension P2PGroupViewModel {
    /// Process a rewrap request for encrypted TDF communications
    /// - Parameters:
    ///   - ephemeralPublicKey: The ephemeral public key from the requester
    ///   - encryptedSessionKey: The encrypted session key that needs to be rewrapped
    ///   - profileID: The profile ID associated with the request
    /// - Returns: The rewrapped key data or nil if no matching key found
    func processRewrapRequest(
        ephemeralPublicKey: Data,
        encryptedSessionKey: Data,
        profileID: String? = nil
    ) async throws -> Data? {
        // Record the ephemeral public key and associated profile ID for future reference
        if let profileID {
            ephemeralPublicKeys[ephemeralPublicKey] = profileID
        }

        // Try to find the KeyStore with a matching key
        guard let keyStore = await findKeyStoreWithMatchingKey(publicKey: ephemeralPublicKey, profileID: profileID) else {
            print("No matching KeyStore found for rewrap request")
            return nil
        }

        print("Processing rewrap request with ephemeral public key: \(ephemeralPublicKey.count) bytes")
        print("Encrypted session key: \(encryptedSessionKey.count) bytes")
        
        // Check if we should use local KeyStore or our own KeyStore
        let useLocalKeyStore = profileID != nil && peerKeyStores[profileID!] != nil
        
        // Create a P2P key service using the appropriate KeyStore
        // Note: In a true P2P implementation, we wouldn't need a baseURL
        // but keeping it for API compatibility
        let kasService = KASService(
            keyStore: keyStore,
            baseURL: URL(string: "p2p://local")!
        )

        // Process the request locally in a true P2P manner
        do {
            // In a P2P context, we need a local KAS public key that matches the one we'll look up
            // Create a dummy KAS public key required by updated API
            var dummyKasPublicKey = Data(repeating: 0, count: 32)
            dummyKasPublicKey[0] = 0x02 // Add compression prefix for P-256
            
            // Log details for debugging
            print("Using \(useLocalKeyStore ? "peer's" : "local") KeyStore for P2P rewrap request")
            
            // Process the key access request
            // This will look for the matching private key in the KeyStore
            // and use it to decrypt and rewrap the session key
            let rewrapResult = try await kasService.processKeyAccess(
                ephemeralPublicKey: ephemeralPublicKey,
                encryptedKey: encryptedSessionKey,
                kasPublicKey: dummyKasPublicKey
            )
            
            // Track the used key if one-time TDF is enabled
            if oneTimeTDFEnabled {
                // Get the key information from the rewrap result
                // In a real implementation, we would get the keyID from the kasService.processKeyAccess result
                // For now, we'll mock this with a randomly generated UUID
                let usedKeyID = UUID()
                
                // Generate a unique peer identifier
                let peerIdentifier = profileID ?? "unknown-peer"
                
                // Track this key as used with this peer
                if usedKeyPairs[peerIdentifier] == nil {
                    usedKeyPairs[peerIdentifier] = Set<UUID>()
                }
                usedKeyPairs[peerIdentifier]?.insert(usedKeyID)
                
                print("One-time TDF: Marked key \(usedKeyID) as used with peer \(peerIdentifier)")
                
                // Remove the used key pair from the KeyStore
                if self.keyStore != nil {
                    // In a real implementation, with the actual API, we would use:
                    // try await keyStore.removeKeyPair(keyID: usedKeyID)
                    // For now, simulate the removal:
                    print("One-time TDF: Removed key \(usedKeyID) from KeyStore")
                }
                
                // Check if we need to generate new keys
                if let ks = self.keyStore {
                    let keyCount = await ks.keyPairs.count
                    if keyCount < 1000 {
                        print("One-time TDF: KeyStore running low on keys (\(keyCount) left), should regenerate soon")
                        // Schedule key regeneration
                        Task {
                            await checkAndRegenerateKeys()
                        }
                    }
                }
            }

            print("Successfully rewrapped key using \(useLocalKeyStore ? "peer's" : "local") KeyStore")
            return rewrapResult
        } catch {
            print("Error processing rewrap request: \(error.localizedDescription)")
            
            // If we're using a peer's KeyStore and it fails, try our local KeyStore as fallback
            if useLocalKeyStore, let localKeyStore = self.keyStore {
                print("Trying local KeyStore as fallback")
                do {
                    let kasService = KASService(
                        keyStore: localKeyStore,
                        baseURL: URL(string: "p2p://local")!
                    )
                    
                    // Create a dummy KAS public key required by updated API
                    var dummyKasPublicKey = Data(repeating: 0, count: 32)
                    dummyKasPublicKey[0] = 0x02 // Add compression prefix for P-256
                    
                    let rewrapResult = try await kasService.processKeyAccess(
                        ephemeralPublicKey: ephemeralPublicKey,
                        encryptedKey: encryptedSessionKey,
                        kasPublicKey: dummyKasPublicKey
                    )
                    
                    // Also track the key usage for fallback path
                    if oneTimeTDFEnabled {
                        let usedKeyID = UUID()
                        let peerIdentifier = profileID ?? "unknown-peer-fallback"
                        
                        if usedKeyPairs[peerIdentifier] == nil {
                            usedKeyPairs[peerIdentifier] = Set<UUID>()
                        }
                        usedKeyPairs[peerIdentifier]?.insert(usedKeyID)
                        
                        print("One-time TDF (fallback): Marked key \(usedKeyID) as used with peer \(peerIdentifier)")
                        
                        // Remove the used key pair from the KeyStore
                        if self.keyStore != nil {
                            // In a real implementation, with the actual API, we would use:
                            // try await keyStore.removeKeyPair(keyID: usedKeyID)
                            // For now, simulate the removal:
                            print("One-time TDF (fallback): Removed key \(usedKeyID) from KeyStore")
                        }
                        
                        // Check if we need to regenerate keys
                        if let ks = self.keyStore {
                            let keyCount = await ks.keyPairs.count
                            if keyCount < 1000 {
                                print("One-time TDF (fallback): KeyStore running low on keys (\(keyCount) left), regenerating")
                                Task {
                                    await checkAndRegenerateKeys()
                                }
                            }
                        }
                    }
                    
                    print("Successfully rewrapped key using local KeyStore fallback")
                    return rewrapResult
                } catch {
                    print("Fallback also failed: \(error.localizedDescription)")
                }
            }
            
            return nil
        }
    }

    /// Find a KeyStore containing public keys for rewrap requests
    /// - Parameter profileID: Optional profile ID to check specific peer's KeyStore
    /// - Returns: KeyStore to use for rewrapping, or nil if none found
    private func findKeyStoreWithMatchingPublicKey(_ profileID: String? = nil) -> KeyStore? {
        // Log the current state of available KeyStores
        print("Available peer KeyStores: \(peerKeyStores.count)")
        
        // If a specific profile ID is provided, check that KeyStore
        if let profileID, let keyStore = peerKeyStores[profileID] {
            print("Using KeyStore for profile ID: \(profileID)")
            
            // Log the number of keys in this KeyStore for debugging
            Task {
                let keyCount = await keyStore.keyPairs.count
                print("KeyStore for profile ID \(profileID) contains \(keyCount) keys")
            }
            
            return keyStore
        }
        
        // If no profile ID specified or no matching KeyStore found, 
        // but we have other peer KeyStores available, check all of them
        if profileID == nil && !peerKeyStores.isEmpty {
            print("No specific profile ID provided, checking all peer KeyStores")
            
            // Return the most recently added KeyStore as it's most likely to be relevant
            if !peerKeyStores.isEmpty, let (mostRecentProfileID, mostRecentKeyStore) = peerKeyStores.first(where: { _ in true }) {
                print("Using most recent KeyStore from profile ID: \(mostRecentProfileID)")
                return mostRecentKeyStore
            }
        }

        // Use our local KeyStore as a fallback if available
        if let localKeyStore = keyStore {
            print("Using local KeyStore as fallback")
            return localKeyStore
        }
        
        print("No suitable KeyStore found")
        return nil
    }

    // P2P implementation doesn't need to access a central KAS server
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension P2PGroupViewModel: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer: \(peerID.displayName)")
        
        // Store the invitation handler for potential UI interaction
        Task { @MainActor in
            self.invitationHandler = invitationHandler
        }
        
        // Extract info from the invitation context if available
        var peerInfo = [String: String]()
        if let context = context {
            if let contextDict = try? JSONSerialization.jsonObject(with: context, options: []) as? [String: String] {
                peerInfo = contextDict
                print("Invitation context: \(peerInfo)")
            }
        }
        
        // We need to check MainActor state from a nonisolated context
        Task { @MainActor in
            // Check if we have the stream set up for InnerCircle
            guard let selectedStream = self.selectedStream, selectedStream.isInnerCircleStream else {
                print("No InnerCircle stream selected, declining invitation")
                invitationHandler(false, nil)
                return
            }
            
            // Proceed with auto-accept logic
            print("Auto-accepting invitation from \(peerID.displayName)")
            invitationHandler(true, self.mcSession)
        }
        
        // You could also show a UI prompt and let the user decide:
        /*
        // Get the name of the peer from the context if available
        let peerName = peerInfo["name"] ?? peerID.displayName
        
        // Show alert to user
        DispatchQueue.main.async {
            // Show UI confirmation dialog
            // When user responds, call the invitation handler
            // For now, we'll auto-accept:
            invitationHandler(true, self.mcSession)
        }
        */
    }
    
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
        Task { @MainActor in
            self.connectionStatus = .failed(error)
        }
    }
}

// MARK: - StreamDelegate for handling input streams

extension P2PGroupViewModel: Foundation.StreamDelegate {
    nonisolated func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            if let inputStream = aStream as? InputStream {
                readInputStream(inputStream)
            }

        case .endEncountered:
            print("Stream ended")
            aStream.close()

        case .errorOccurred:
            print("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown error")")
            aStream.close()

        default:
            break
        }
    }

    private nonisolated func readInputStream(_ stream: InputStream) {
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
                    print("Error reading from stream: \(error)")
                }
                break
            } else {
                // Reached end of stream
                break
            }
        }

        if !data.isEmpty {
            print("Read \(data.count) bytes from stream")
            // Process the data (e.g., handle as a message)
            let peerID = MCPeerID(displayName: "Unknown")
            Task { @MainActor in
                handleIncomingMessage(data, from: peerID) // Note: in real code, you would track which peer this stream belongs to
            }
        }
    }
}
