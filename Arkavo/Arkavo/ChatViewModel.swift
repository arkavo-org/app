import ArkavoSocial
import CryptoKit
import FlatBuffers
import MultipeerConnectivity
import OpenTDFKit
import SwiftData
import SwiftUI

// Helper extension to convert Swift MediaType to FlatBuffers Arkavo_MediaType
// Assuming MediaType enum cases match Arkavo_MediaType cases. Adjust if needed.
// REMOVED MediaType extension as requested

@MainActor
class ChatViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    let streamPublicID: Data
    @Published var messages: [ChatMessage] = []
    private var notificationObservers: [NSObjectProtocol] = []

    // Access to PeerDiscoveryManager (assuming it's available via ViewModelFactory)
    private var peerManager: PeerDiscoveryManager {
        ViewModelFactory.shared.getPeerDiscoveryManager()
    }

    // Access to P2PClient for peer-to-peer operations
    private var p2pClient: P2PClient? {
        ViewModelFactory.shared.getP2PClient()
    }

    init(client: ArkavoClient, account: Account, profile: Profile, streamPublicID: Data) {
        self.client = client
        self.account = account
        self.profile = profile
        self.streamPublicID = streamPublicID

        setupNotifications()

        // Load existing thoughts for this stream
        Task {
            await loadExistingMessages()

            // Set up P2PClient delegate if this is for a P2P stream
            if let p2pClient = self.p2pClient {
                let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID)
                if stream?.isInnerCircleStream == true {
                    print("ChatViewModel Setting up as P2PClient delegate for P2P stream")
                    p2pClient.delegate = self
                }
            }
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Message Loading and Handling

    private func loadExistingMessages() async {
        do {
            let thoughts = try await PersistenceController.shared.fetchThoughtsForStream(withPublicID: streamPublicID)
            print("ChatViewModel: Loading \(thoughts.count) existing thoughts for stream \(streamPublicID.base58EncodedString)")

            for thought in thoughts {
                // All thoughts are assumed to have NanoTDF payload in 'nano'
                // Send the raw nano data to the client's decryption mechanism
                // The result will be handled by the .messageDecrypted notification observer
                print("ChatViewModel: Attempting decryption for thought \(thought.publicID.base58EncodedString)")
                // Use a non-throwing try? as failure to decrypt one message shouldn't stop others.
                try? await client.sendMessage(thought.nano)
            }

            // Sorting will happen as messages are added by the notification handler
            // We might want an initial sort here if messages appear out of order initially
            await MainActor.run {
                messages.sort { $0.timestamp < $1.timestamp }
            }
        } catch {
            print("❌ ChatViewModel: Error loading existing messages: \(error)")
        }
    }

    func setupNotifications() {
        print("ChatViewModel: setupNotifications")
        // Clean up any existing observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        // Observer for decrypted messages (from client/websocket or local decryption)
        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, // Ensure self is valid
                  let data = notification.userInfo?["data"] as? Data,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy else { return }

            // Check if the decrypted message belongs to this stream context
            if let thoughtModel = try? ThoughtServiceModel.deserialize(from: data),
               thoughtModel.streamPublicID == self.streamPublicID
            {
                print("ChatViewModel: Received decrypted message notification for this stream.")
                Task { @MainActor [weak self] in
                    await self?.handleDecryptedThought(payload: data, policy: policy)
                }
            } else {
//                 print("ChatViewModel: Ignoring decrypted message for different stream.")
            }
        }
        notificationObservers.append(messageObserver)

        // Observer for P2P messages received directly via PeerDiscoveryManager
        let p2pMessageObserver = NotificationCenter.default.addObserver(
            forName: .p2pMessageReceived, // Assuming this notification carries raw Data
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let notificationStreamID = notification.userInfo?["streamID"] as? Data,
                  streamPublicID == notificationStreamID,
                  let nanoTDFData = notification.userInfo?["data"] as? Data, // Expecting encrypted NanoTDF data
                  let senderPeerID = notification.userInfo?["senderPeerID"] as? MCPeerID // Need the sender PeerID
            else {
                // print("ChatViewModel: Ignoring P2P notification (mismatched stream or missing data).")
                return
            }

            print("ChatViewModel: Received P2P NanoTDF notification for stream \(notificationStreamID.base58EncodedString)")

            Task { @MainActor [weak self] in
                // Find sender profile ID if possible (may require lookup based on MCPeerID)
                // This part depends on how PeerDiscoveryManager maps MCPeerIDs to Profiles/PublicIDs
                // FIX 1: Moved peerManager access inside Task @MainActor block
                guard let self else { return }
                let senderProfile = peerManager.getProfile(for: senderPeerID)
                let senderProfileID = senderProfile?.publicID ?? Data() // Use empty Data if profile not found

                // Decrypt and handle the incoming P2P message
                await handleIncomingP2PData(nanoTDFData, from: senderPeerID.displayName, profileID: senderProfileID)
            }
        }
        notificationObservers.append(p2pMessageObserver)

        // Note: Removed handleP2PMessageReceived as its role seemed overlapping or unclear.
        // Incoming P2P data is handled by .p2pMessageReceived observer.
        // Stored P2P messages are handled by loadExistingMessages -> client.sendMessage -> .messageDecrypted observer.
    }

    @MainActor
    func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy) async {
        print("ChatViewModel: Handling decrypted thought...")
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)

            // Double-check if it belongs to this stream (already checked in notification handler, but good practice)
            guard thoughtModel.streamPublicID == streamPublicID else {
                print("❌ ChatViewModel: Decrypted thought belongs to a different stream. Ignoring.")
                return
            }

            // Ensure it's a message type we display in chat
            guard thoughtModel.mediaType == .say else {
                print("ChatViewModel: Ignoring decrypted thought with non-chat mediaType: \(thoughtModel.mediaType)")
                return
            }

            let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)
            let timestamp = Date() // TODO: Get timestamp from policy/metadata if available, otherwise use current time

            let message = ChatMessage(
                id: thoughtModel.publicID.base58EncodedString, // Use thought public ID as message ID
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: formatUsername(publicID: thoughtModel.creatorPublicID),
                content: displayContent,
                timestamp: timestamp, // Adjust if timestamp is available elsewhere
                attachments: [],
                reactions: [],
                isPinned: false,
                publicID: thoughtModel.publicID,
                creatorPublicID: thoughtModel.creatorPublicID,
                mediaType: thoughtModel.mediaType,
                rawContent: thoughtModel.content // Store original decrypted content
            )

            // Avoid adding duplicates
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                messages.sort { $0.timestamp < $1.timestamp } // Keep sorted
                print("ChatViewModel: Added message ID \(message.id) to UI. Total: \(messages.count)")
            } else {
                print("ChatViewModel: Message ID \(message.id) already exists. Ignoring duplicate.")
            }

        } catch {
            print("❌ ChatViewModel: Error handling decrypted thought: \(error)")
        }
    }

    func processContent(_ content: Data, mediaType: MediaType) -> String {
        switch mediaType {
        case .text, .post, .say:
            String(data: content, encoding: .utf8) ?? "[Invalid text content]"
        // Add cases for other media types if they should be displayed differently in chat
        default:
            "[\(mediaType.rawValue) content]" // Generic placeholder
        }
    }

    func formatUsername(publicID: Data) -> String {
        // TODO: Implement fetching actual username from profile/contacts if possible
        let shortID = publicID.prefix(6).base58EncodedString
        return "User-\(shortID)"
    }

    enum ChatError: Error {
        case noProfile
        case serializationError
        case encryptionError(Error)
        case decryptionError(Error)
        case persistenceError(Error)
        case peerSendError(Error)
        case missingPeerID
        case missingTDFClient
        case missingPublicID // Added for clarity
    }

    // MARK: - Message Sending

    func sendMessage(content: String) async throws {
        print("ChatViewModel: sendMessage called.")
        guard !content.isEmpty else { return }

        // Check if this is a direct message chat
        if let directProfile = directMessageProfile {
            print("ChatViewModel: Sending as direct message to \(directProfile.name)")
            try await sendDirectMessageToPeer(directProfile, content: content)
            return
        }

        // Check if this is a general InnerCircle (P2P) stream
        if let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID),
           stream.isInnerCircleStream
        {
            print("ChatViewModel: Sending as general P2P message in stream \(stream.publicID)")
            try await sendP2PMessage(content, stream: stream)
            return
        }

        // Otherwise, send as a regular (non-P2P) message via the client/websocket
        print("ChatViewModel: Sending as regular message via client.")
        try await sendRegularMessage(content: content)
    }

    /// Sends a regular message (non-P2P) through the ArkavoClient (websocket)
    private func sendRegularMessage(content: String) async throws {
        let messageData = content.data(using: .utf8) ?? Data()

        // **FIX:** Generate a unique public ID for the thought
        let newThoughtPublicID = UUID().uuidStringData

        // Create thought service model
        var thoughtModel = ThoughtServiceModel( // Make mutable to set publicID
            creatorPublicID: profile.publicID,
            streamPublicID: streamPublicID,
            mediaType: .say, // Chat messages use .say
            content: messageData
        )
        // **FIX:** Assign the generated public ID to the model
        thoughtModel.publicID = newThoughtPublicID

        // Create FlatBuffers policy (now uses the correct publicID from thoughtModel)
        let policyData = try createPolicyData(for: thoughtModel)

        // Serialize payload
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData
        )

        // Create and save the Thought locally, passing the generated publicID
        let thought = try await createAndSaveThought(
            nanoData: nanoData,
            thoughtModel: thoughtModel,
            publicID: newThoughtPublicID // **FIX:** Pass the ID
        )

        // Add message to local UI immediately
        addLocalChatMessage(content: content, thoughtPublicID: thought.publicID, timestamp: thought.metadata.createdAt)
    }

    // MARK: - P2P Messaging

    /// The profile of the direct message recipient, if this is a direct chat
    var directMessageProfile: Profile? {
        let sharedState = ViewModelFactory.shared.getSharedState()
        return sharedState.getState(forKey: "selectedDirectMessageProfile") as? Profile
    }

    /// Whether this is a direct message conversation
    var isDirectMessageChat: Bool {
        directMessageProfile != nil
    }

    /// Get display name for recipient if in direct message mode
    var directMessageRecipientName: String {
        directMessageProfile?.name ?? "Peer"
    }

    /// Send a P2P message to all peers in an InnerCircle stream
    func sendP2PMessage(_ content: String, stream: Stream) async throws {
        print("ChatViewModel: Preparing P2P message for stream \(stream.publicID)")

        guard let p2pClient else {
            throw ChatError.missingTDFClient
        }

        // Use P2PClient to handle the message sending, encryption, and persistence
        // FIX 2: Discard unused return value
        _ = try await p2pClient.sendMessage(content, toStream: stream.publicID)
        print("ChatViewModel: Sent P2P message via P2PClient for stream \(stream.publicID)")

        // This is for immediate UI feedback - the message is already persisted by P2PClient
        // We use a random UUID here just for display purposes since the actual ID is handled by P2PClient
        addLocalChatMessage(content: content, thoughtPublicID: UUID().uuidStringData, timestamp: Date(), isP2P: true)
    }

    /// Send a message directly to a specific peer by their profile
    func sendDirectMessageToPeer(_ peerProfile: Profile, content: String) async throws {
        print("ChatViewModel: Preparing direct message to \(peerProfile.name): \(content)")

        guard let p2pClient else {
            throw ChatError.missingTDFClient
        }

        // Use P2PClient to handle direct message sending, encryption, and persistence
        // FIX 2: Discard unused return value
        _ = try await p2pClient.sendDirectMessage(
            content,
            toPeer: peerProfile.publicID,
            inStream: streamPublicID
        )
        print("ChatViewModel: Sent direct message via P2PClient to \(peerProfile.name)")

        // This is for immediate UI feedback - the message is already persisted by P2PClient
        addLocalChatMessage(content: content, thoughtPublicID: UUID().uuidStringData, timestamp: Date(), isP2P: true)
    }

    /// Handles incoming raw P2P data (NanoTDF) received from PeerDiscoveryManager
    func handleIncomingP2PData(_ nanoTDFData: Data, from peerDisplayName: String, profileID: Data) async {
        print("ChatViewModel: Handling incoming P2P NanoTDF data from \(peerDisplayName), size: \(nanoTDFData.count)")

        guard let p2pClient else {
            print("❌ ChatViewModel: P2PClient not available for decryption")
            return
        }

        do {
            // 1. Decrypt the NanoTDF data using P2PClient
            let decryptedPayload = try await p2pClient.decryptMessage(nanoTDFData)
            print("ChatViewModel: Successfully decrypted incoming P2P data.")

            // 2. Deserialize the payload into ThoughtServiceModel
            let thoughtModel = try ThoughtServiceModel.deserialize(from: decryptedPayload)
            print("ChatViewModel: Deserialized incoming P2P thought model, creator: \(thoughtModel.creatorPublicID.base58EncodedString)")

            // 3. Ensure it's a relevant message type
            guard thoughtModel.mediaType == .say else {
                print("ChatViewModel: Ignoring incoming P2P data with non-chat mediaType: \(thoughtModel.mediaType)")
                return
            }

            // **FIX:** Ensure thoughtModel has a publicID before proceeding
            guard !thoughtModel.publicID.isEmpty else {
                print("❌ ChatViewModel: Incoming P2P thought model missing publicID.")
                throw ChatError.missingPublicID
            }

            // 4. Create and display the ChatMessage
            let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)
            let timestamp = Date() // TODO: Extract timestamp if included in thoughtModel or metadata

            // Determine username: Use profileID lookup if possible, otherwise fallback to peerDisplayName
            // FIX 3: Changed check from `profileID != nil` to `!profileID.isEmpty`
            let username = !profileID.isEmpty ? formatUsername(publicID: thoughtModel.creatorPublicID) : peerDisplayName

            let message = ChatMessage(
                id: thoughtModel.publicID.base58EncodedString, // Use thought public ID
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: username + " (P2P)", // Indicate P2P origin
                content: displayContent,
                timestamp: timestamp,
                attachments: [],
                reactions: [],
                isPinned: false,
                publicID: thoughtModel.publicID,
                creatorPublicID: thoughtModel.creatorPublicID,
                mediaType: thoughtModel.mediaType,
                rawContent: thoughtModel.content
            )

            // 5. Add to UI if not already present
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                messages.sort { $0.timestamp < $1.timestamp } // Keep sorted
                print("ChatViewModel: Added incoming P2P message ID \(message.id) to UI. Total: \(messages.count)")
            } else {
                print("ChatViewModel: Incoming P2P message ID \(message.id) already exists. Ignoring duplicate.")
            }

        } catch {
            print("❌ ChatViewModel: Failed to handle incoming P2P data: \(error)")
            // Optionally notify the user or log more details
        }
    }

    // MARK: - UI Helpers

    /// Adds a chat message to the local UI, typically after sending.
    private func addLocalChatMessage(content: String, thoughtPublicID: Data, timestamp: Date, isP2P: Bool = false) {
        // **FIX:** Ensure thoughtPublicID is not empty before creating message
        guard !thoughtPublicID.isEmpty else {
            print("❌ ChatViewModel: Attempted to add local chat message with empty publicID.")
            return
        }

        let message = ChatMessage(
            id: thoughtPublicID.base58EncodedString, // Use thought public ID as message ID
            userId: profile.publicID.base58EncodedString,
            username: "Me" + (isP2P ? " (P2P)" : ""),
            content: content,
            timestamp: timestamp,
            attachments: [],
            reactions: [],
            isPinned: false,
            publicID: thoughtPublicID,
            creatorPublicID: profile.publicID,
            mediaType: .say,
            rawContent: content.data(using: .utf8) ?? Data() // Store raw *unencrypted* content for local display
        )

        // Avoid adding duplicates if somehow already added
        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
            messages.sort { $0.timestamp < $1.timestamp } // Keep sorted
            print("ChatViewModel: Added local message ID \(message.id) to UI. Total: \(messages.count)")
        }
    }

    // MARK: - Cryptography Helpers

    // Note: These methods are kept for non-P2P message handling that still uses ArkavoClient
    // For P2P communication, we use P2PClient instead

    /// Encrypts payload data for non-P2P communication using ArkavoClient
    private func encryptPayload(_ payload: Data, withPolicy policy: String) async throws -> Data {
        // Use ArkavoClient for non-P2P encryption
        do {
            let nanoTDFData = try await client.encryptAndSendPayload(payload: payload, policyData: policy.data(using: .utf8) ?? Data())
            return nanoTDFData
        } catch {
            print("❌ ChatViewModel: NanoTDF Encryption failed: \(error)")
            throw ChatError.encryptionError(error)
        }
    }

    // MARK: - Persistence Helpers

    /// Creates a ThoughtMetadata object (part of Thought model)
    private func createThoughtMetadata(from model: ThoughtServiceModel) -> Thought.Metadata {
        Thought.Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: Date(), // Use current date for creation timestamp
            contributors: [] // Add contributors if applicable/available
        )
    }

    /// Creates and saves a Thought object to persistence.
    @discardableResult
    // **FIX:** Modify signature to accept publicID
    private func createAndSaveThought(nanoData: Data, thoughtModel: ThoughtServiceModel, publicID: Data) async throws -> Thought {
        let thoughtMetadata = createThoughtMetadata(from: thoughtModel)

        // Create the Thought object using the standard initializer
        let thought = Thought(
            nano: nanoData,
            metadata: thoughtMetadata
        )

        // **FIX:** Explicitly set the publicID before saving
        thought.publicID = publicID

        do {
            // Save the thought itself (now with the correct publicID)
            let saved = try await PersistenceController.shared.saveThought(thought)

            // Only associate if the thought was actually saved (not a duplicate)
            if saved {
                // Associate thought with the stream if the stream exists locally
                // This task runs asynchronously and doesn't block the return.
                Task { // Run association in a separate task to avoid blocking
                    if let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID) {
                        // Use the dedicated PersistenceController method for association
                        await PersistenceController.shared.associateThoughtWithStream(thought: thought, stream: stream)
                        print("ChatViewModel: Association task completed for thought \(thought.publicID.base58EncodedString) with stream \(stream.publicID.base58EncodedString)")
                    } else {
                        print("ChatViewModel: Stream \(streamPublicID.base58EncodedString) not found for thought association.")
                    }
                }
            } else {
                print("ChatViewModel: Thought \(thought.publicID.base58EncodedString) was a duplicate, skipping association.")
            }

            // This print statement now correctly reflects the ID saved.
            print("ChatViewModel: Saved thought \(thought.publicID.base58EncodedString) locally (Duplicate: \(!saved)).")
            return thought
        } catch {
            print("❌ ChatViewModel: Error saving thought: \(error)")
            throw ChatError.persistenceError(error)
        }
    }

    // MARK: - FlatBuffer Policy Helper (for regular messages)

    private func createPolicyData(for thoughtModel: ThoughtServiceModel) throws -> Data {
        // **FIX:** Add guard to ensure thoughtModel.publicID is valid before proceeding
        guard !thoughtModel.publicID.isEmpty else {
            print("❌ ChatViewModel: Cannot create policy data, thoughtModel.publicID is empty.")
            throw ChatError.missingPublicID // Or a more specific error
        }

        var builder = FlatBufferBuilder()

        let formatVersionString = builder.create(string: "1.0")
        let formatProfileString = builder.create(string: "standard")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(&builder, type: .plain, versionOffset: formatVersionString, profileOffset: formatProfileString)

        // Map app MediaType to Arkavo_MediaType for FlatBuffers
        let fbMediaType: Arkavo_MediaType = switch thoughtModel.mediaType {
        case .text: .text
        case .image: .image
        case .video: .video
        case .audio: .audio
        // Special handling for types not in FlatBuffers schema
        case .post, .say: .text // Map speech/post types to text
        }

        let contentFormat = Arkavo_ContentFormat.createContentFormat(&builder, mediaType: fbMediaType, dataEncoding: .utf8, formatOffset: formatInfo)

        let rating: Offset = Arkavo_Rating.createRating(&builder, violent: .mild, sexual: .none_, profane: .none_, substance: .none_, hate: .none_, harm: .none_, mature: .none_, bully: .none_)
        let purpose = Arkavo_Purpose.createPurpose(&builder, educational: 0.8, entertainment: 0.2, news: 0.0, promotional: 0.0, personal: 0.0, opinion: 0.1, transactional: 0.0, harmful: 0.0, confidence: 0.9)

        // These vectors now use the correct IDs from the thoughtModel
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: thoughtModel.streamPublicID)
        let creatorVector = builder.createVector(bytes: thoughtModel.creatorPublicID)
        let topics: [UInt32] = []
        let topicsVector = builder.createVector(topics)

        let metadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            creatorVectorOffset: creatorVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat
        )
        builder.finish(offset: metadata)

        var buffer = builder.sizedBuffer
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

        return Data(bytes: buffer.memory.advanced(by: buffer.reader), count: Int(buffer.size))
    }
}

// Extension potentially needed on PeerDiscoveryManager (example)
// extension PeerDiscoveryManager {
//     func getProfileId(for peerID: MCPeerID) -> String? {
//         // Implementation to map MCPeerID back to a profile public ID string
//         // This might involve looking up connected peers' discovery info
//         return nil // Placeholder
//     }
//
//     func getPeerID(for profileID: Data) -> MCPeerID? {
//         // Implementation to map a profile public ID to an MCPeerID
//         // This might involve iterating through connected peers
//         return nil // Placeholder
//     }
//
//     func sendDirectDataMessage(to peerID: MCPeerID, data: Data, streamID: Data) throws {
//         // Implementation to send data directly to a peer,
//         // possibly encoding streamID and data together or using MCSession's send method.
//         // Example using MCSession:
//         // guard let session = mcSession else { throw PeerError.notConnected }
//         // let packet = P2PDataPacket(streamID: streamID, payload: data) // Define a Codable struct/class
//         // let encodedData = try JSONEncoder().encode(packet)
//         // try session.send(encodedData, toPeers: [peerID], with: .reliable)
//     }
// }

// Extension potentially needed on ArkavoClient
// extension ArkavoClient {
//     var tdfClient: TDFClient? {
//         // Return the configured TDFClient instance used by ArkavoClient
//         return self._tdfClientInstance // Placeholder for actual property name
//     }
// }

// Extension for Thought convenience initializer
extension Thought {
    // Convenience initializer or static function to create Thought from ThoughtServiceModel
    // This replaces the previous `from(_ model: ThoughtServiceModel)` which was in an extension.
    // Note: This assumes Thought's initializer can take publicID directly.
    // Adjust based on the actual @Model definition.
    convenience init(from model: ThoughtServiceModel, nano: Data) {
        let metadata = Metadata( // Reconstruct Metadata struct
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: Date(), // Or get from model if available
            contributors: [] // Or get from model if available
        )
        // This assumes the primary initializer correctly sets the publicID
        // based on the provided metadata or nano structure.
        // If the publicID needs to be explicitly passed from model.publicID,
        // this initializer or the primary one needs adjustment.
        self.init(nano: nano, metadata: metadata)
        // **NOTE:** If this convenience init is used, the publicID might still be implicitly set.
        // The fix applied in createAndSaveThought explicitly sets it *after* initialization.
        if !model.publicID.isEmpty {
            publicID = model.publicID // Attempt to set it here too, if possible
        }
    }
}

// MARK: - P2PClientDelegate Implementation

extension ChatViewModel: P2PClientDelegate {
    func clientDidReceiveMessage(_: P2PClient, streamID: Data, messageData: Data, from profile: Profile) {
        // Only process messages for this ChatViewModel's stream
        guard streamID == streamPublicID else {
            return
        }

        print("ChatViewModel: Received message from P2PClient for stream \(streamID.base58EncodedString)")

        // Process the message data to display in UI
        Task { @MainActor in // Ensure UI updates happen on the main thread
            do {
                let thoughtModel = try ThoughtServiceModel.deserialize(from: messageData)

                // Verify it's a chat message type
                guard thoughtModel.mediaType == .say else {
                    print("ChatViewModel: Ignoring message with non-chat mediaType: \(thoughtModel.mediaType)")
                    return
                }

                // **FIX:** Ensure thoughtModel has a publicID
                guard !thoughtModel.publicID.isEmpty else {
                    print("❌ ChatViewModel: Received P2P message missing publicID.")
                    return // Or handle error appropriately
                }

                let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)
                let timestamp = Date()

                let message = ChatMessage(
                    id: thoughtModel.publicID.base58EncodedString,
                    userId: profile.publicID.base58EncodedString,
                    username: profile.name, // Use the sender's profile name directly
                    content: displayContent,
                    timestamp: timestamp,
                    attachments: [],
                    reactions: [],
                    isPinned: false,
                    publicID: thoughtModel.publicID,
                    creatorPublicID: profile.publicID, // Use sender's profile ID
                    mediaType: thoughtModel.mediaType,
                    rawContent: thoughtModel.content
                )

                // Avoid adding duplicates
                if !messages.contains(where: { $0.id == message.id }) {
                    messages.append(message)
                    messages.sort { $0.timestamp < $1.timestamp }
                    print("ChatViewModel: Added message from P2PClient to UI")
                }
            } catch {
                print("Error processing received P2P message: \(error)")
            }
        }
    }

    func clientDidChangeConnectionStatus(_: P2PClient, status: P2PConnectionStatus) {
        // Update UI or other state based on connection status
        Task { @MainActor in
            switch status {
            case let .connected(peerCount):
                print("ChatViewModel: P2P connected with \(peerCount) peers")
            // Update UI to show connected status
            case .connecting:
                print("ChatViewModel: P2P connecting...")
            // Show connecting status
            case .disconnected:
                print("ChatViewModel: P2P disconnected")
            // Show disconnected status
            case let .failed(error):
                print("ChatViewModel: P2P connection failed: \(error)")
                // Show error
            }
        }
    }

    func clientDidUpdateKeyStatus(_: P2PClient, localKeys: Int, totalCapacity: Int) {
        // Update UI to show key status if needed
        print("ChatViewModel: P2P key status: \(localKeys)/\(totalCapacity)")
    }

    func clientDidEncounterError(_: P2PClient, error: Error) {
        // Handle errors from P2PClient
        print("ChatViewModel: P2P error: \(error)")
    }
}

// Add UUID extension to support UUID to Data conversion for publicID
extension UUID {
    var uuidStringData: Data {
        // Convert UUID to Data for use as publicID
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

// **FIX:** Removed placeholder extension for PersistenceController
// The associateThoughtWithStream function is now implemented in PersistenceController.swift
