import MultipeerConnectivity
import SwiftUI
import OpenTDFKit

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
    
    func setupMultipeerConnectivity(for stream: Stream) throws {
        try implementation.setupMultipeerConnectivity(for: stream)
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
        return implementation.getBrowser()
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
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// Implementation class for MultipeerConnectivity
@MainActor
class P2PGroupViewModel: NSObject, ObservableObject {
    // MultipeerConnectivity properties
    private var mcSession: MCSession?
    private var mcPeerID: MCPeerID?
    private var mcAdvertiserAssistant: MCAdvertiserAssistant?
    private var mcBrowser: MCBrowserViewController?
    
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
                return "Peer-to-peer session not initialized"
            case .invalidStream:
                return "Not a valid InnerCircle stream"
            case .browserNotInitialized:
                return "Browser controller not initialized"
            case .keyStoreNotInitialized:
                return "KeyStore not initialized"
            case .profileNotAvailable:
                return "User profile not available"
            case .serializationFailed:
                return "Failed to serialize message data"
            case .noConnectedPeers:
                return "No connected peers available"
            }
        }
    }
    
    // KeyStore for secure key exchange
    private var keyStore: KeyStore?
    
    // MARK: - Initialization and Cleanup
    
    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
    
    private func cleanup() {
        stopSearchingForPeers()
        mcSession?.disconnect()
    }
    
    // MARK: - MultipeerConnectivity Setup
    
    /// Sets up MultipeerConnectivity for the given stream
    /// - Parameter stream: The stream to use for peer discovery
    /// - Throws: P2PError if initialization fails
    func setupMultipeerConnectivity(for stream: Stream) throws {
        guard stream.isInnerCircleStream else {
            connectionStatus = .failed(P2PError.invalidStream)
            throw P2PError.invalidStream
        }
        
        // Store the selected stream
        self.selectedStream = stream
        
        // Create a unique ID for this device using the profile name or a default
        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            connectionStatus = .failed(P2PError.profileNotAvailable)
            throw P2PError.profileNotAvailable
        }
        
        let displayName = profile.name
        mcPeerID = MCPeerID(displayName: displayName)
        
        // Initialize KeyStore with 8192 keys for secure exchange
        do {
            keyStore = try OpenTDFKit.KeyStore(curve: .secp256r1, capacity: 8192)
            print("Successfully initialized KeyStore with 8192 keys")
        } catch {
            print("Error initializing KeyStore: \(error)")
            connectionStatus = .failed(error)
            throw error
        }
        
        // Create the session with encryption
        mcSession = MCSession(peer: mcPeerID!, securityIdentity: nil, encryptionPreference: .required)
        mcSession?.delegate = self
        
        // Set up service type for InnerCircle
        let serviceType = "arkavo-circle"
        
        // Include profile info in discovery info - helps with authentication
        var discoveryInfo: [String: String] = [
            "profileID": profile.publicID.base58EncodedString,
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": "\(Date().timeIntervalSince1970)"
        ]
        
        // Create the advertiser assistant
        mcAdvertiserAssistant = MCAdvertiserAssistant(
            serviceType: serviceType, 
            discoveryInfo: discoveryInfo, 
            session: mcSession!
        )
        
        // Set up the browser controller
        mcBrowser = MCBrowserViewController(serviceType: serviceType, session: mcSession!)
        mcBrowser?.delegate = self
        
        connectionStatus = .idle
        print("MultipeerConnectivity setup complete for stream: \(stream.profile.name)")
    }
    
    /// Starts the peer discovery process
    /// - Throws: P2PError if peer discovery cannot be started
    func startSearchingForPeers() throws {
        guard let mcSession = mcSession else {
            connectionStatus = .failed(P2PError.sessionNotInitialized)
            throw P2PError.sessionNotInitialized
        }
        
        guard let selectedStream = selectedStream, selectedStream.isInnerCircleStream else {
            connectionStatus = .failed(P2PError.invalidStream)
            throw P2PError.invalidStream
        }
        
        // Start advertising our presence
        mcAdvertiserAssistant?.start()
        isSearchingForPeers = true
        connectionStatus = .searching
        
        print("Started advertising presence for peer discovery")
    }
    
    /// Stops the peer discovery process
    func stopSearchingForPeers() {
        mcAdvertiserAssistant?.stop()
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
        return mcBrowser
    }
    
    // MARK: - Data Transmission
    
    /// Sends data to all connected peers or specified peers
    /// - Parameters:
    ///   - data: The data to send
    ///   - peers: Optional specific peers to send to (defaults to all connected peers)
    /// - Throws: P2PError or session errors if sending fails
    func sendData(_ data: Data, toPeers peers: [MCPeerID]? = nil) throws {
        guard let mcSession = mcSession else {
            throw P2PError.sessionNotInitialized
        }
        
        let targetPeers = peers ?? mcSession.connectedPeers
        guard !targetPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }
        
        try mcSession.send(data, toPeers: targetPeers, with: .reliable)
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
        guard let mcSession = mcSession else {
            throw P2PError.sessionNotInitialized
        }
        
        guard let keyStore = keyStore else {
            throw P2PError.keyStoreNotInitialized
        }
        
        guard let profile = ViewModelFactory.shared.getCurrentProfile() else {
            throw P2PError.profileNotAvailable
        }
        
        // Serialize the KeyStore (in a real implementation, use the actual API)
        let keyStoreData = try serializeKeyStore(keyStore)
        
        // Create container with profile ID and keystore
        let container: [String: Any] = [
            "type": "keystore",
            "profileID": profile.publicID.base58EncodedString,
            "deviceID": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            "timestamp": Date().timeIntervalSince1970,
            "keystore": keyStoreData.base64EncodedString()
        ]
        
        // Serialize the container
        let containerData = try JSONSerialization.data(withJSONObject: container)
        
        // Send only to the specific peer
        try mcSession.send(containerData, toPeers: [peer], with: .reliable)
        print("KeyStore sent to peer: \(peer.displayName)")
    }
    
    /// Serializes a KeyStore into Data
    /// This is a placeholder implementation until the actual API is understood
    /// - Parameter keyStore: The KeyStore to serialize
    /// - Returns: Serialized KeyStore data
    /// - Throws: Serialization errors
    private func serializeKeyStore(_ keyStore: KeyStore) throws -> Data {
        // In a real implementation, use the actual KeyStore serialization API
        // For this placeholder, create a more realistic representation
        
        // Create a dictionary with keystore metadata and mock keys
        let keystoreDict: [String: Any] = [
            "version": "1.0",
            "curve": "secp256r1",
            "capacity": 8192,
            "created": Date().timeIntervalSince1970,
            "device": UIDevice.current.name,
            "keys": [
                // Add a few mock keys for better simulation
                [
                    "id": UUID().uuidString,
                    "created": Date().timeIntervalSince1970,
                    // Generate random public key data for demonstration
                    "publicKey": Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                ],
                [
                    "id": UUID().uuidString,
                    "created": Date().timeIntervalSince1970 - 86400,  // One day ago
                    "publicKey": Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
                ]
            ]
        ]
        
        return try JSONSerialization.data(withJSONObject: keystoreDict)
    }
    
    /// Deserializes KeyStore data
    /// This is a placeholder implementation until the actual API is understood
    /// - Parameter data: The serialized KeyStore data
    /// - Returns: Deserialized KeyStore
    /// - Throws: Deserialization errors
    private func deserializeKeyStore(from data: Data) throws -> KeyStore {
        // In a real implementation, use the actual KeyStore deserialization API
        
        // Parse the incoming data
        let keystoreDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        // Validate the required fields
        guard let version = keystoreDict?["version"] as? String,
              let curve = keystoreDict?["curve"] as? String,
              let capacity = keystoreDict?["capacity"] as? Int,
              let keys = keystoreDict?["keys"] as? [[String: Any]] else {
            throw NSError(domain: "KeyStoreError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid keystore format"
            ])
        }
        
        print("Deserializing KeyStore: v\(version), curve: \(curve), capacity: \(capacity), keys: \(keys.count)")
        
        // Create a new KeyStore
        // In a real implementation, we would populate it with the keys from the serialized data
        return try OpenTDFKit.KeyStore(curve: .secp256r1, capacity: capacity)
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
        
        guard let mcSession = mcSession, !mcSession.connectedPeers.isEmpty else {
            throw P2PError.noConnectedPeers
        }
        
        guard let mcPeerID = mcPeerID else {
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
            "profileID": profile.publicID.base58EncodedString
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
                   let messageID = UUID(uuidString: messageIDString) {
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
              let keystoreData = Data(base64Encoded: keystoreBase64) else {
            print("Invalid keystore message format")
            return
        }
        
        print("Received keystore from peer \(peer.displayName) with profile ID \(profileIDString)")
        
        // Process the received keystore
        Task {
            do {
                // Try to deserialize the KeyStore
                let receivedKeyStore = try deserializeKeyStore(from: keystoreData)
                
                print("Successfully processed keystore data: \(keystoreData.count) bytes")
                
                // Store the keystore or merge with existing keystore
                // This would depend on your specific implementation and security requirements
                
                // Send acknowledgement
                let profileID = ViewModelFactory.shared.getCurrentProfile()?.publicID.base58EncodedString ?? "unknown"
                let acknowledgement: [String: Any] = [
                    "type": "keystore_ack",
                    "profileID": profileID,
                    "status": "success",
                    "timestamp": Date().timeIntervalSince1970
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
                        "status": "error",
                        "error": error.localizedDescription,
                        "timestamp": Date().timeIntervalSince1970
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
        
        if status == "success" {
            print("KeyStore successfully received by peer \(peer.displayName) with profile ID \(profileID)")
        } else {
            if let errorMessage = message["error"] as? String {
                print("KeyStore error from peer \(peer.displayName): \(errorMessage)")
            } else {
                print("KeyStore error from peer \(peer.displayName)")
            }
        }
    }
    
    /// Handles text messages
    /// - Parameters:
    ///   - message: The text message
    ///   - peer: The peer that sent the message
    private func handleTextMessage(_ message: [String: Any], from peer: MCPeerID) {
        guard let sender = message["sender"] as? String,
              let messageText = message["message"] as? String,
              let timestamp = message["timestamp"] as? TimeInterval else {
            print("Invalid text message format")
            return
        }
        
        print("Received message from \(sender): \(messageText)")
        
        // Send message acknowledgement if it has an ID
        if let messageIDString = message["messageID"] as? String,
           let messageID = UUID(uuidString: messageIDString) {
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
                "timestamp": Date().timeIntervalSince1970
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
}

// MARK: - MCSessionDelegate
extension P2PGroupViewModel: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    self.peerConnectionTimes[peerID] = Date()
                    
                    // When a new peer connects, exchange keystores
                    self.sendKeyStore(to: peerID)
                    
                    // Update status if this is our first connection
                    if connectedPeers.count == 1 {
                        connectionStatus = .connected
                    }
                }
                print("Peer connected: \(peerID.displayName)")
                
            case .connecting:
                print("Peer connecting: \(peerID.displayName)")
                if connectionStatus != .connected {
                    connectionStatus = .connecting
                }
                
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.peerConnectionTimes.removeValue(forKey: peerID)
                print("Peer disconnected: \(peerID.displayName)")
                
                // Update connection status if no peers left
                if connectedPeers.isEmpty {
                    connectionStatus = isSearchingForPeers ? .searching : .idle
                }
                
            @unknown default:
                print("Unknown peer state: \(state)")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Process received data on the main actor
        Task { @MainActor in
            handleIncomingMessage(data, from: peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
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
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        Task { @MainActor in
            print("Started receiving resource \(resourceName) from \(peerID.displayName): \(progress.fractionCompleted * 100)%")
            
            // Store progress for UI updates
            resourceProgress[resourceName] = progress
        }
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        Task { @MainActor in
            // Remove from progress tracking
            resourceProgress.removeValue(forKey: resourceName)
            
            if let error = error {
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
                print("Received resource of size: \(try? Data(contentsOf: url).count ?? 0) bytes")
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
    func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
        print("Browser view controller finished")
        browserViewController.dismiss(animated: true)
    }
    
    func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
        print("Browser view controller cancelled")
        browserViewController.dismiss(animated: true)
    }
    
    func browserViewController(_ browserViewController: MCBrowserViewController, shouldPresentNearbyPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) -> Bool {
        print("Found nearby peer: \(peerID.displayName) with info: \(info ?? [:])")
        
        // Here you could implement filtering based on discovery info
        // For example, verify that the peer is part of your application
        
        if let profileID = info?["profileID"] {
            print("Peer \(peerID.displayName) has profile ID: \(profileID)")
            
            // You could check if this profile ID is in your whitelist
            // or matches some other criteria
            
            return true
        }
        
        // Allow all peers by default
        return true
    }
}

// MARK: - StreamDelegate for handling input streams
extension P2PGroupViewModel: Foundation.StreamDelegate {
    func stream(_ aStream: Foundation.Stream, handle eventCode: Foundation.Stream.Event) {
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
    
    private func readInputStream(_ stream: InputStream) {
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
            Task { @MainActor in
                handleIncomingMessage(data, from: MCPeerID(displayName: "Unknown")) // Note: in real code, you would track which peer this stream belongs to
            }
        }
    }
}