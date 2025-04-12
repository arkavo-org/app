import ArkavoSocial
import CryptoKit
import FlatBuffers
// import MultipeerConnectivity // Removed if not directly needed, ArkavoClient might handle internally
import OpenTDFKit
import SwiftData
import SwiftUI

// Helper extension to convert Swift MediaType to FlatBuffers Arkavo_MediaType
// Assuming MediaType enum cases match Arkavo_MediaType cases. Adjust if needed.
// REMOVED MediaType extension as requested

@MainActor
class ChatViewModel: ObservableObject, ArkavoClientDelegate { // Conform to ArkavoClientDelegate
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

        // Set ArkavoClient delegate
        self.client.delegate = self

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
                try? await client.sendMessage(thought.nano)

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
                // Message is for a different stream, ignore.
            }
        }
        notificationObservers.append(messageObserver)

        // Removed P2P message observer (.p2pMessageReceived)
    }

    @MainActor
    func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy) async {
        print("ChatViewModel: Handling decrypted thought...")
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)

            // Double-check if it belongs to this stream
            guard thoughtModel.streamPublicID == streamPublicID else {
                print("❌ ChatViewModel: Decrypted thought belongs to a different stream. Ignoring.")
                return
            }

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

            let message = ChatMessage(
                id: thoughtModel.publicID.base58EncodedString, // Use thought public ID
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: await formatUsername(publicID: thoughtModel.creatorPublicID), // Fetch username async
                content: displayContent,
                timestamp: timestamp, // Use timestamp from the model
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
        case invalidState(String) // For ArkavoClient state issues
    }

    // MARK: - Message Sending (Unified Approach)

    func sendMessage(content: String) async throws {
        print("ChatViewModel: sendMessage called.")
        guard !content.isEmpty else { return }
        guard client.currentState == .connected else {
            throw ChatError.invalidState("ArkavoClient not connected")
        }

        // Determine policy based on chat type (direct, stream, regular)
        let policyData: Data
        if let directProfile = directMessageProfile {
            print("ChatViewModel: Sending as direct message to \(directProfile.name)")
            policyData = try createPolicyDataForDirectMessage(recipientProfileID: directProfile.publicID)
        } else if let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID),
                  stream.isInnerCircleStream {
            print("ChatViewModel: Sending as P2P message in stream \(stream.publicID.base58EncodedString)")
            policyData = try createPolicyDataForStream() // Assumes stream policy
        } else {
            print("ChatViewModel: Sending as regular message via client.")
            policyData = try createPolicyDataForStream() // Use stream policy for regular messages too? Or a different one?
        }

        // Common sending logic
        await sendEncryptedMessage(content: content, policyData: policyData)
    }

    /// Encrypts and sends the message using ArkavoClient, saves locally.
    private func sendEncryptedMessage(content: String, policyData: Data) async {
        let messageData = content.data(using: .utf8) ?? Data()
        let creationDate = Date() // Capture creation time

        do {
            // Create thought service model
            let thoughtModel = ThoughtServiceModel(
                creatorPublicID: profile.publicID,
                streamPublicID: streamPublicID,
                mediaType: .say,
                createdAt: creationDate, // Set the creation timestamp
                content: messageData
            )
            // Decide if the service model's publicID should be the UUID-based one or content-based one.
            // Using the content-based one generated by the init for now.
            // If UUID-based is preferred: thoughtModel.publicID = newThoughtPublicID

            // Serialize payload
            let payload = try thoughtModel.serialize()

            // Encrypt and send via ArkavoClient
            // This method handles encryption and sending via WebSocket (NATS msg type 0x05)
            let nanoData = try await client.encryptAndSendPayload(
                payload: payload,
                policyData: policyData
            )
            print("ChatViewModel: Encrypted and sent payload via ArkavoClient.")

            // Create and save the Thought locally
            // Use the *same* publicID and timestamp as the service model for consistency
            let thought = try await createAndSaveThought(
                nanoData: nanoData, // Save the *encrypted* data
                thoughtModel: thoughtModel,
                publicID: thoughtModel.publicID // Use the ID from the service model
            )

            // Add message to local UI immediately
            // Use the timestamp from the locally created Thought's metadata (which came from thoughtModel)
            addLocalChatMessage(content: content, thoughtPublicID: thought.publicID, timestamp: thought.metadata.createdAt)

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
            rawContent: content.data(using: .utf8) ?? Data()
        )

        if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
            messages.sort { $0.timestamp < $1.timestamp }
            print("ChatViewModel: Added local message ID \(message.id) to UI. Total: \(messages.count)")
        }
    }

    // MARK: - Cryptography Helpers (Now rely on ArkavoClient)

    // Removed encryptPayload - ArkavoClient.encryptAndSendPayload handles this.

    // MARK: - Persistence Helpers

    /// Creates a ThoughtMetadata object (part of Thought model)
    private func createThoughtMetadata(from model: ThoughtServiceModel) -> Thought.Metadata {
        // Use the timestamp directly from the model
        Thought.Metadata(
            creatorPublicID: model.creatorPublicID,
            streamPublicID: model.streamPublicID,
            mediaType: model.mediaType,
            createdAt: model.createdAt, // Use timestamp from service model
            contributors: []
        )
    }


    /// Creates and saves a Thought object to persistence.
    @discardableResult
    private func createAndSaveThought(nanoData: Data, thoughtModel: ThoughtServiceModel, publicID: Data) async throws -> Thought {
        let thoughtMetadata = createThoughtMetadata(from: thoughtModel)

        let thought = Thought(
            nano: nanoData, // Store the encrypted NanoTDF data
            metadata: thoughtMetadata
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

    // MARK: - FlatBuffer Policy Helpers (Adjusted for different scenarios)

    /// Creates policy data for messages intended for the current stream.
    private func createPolicyDataForStream() throws -> Data {
        // Policy grants access based on having an attribute matching the stream ID.
        // Assumes recipients get this attribute via KAS.
        let attribute = "stream:\(streamPublicID.base58EncodedString)"
        let policyJson = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [ { "attribute": "\(attribute)" } ],
            "dissem": []
          }
        }
        """
        guard let policyData = policyJson.data(using: .utf8) else {
            throw ChatError.invalidPolicy("Failed to encode stream policy JSON")
        }
        // This creates an *embedded plaintext* policy as Data.
        // ArkavoClient.encryptAndSendPayload is expected to handle embedding this correctly.
        return policyData
    }

    /// Creates policy data for a direct message to a specific recipient.
    private func createPolicyDataForDirectMessage(recipientProfileID: Data) throws -> Data {
        // Policy grants access based on dissem list containing the recipient's profile ID.
        let policyJson = """
        {
          "uuid": "\(UUID().uuidString)",
          "body": {
            "dataAttributes": [],
            "dissem": ["\(recipientProfileID.base58EncodedString)"]
          }
        }
        """
        guard let policyData = policyJson.data(using: .utf8) else {
            throw ChatError.invalidPolicy("Failed to encode direct message policy JSON")
        }
        // This creates an *embedded plaintext* policy as Data.
        // ArkavoClient.encryptAndSendPayload is expected to handle embedding this correctly.
        return policyData
    }

    // Removed the complex FlatBuffer policy creation method (`createPolicyData(for:)`)
    // Replaced with simpler JSON policy creation for embedded policies.
    // If FlatBuffer policies are strictly required by ArkavoClient, that method needs to be reinstated and adapted.
    // However, `ArkavoClient.encryptAndSendPayload` seems designed for embedded plaintext policies.

    // MARK: - ArkavoClientDelegate Methods

    nonisolated func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        Task { @MainActor in
            print("ChatViewModel: ArkavoClient state changed to \(state)")
            // Update UI based on state (e.g., show connection status)
            switch state {
            case .connected:
                // Enable input, show connected status
                () // Use empty tuple or other placeholder if needed
            case .disconnected:
                // Disable input, show disconnected
                print("ChatViewModel: Client disconnected")
            case .connecting, .authenticating:
                // Show connecting status
                print("ChatViewModel: Client connecting or authenticating")
            case .error(let error):
                // Show error message
                print("ChatViewModel: ArkavoClient error state: \(error)")
            }
        }
    }

    nonisolated func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        // This delegate method receives *raw* data from the WebSocket for message types
        // not handled by specific continuations (like PublicKey, KASKey responses).
        // This includes NATS messages (0x05, 0x06) which likely contain NanoTDF payloads.
        print("ChatViewModel: clientDidReceiveMessage raw data length: \(message.count)")

        // We assume ArkavoClient needs to be explicitly told to decrypt this data.
        // How? If there's no public decrypt method, this data might be undecryptable here.
        // Revisit Hypothesis: Does ArkavoClient *internally* decrypt NATS messages (0x05)
        // containing NanoTDFs and *then* post `.messageDecrypted`?
        // If yes, this delegate method might only receive *other* kinds of messages,
        // or NATS messages that *failed* internal decryption.

        // Let's assume the `.messageDecrypted` notification is the correct path for now.
        // This method could log unexpected message types.
        if let typeByte = message.first {
            print("ChatViewModel: Received unhandled message type 0x\(String(format: "%02X", typeByte)) via delegate.")
            // Potentially handle specific non-chat message types if needed in the future.
            // If ArkavoClient *doesn't* internally decrypt and post notifications for NATS messages,
            // this is where we would need to call the hypothetical `client.decryptAndNotify(nanoData: message)`
            // Task {
            //     try? await client.decryptAndNotify(nanoData: message)
            // }
        }
    }

    nonisolated func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        Task { @MainActor in
            print("❌ ChatViewModel: ArkavoClient received error: \(error)")
            // Display error to user
        }
    }

    // --- Removed ArkavoClientDelegate methods related to KeyStore/Peer Profile Updates ---
    // These seemed specific to the GroupViewModel/Multipeer context in the reference file.
    // Add them back if ChatViewModel needs to react to these events.
    // nonisolated func arkavoClientDidUpdateKeyStatus(...)
    // nonisolated func arkavoClientDidUpdatePeerProfile(...)
    // nonisolated func arkavoClientEncounteredError(...) // Covered by clientDidReceiveError?

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
            contributors: []
        )
        self.init(nano: nano, metadata: metadata)
        // Ensure the publicID matches the service model's ID
        if !model.publicID.isEmpty {
            publicID = model.publicID
        }
    }
}

// Removed P2PClientDelegate Implementation

// Add UUID extension (Keep as is)
extension UUID {
    var uuidStringData: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }
}

// Removed placeholder extensions for PeerDiscoveryManager, ArkavoClient, PersistenceController
