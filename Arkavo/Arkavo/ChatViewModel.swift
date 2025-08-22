import ArkavoSocial
import CryptoKit
import FlatBuffers
import OpenTDFKit
import SwiftData
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject { // REMOVED: ArkavoClientDelegate conformance
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    let streamPublicID: Data
    @Published var messages: [ChatMessage] = []
    private var notificationObservers: [NSObjectProtocol] = []

    // Access to PeerDiscoveryManager (might still be needed for profile lookups)
    private var peerManager: PeerDiscoveryManager {
        ViewModelFactory.shared.getPeerDiscoveryManager()
    }

    init(client: ArkavoClient, account: Account, profile: Profile, streamPublicID: Data) {
        self.client = client
        self.account = account
        self.profile = profile
        self.streamPublicID = streamPublicID

        // REMOVED: self.client.delegate = self

        setupNotifications()

        // Load existing thoughts for this stream
        Task {
            await loadExistingMessages()
        }
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        // Consider setting client.delegate = nil if appropriate lifecycle management is needed
    }

    // Access the shared message router
    private var messageRouter: ArkavoMessageRouter {
        ViewModelFactory.shared.serviceLocator.resolve()
    }

    // MARK: - Message Loading and Handling

    private func loadExistingMessages() async {
        do {
            let thoughts = try await PersistenceController.shared.fetchThoughtsForStream(withPublicID: streamPublicID)
            print("ChatViewModel: Loading \(thoughts.count) existing thoughts for stream \(streamPublicID.base58EncodedString)")

            for thought in thoughts {
                // Each 'thought' contains encrypted 'nano' data in NanoTDF format.
                // Based on the ArkavoMessageRouter implementation, decryption happens through
                // a multi-step process involving rewrap requests and key exchange.

                // After analyzing ArkavoClient and ArkavoMessageRouter, we found that:
                // 1. There's no public direct decrypt method in ArkavoClient
                // 2. ArkavoMessageRouter handles decryption and posts .messageDecrypted notifications
                // 3. The original pattern was to send nano data to client.sendMessage()

                // Try the original approach which may trigger ArkavoMessageRouter's processing path
                // This will either work if ArkavoMessageRouter handles it, or do nothing if it doesn't
                print("ChatViewModel: Attempting to process stored NanoTDF for thought \(thought.publicID.base58EncodedString)")

                // Directly call the message router's processing method for local NanoTDF data
                do {
                    try await messageRouter.processMessage(thought.nano, messageId: thought.id)
                } catch {
                    try? await PersistenceController.shared.deleteThought(thought)
                }

                // NOTE TO DEVELOPER: This approach needs verification.
                // If existing messages don't appear, ArkavoClient may need an additional
                // method to initiate decryption for local NanoTDF data without sending to server.
            }

            // Sorting will happen as messages are added via notification handlers
            // Important: If decryption doesn't trigger properly, messages won't appear in UI
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
        // This remains the primary way to get decrypted content into the UI.
        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted, // Assuming ArkavoClient posts this after successful decryption
            object: nil, // Optionally filter by client instance if needed
            queue: .main,
        ) { [weak self] notification in
            guard let self, // Ensure self is valid
                  let data = notification.userInfo?["data"] as? Data,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy else { return }

            // Check if the decrypted message belongs to this stream context
            print("ChatViewModel: Received .messageDecrypted notification.") // Log receipt
            let incomingThoughtModel = try? ThoughtServiceModel.deserialize(from: data) // Deserialize once

            if let thoughtModel = incomingThoughtModel // Check if deserialization succeeded
//               thoughtModel.streamPublicID == self.streamPublicID // FIXME: skip for now Check if stream IDs match
            {
                print("   Stream ID MATCH: \(thoughtModel.streamPublicID.base58EncodedString). Handling message.") // Log match
                print("ChatViewModel: Received decrypted message notification for this stream.")
                Task { @MainActor [weak self] in
                    await self?.handleDecryptedThought(payload: data, policy: policy)
                }
            } else {
                // Message is for a different stream, ignore.
                // Log the mismatch or failure for debugging
                let incomingStreamID = incomingThoughtModel?.streamPublicID.base58EncodedString ?? "N/A"
                let reason = incomingThoughtModel == nil ? "Deserialization Failed" : "Stream ID Mismatch"
                print("   Ignoring message. Reason: \(reason).")
                print("     ViewModel Stream ID: \(streamPublicID.base58EncodedString)")
                print("     Incoming Stream ID: \(incomingStreamID)")
            }
        }
        notificationObservers.append(messageObserver)
    }

    @MainActor
    func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy) async {
        print("ChatViewModel: Handling decrypted thought...")
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)

            // Double-check if it belongs to this stream
//            guard thoughtModel.streamPublicID == streamPublicID else {
//                print("❌ ChatViewModel: Decrypted thought belongs to a different stream. Ignoring.")
//                return
//            }

            // Ensure it's a message type we display in chat
            guard thoughtModel.mediaType == .say else {
                print("ChatViewModel: Ignoring decrypted thought with non-chat mediaType: \(thoughtModel.mediaType)")
                return
            }

            // **FIX:** Ensure thoughtModel has a publicID before proceeding
            guard !thoughtModel.publicID.isEmpty else {
                print("❌ ChatViewModel: Decrypted thought model missing publicID.")
                throw ChatError.missingPublicID
            }

            let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)

            // Extract timestamp directly from the deserialized thought model
            let timestamp = thoughtModel.createdAt

            let message = await ChatMessage(
                id: thoughtModel.publicID.base58EncodedString, // Use thought public ID
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: formatUsername(publicID: thoughtModel.creatorPublicID), // Fetch username async
                content: displayContent,
                timestamp: timestamp, // Use timestamp from the model
                attachments: [],
                reactions: [],
                isPinned: false,
                publicID: thoughtModel.publicID,
                creatorPublicID: thoughtModel.creatorPublicID,
                mediaType: thoughtModel.mediaType,
                rawContent: thoughtModel.content, // Store original decrypted content
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
        default:
            "[\(mediaType.rawValue) content]"
        }
    }

    // Updated to be async to allow fetching profile info
    func formatUsername(publicID: Data) async -> String {
        do {
            // Attempt to fetch profile using ArkavoClient's profile cache/fetch mechanism
            let profile = try await client.fetchProfile(forPublicID: publicID)
            return profile.displayName // Or profile.handle
        } catch {
            // Fallback if profile fetch fails
            print("ChatViewModel: Failed to fetch profile for \(publicID.base58EncodedString): \(error)")
            let shortID = publicID.prefix(6).base58EncodedString
            return "User-\(shortID)"
        }
    }

    enum ChatError: Error {
        case noProfile
        case serializationError
        case encryptionError(Error)
        case persistenceError(Error)
        case missingPublicID
        case clientError(Error) // General ArkavoClient error
        case invalidPolicy(String)
        case invalidState(String)
        case streamError(String)
    }

    // MARK: - Message Sending (Unified Approach)

    func sendMessage(content: String) async throws {
        print("ChatViewModel: sendMessage called.")
        guard !content.isEmpty else { return }
        let messageData = content.data(using: .utf8) ?? Data()
        let creationDate = Date() // Capture creation time
        var kasMetadata: KasMetadata? = nil
        var policyData: Data? = nil

        // Fetch the stream to check its type
        guard let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID) else {
            print("❌ ChatViewModel: Could not fetch stream \(streamPublicID.base58EncodedString) to send message.")
            throw ChatError.streamError("Stream not found")
        }

        // --- Determine Send Method and Policy ---
        // FIXME: revise to see if all profiles in a stream hav a KeyStore
        if stream.isInnerCircleStream {
            print("ChatViewModel: Sending message in InnerCircle stream...")
            for profile in stream.innerCircleProfiles {
                if let keyStorePublic = profile.keyStorePublic {
                    let keystore = PublicKeyStore(curve: .secp256r1)
                    try await keystore.deserialize(from: keyStorePublic)
                    if let rl = ResourceLocator(
                        protocolEnum: .sharedResourceDirectory,
                        body: profile.publicID.base58EncodedString,
                    ) {
                        kasMetadata = try await keystore.createKasMetadata(resourceLocator: rl)
                        // Create thought service model
                        let thoughtModel = ThoughtServiceModel(
                            creatorPublicID: account.profile!.publicID,
                            streamPublicID: profile.publicID, // route to each individual, perhaps rename to targetPublicID
                            mediaType: .say,
                            createdAt: creationDate,
                            content: messageData,
                        )
                        policyData = try createFlatBuffersPolicy(for: thoughtModel)
                        profile.keyStorePublic = await keystore.serialize()
                        try PersistenceController.shared.saveStream(stream)
                        break
                    }
                }
            }
            // Check P2P connection status
            if !peerManager.connectedPeers.isEmpty {
                print("   P2P Peers connected. Sending via PeerManager.")
                // P2P Send Logic (using PeerManager)
                do {
                    // PeerManager handles encryption and policy internally for P2P
                    try await peerManager.sendSecureTextMessage(content, in: stream)
                    print("   InnerCircle P2P message sent successfully via PeerManager.")
                    // Add local message immediately after successful P2P send
                    // Note: P2P send doesn't return nanoData, so we need a way to get/generate the thought ID
                    // Let's generate a temporary ID or use a placeholder for now.
                    // A better approach might be for sendSecureTextMessage to return the Thought ID.
                    let tempThoughtID = UUID().uuidString.data(using: .utf8)! // Placeholder ID
                    addLocalChatMessage(content: content, thoughtPublicID: tempThoughtID, timestamp: creationDate)
                    return // Exit after successful P2P send
                } catch {
                    print("❌ ChatViewModel: Failed to send InnerCircle message via P2P: \(error). Falling back to ArkavoClient.")
                    // Fall through to ArkavoClient send if P2P fails
                }
            } else {
                print("   No P2P Peers connected. Sending via ArkavoClient.")
                // Fall through to ArkavoClient send
            }
        }

        // --- ArkavoClient Send Logic (Used for non-InnerCircle or P2P fallback) ---
        print("ChatViewModel: Sending message via ArkavoClient...")
        guard client.currentState == .connected else {
            throw ChatError.invalidState("ArkavoClient not connected")
        }

        do {
            // Create thought service model
            let thoughtModel = ThoughtServiceModel(
                creatorPublicID: profile.publicID,
                streamPublicID: streamPublicID,
                mediaType: .say,
                createdAt: creationDate, // Set the creation timestamp
                content: messageData,
            )
            let isOneTime = policyData != nil
            if policyData == nil {
                policyData = try createFlatBuffersPolicy(for: thoughtModel)
            }

            // Serialize payload
            let payload = try thoughtModel.serialize()

            // Encrypt and send via ArkavoClient
            // This method handles encryption and sending via WebSocket (NATS msg type 0x05)
            let nanoData = try await client.encryptAndSendPayload(
                payload: payload,
                policyData: policyData!,
                kasMetadata: kasMetadata
            )
            print("ChatViewModel: Encrypted and sent payload via ArkavoClient.")

            // do not save one-time thought
            // Create and save the Thought locally
            // Use the *same* publicID and timestamp as the service model for consistency
            if !isOneTime {
                let thought = try await createAndSaveThought(
                    nanoData: nanoData, // Save the *encrypted* data
                    thoughtModel: thoughtModel,
                    publicID: thoughtModel.publicID, // Use the ID from the service model
                )
                addLocalChatMessage(content: content, thoughtPublicID: thought.publicID, timestamp: thought.metadata.createdAt)
            } else {
                // Add message to local UI immediately
                // Use the timestamp from the locally created Thought's metadata (which came from thoughtModel)
                addLocalChatMessage(content: content, thoughtPublicID: thoughtModel.publicID, timestamp: creationDate)
            }
        } catch {
            print("❌ ChatViewModel: Failed to send encrypted message: \(error)")
            // TODO: Notify user of failure
            // Map error to ChatError if needed
            // self.lastError = ChatError.clientError(error).localizedDescription
        }
    }

    // Removed sendRegularMessage, sendP2PMessage, sendDirectMessageToPeer
    // Replaced by unified sendMessage -> sendEncryptedMessage

    // MARK: - P2P Messaging (Superseded by Unified Approach)

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

    // Removed handleIncomingP2PData - Handled by ArkavoClientDelegate and .messageDecrypted notification

    // MARK: - UI Helpers

    /// Adds a chat message to the local UI, typically after sending.
    private func addLocalChatMessage(content: String, thoughtPublicID: Data, timestamp: Date) { // Removed isP2P flag
        guard !thoughtPublicID.isEmpty else {
            print("❌ ChatViewModel: Attempted to add local chat message with empty publicID.")
            return
        }

        let message = ChatMessage(
            id: thoughtPublicID.base58EncodedString,
            userId: profile.publicID.base58EncodedString,
            username: "Me", // Simplified username for local messages
            content: content,
            timestamp: timestamp, // Use provided timestamp (from saved Thought)
            attachments: [],
            reactions: [],
            isPinned: false,
            publicID: thoughtPublicID,
            creatorPublicID: profile.publicID,
            mediaType: .say,
            rawContent: content.data(using: .utf8) ?? Data(),
        )

        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
            messages.sort { $0.timestamp < $1.timestamp }
            print("ChatViewModel: Added local message ID \(message.id) to UI. Total: \(messages.count)")
        }
    }

    private func createFlatBuffersPolicy(for thoughtModel: ThoughtServiceModel) throws -> Data {
        var builder = FlatBufferBuilder()

        // Create format info
        let formatVersionString = builder.create(string: "1.0")
        let formatProfileString = builder.create(string: "standard")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain,
            versionOffset: formatVersionString,
            profileOffset: formatProfileString,
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: thoughtModel.mediaType == .image ? .image : .text,
            dataEncoding: .utf8,
            formatOffset: formatInfo,
        )

        // Create rating
        let rating = Arkavo_Rating.createRating(
            &builder,
            violent: .none_,
            sexual: .none_,
            profane: .none_,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .none_,
            bully: .none_,
        )

        // Create purpose
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.2,
            entertainment: 0.8,
            news: 0.0,
            promotional: 0.0,
            personal: 0.8,
            opinion: 0.2,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9,
        )

        // Create ID and related vectors
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: thoughtModel.streamPublicID)
        let creatorVector = builder.createVector(bytes: thoughtModel.creatorPublicID)

        // Create topics vector
        let topics: [UInt32] = [1, 2, 3]
        let topicsVector = builder.createVector(topics)

        // Create metadata root
        let metadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            creatorVectorOffset: creatorVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat,
        )

        builder.finish(offset: metadata)

        // Verify FlatBuffer
        var buffer = builder.sizedBuffer
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

        // Return the final binary policy data
        return Data(
            bytes: buffer.memory.advanced(by: buffer.reader),
            count: Int(buffer.size),
        )
    }

    // MARK: - Persistence Helpers

    /// Creates a ThoughtMetadata object (part of Thought model)
    private func createThoughtMetadata(from model: ThoughtServiceModel) -> Thought.Metadata {
        // Use the timestamp directly from the model
        Thought.Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: model.createdAt, // Use timestamp from service model
            contributors: [],
        )
    }

    /// Creates and saves a Thought object to persistence.
    @discardableResult
    private func createAndSaveThought(nanoData: Data, thoughtModel: ThoughtServiceModel, publicID: Data) async throws -> Thought {
        let thoughtMetadata = createThoughtMetadata(from: thoughtModel)

        let thought = Thought(
            nano: nanoData, // Store the encrypted NanoTDF data
            metadata: thoughtMetadata,
        )
        // Ensure the Thought's publicID matches the one used/generated for the service model
        thought.publicID = publicID

        do {
            let saved = try await PersistenceController.shared.saveThought(thought)
            if saved {
                Task { // Associate asynchronously
                    do {
                        // Attempt to fetch the stream
                        guard let stream = try await PersistenceController.shared.fetchStream(withPublicID: streamPublicID) else {
                            print("❌ ChatViewModel: Stream with publicID \(streamPublicID.base58EncodedString) not found")
                            return
                        }
                        await PersistenceController.shared.associateThoughtWithStream(thought: thought, stream: stream)
                        print("ChatViewModel: Association task completed for thought \(thought.publicID.base58EncodedString) with stream \(stream.publicID.base58EncodedString)")
                    } catch {
                        // Log the specific error if fetching or association fails
                        print("❌ ChatViewModel: Error associating thought \(thought.publicID.base58EncodedString) with stream \(streamPublicID.base58EncodedString): \(error)")
                    }
                }
            } else {
                print("ChatViewModel: Thought \(thought.publicID.base58EncodedString) was a duplicate, skipping association.")
            }
            print("ChatViewModel: Saved thought \(thought.publicID.base58EncodedString) locally (Duplicate: \(!saved)).")
            return thought
        } catch {
            print("❌ ChatViewModel: Error saving thought: \(error)")
            throw ChatError.persistenceError(error)
        }
    }
}

// Extension for Thought convenience initializer (Keep as is)
extension Thought {
    convenience init(from model: ThoughtServiceModel, nano: Data) {
        // Use timestamp from model when creating Metadata
        let metadata = Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: model.createdAt, // Use timestamp from service model
            contributors: [],
        )
        self.init(nano: nano, metadata: metadata)
        // Ensure the publicID matches the service model's ID
        if !model.publicID.isEmpty {
            publicID = model.publicID
        }
    }
}
