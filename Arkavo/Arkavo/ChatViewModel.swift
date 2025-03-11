import ArkavoSocial
import CryptoKit
import FlatBuffers
import OpenTDFKit
import SwiftData
import SwiftUI
import MultipeerConnectivity

@MainActor
class ChatViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    let streamPublicID: Data
    @Published var messages: [ChatMessage] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private static var instanceCount = 0
    private let instanceId: Int

    init(client: ArkavoClient, account: Account, profile: Profile, streamPublicID: Data) {
        Self.instanceCount += 1
        instanceId = Self.instanceCount
        print("🔵 Initializing ChatViewModel #\(instanceId)")

        self.client = client
        self.account = account
        self.profile = profile
        self.streamPublicID = streamPublicID
        setupNotifications()
        // Load existing thoughts for this stream
        Task {
            await loadExistingMessages()
        }
    }

    private func loadExistingMessages() async {
        do {
            let thoughts = try await PersistenceController.shared.fetchThoughtsForStream(withPublicID: streamPublicID)
            print("stream thoughts: \(thoughts.count) \(streamPublicID.base58EncodedString)")
            for thought in thoughts {
                try? await client.sendMessage(thought.nano)
            }
        } catch {
            print("Error loading existing messages: \(error)")
        }
    }

    private func setupNotifications() {
        print("ChatViewModel: setupNotifications")
        // Clean up any existing observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy else { return }
            Task { @MainActor [weak self] in
                await self?.handleDecryptedThought(payload: data, policy: policy)
            }
        }
        notificationObservers.append(messageObserver)
    }

    deinit {
        print("🔴 Deinitializing ChatViewModel #\(instanceId)")
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func sendMessage(content: String) async throws {
        print("ChatViewModel: sendMessage")
        let messageData = content.data(using: .utf8) ?? Data()
        
        // Check if this is an InnerCircle stream for p2p messaging
        if let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID),
           stream.isInnerCircleStream {
            // Send via MultipeerConnectivity
            sendP2PMessage(content, stream: stream)
            return
        }

        // Create thought service model for regular messaging
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamPublicID,
            mediaType: .say,
            content: messageData
        )

        // Create FlatBuffers policy
        var builder = FlatBufferBuilder()

        // Create format info
        let formatVersionString = builder.create(string: "1.0")
        let formatProfileString = builder.create(string: "standard")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain,
            versionOffset: formatVersionString,
            profileOffset: formatProfileString
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: .text,
            dataEncoding: .utf8,
            formatOffset: formatInfo
        )

        // TODO: determine rating using ML analysis
        let rating: Offset = Arkavo_Rating.createRating(
            &builder,
            violent: .mild,
            sexual: .none_,
            profane: .none_,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .none_,
            bully: .none_
        )

        // Create purpose
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.8,
            entertainment: 0.2,
            news: 0.0,
            promotional: 0.0,
            personal: 0.0,
            opinion: 0.1,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9
        )

        // Create ID and related vectors
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: thoughtModel.streamPublicID)
        let creatorVector = builder.createVector(bytes: thoughtModel.creatorPublicID)

        // Create topics vector
        let topics: [UInt32] = []
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
            contentOffset: contentFormat
        )

        builder.finish(offset: metadata)

        // Verify FlatBuffer
        var buffer = builder.sizedBuffer
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

        // Get policy data
        let policyData = Data(
            bytes: buffer.memory.advanced(by: buffer.reader),
            count: Int(buffer.size)
        )

        // Serialize payload
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData
        )

        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: streamPublicID,
            mediaType: .say,
            createdAt: Date(),
            contributors: []
        )

        let thought = Thought(
            nano: nanoData,
            metadata: thoughtMetadata
        )
        _ = try PersistenceController.shared.saveThought(thought)
        // Save thought to stream if locally stored
        if let stream = try await PersistenceController.shared.fetchStream(withPublicID: streamPublicID) {
            Task {
                stream.thoughts.append(thought)
                try await PersistenceController.shared.saveChanges()
            }
        }
    }

    private func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy) async {
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)
            guard thoughtModel.mediaType == .say else {
//                print("❌ Incorrect mediaType received \(thoughtModel.mediaType)")
                return
            }
            // Process content based on media type
            let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)

            let message = ChatMessage(
                id: UUID().uuidString,
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: formatUsername(publicID: thoughtModel.creatorPublicID),
                content: displayContent,
                timestamp: Date(),
                attachments: [],
                reactions: [],
                isPinned: false,
                publicID: thoughtModel.publicID,
                creatorPublicID: thoughtModel.creatorPublicID,
                mediaType: thoughtModel.mediaType,
                rawContent: thoughtModel.content // Store original content
            )

            await MainActor.run {
                messages.append(message)
            }
        } catch {
            print("❌ Error handling decrypted thought: \(error)")
        }
    }

    private func processContent(_ content: Data, mediaType: MediaType) -> String {
        switch mediaType {
        case .text, .post, .say:
            return String(data: content, encoding: .utf8) ?? "[Invalid text content]"

        case .image:
            if UIImage(data: content) != nil {
                return "[Image]"
            }
            return "[Invalid image data]"

        case .video:
            return "[Video content]"

        case .audio:
            return "[Audio content]"
        }
    }

    private func formatUsername(publicID: Data) -> String {
        let shortID = publicID.prefix(6).base58EncodedString
        return "User-\(shortID)"
    }

    enum ChatError: Error {
        case noProfile
        case serializationError
    }
    
    // MARK: - P2P Messaging
    
    func sendP2PMessage(_ content: String, stream: Stream) {
        // Create local chat message to display in UI
        let message = ChatMessage(
            id: UUID().uuidString,
            userId: profile.publicID.base58EncodedString,
            username: "Me (P2P)",
            content: content,
            timestamp: Date(),
            attachments: [],
            reactions: [],
            isPinned: false,
            publicID: Data(),
            creatorPublicID: profile.publicID,
            mediaType: .say,
            rawContent: content.data(using: .utf8) ?? Data()
        )
        
        messages.append(message)
    }
    
    func handleIncomingP2PMessage(_ message: String, from peer: String, timestamp: Date) {
        // Create a message to represent the incoming peer message
        let chatMessage = ChatMessage(
            id: UUID().uuidString,
            userId: "p2p-\(peer)",
            username: "\(peer) (P2P)",
            content: message,
            timestamp: timestamp,
            attachments: [],
            reactions: [],
            isPinned: false,
            publicID: Data(),
            creatorPublicID: Data(),
            mediaType: .say,
            rawContent: message.data(using: .utf8) ?? Data()
        )
        
        messages.append(chatMessage)
    }
}
