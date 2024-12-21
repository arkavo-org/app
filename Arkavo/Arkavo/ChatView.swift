import ArkavoSocial
import CryptoKit
import OpenTDFKit
import SwiftUI

// MARK: - View Model

@MainActor
class ChatViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var messages: [ChatMessage] = []
    @Published var connectionState: ArkavoClientState = .disconnected
    // Track pending thoughts by their ephemeral public key
    private var pendingThoughts: [Data: (header: Header, payload: Payload, nano: NanoTDF)] = [:]
    // Add set to track processed message IDs
    private var processedMessageIds = Set<Data>()

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        connectionState = client.currentState
        // Set self as delegate
        client.delegate = self
        print("ChatViewModel initialized and delegate set")
    }

    func sendMessage(content: String) async throws {
        let messageData = content.data(using: .utf8) ?? Data()
        let streamPublicID = Data() // Replace with actual stream ID

        let message = ChatMessage(
            id: UUID().uuidString,
            userId: profile.id.uuidString,
            username: profile.name,
            content: content,
            timestamp: Date(),
            attachments: [],
            reactions: [],
            isPinned: false,
            publicID: generatePublicID(content: messageData),
            creatorPublicID: profile.publicID,
            mediaType: .text,
            rawContent: content.data(using: .utf8) ?? Data()
        )

        // Create ThoughtServiceModel
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: streamPublicID,
            mediaType: .text,
            content: messageData
        )

        let payload = try thoughtModel.serialize()
        try await client.sendMessage(payload)

        await MainActor.run {
            messages.append(message)
        }
    }

    private func generatePublicID(content: Data) -> Data {
        let hashData = content
        return SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }

    func handleIncomingMessage(_ data: Data) async {
        print("\n=== handleIncomingMessage ===")
        guard let messageType = data.first else {
            print("No message type byte found")
            return
        }
        print("Message type: 0x\(String(format: "%02X", messageType))")

        let messageData = data.dropFirst()

        switch messageType {
        case 0x04: // Rewrapped key
            print("Routing to handleRewrappedKeyMessage")
            await handleRewrappedKeyMessage(messageData)

        case 0x05, 0x06: // NATS message/event
            print("Routing to NATS message handler")
            Task {
                await handleNATSMessage(messageData)
            }

        default:
            print("Unknown message type: 0x\(String(format: "%02X", messageType))")
        }
    }

    private func handleRewrappedKeyMessage(_ data: Data) async {
        print("\n=== handleRewrappedKeyMessage ===")
        print("Message length: \(data.count)")

        guard data.count == 93 else {
            if data.count == 33 {
                let identifier = data
                print("Received DENY for EPK: \(identifier.hexEncodedString())")
                pendingThoughts.removeValue(forKey: identifier)
                return
            }
            print("Invalid rewrapped key length: \(data.count)")
            return
        }

        let identifier = data.prefix(33)
        print("Looking for thought with EPK: \(identifier.hexEncodedString())")
        print("Current pending thoughts: \(pendingThoughts.keys.map { $0.hexEncodedString() })")

        // Find corresponding thought
        guard let (header, _, nano) = pendingThoughts.removeValue(forKey: identifier) else {
            print("❌ No pending thought found for EPK: \(identifier.hexEncodedString())")
            return
        }

        print("✅ Found matching thought!")
        let keyData = data.suffix(60)
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16
        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

        do {
            print("Attempting to decrypt rewrapped key...")
            let symmetricKey = try client.decryptRewrappedKey(
                nonce: nonce,
                rewrappedKey: rewrappedKey,
                authTag: authTag
            )
            print("Successfully decrypted rewrapped key")

            // Decrypt the thought payload
            print("Attempting to decrypt thought payload...")
            let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
            print("Successfully decrypted thought payload")

            // Process decrypted thought
            Task {
                print("Processing decrypted thought...")
                await handleDecryptedThought(
                    payload: decryptedData,
                    policy: ArkavoPolicy(header.policy),
                    nano: nano
                )
            }
        } catch {
            print("❌ Error processing rewrapped key: \(error)")
        }
    }

    private func handleNATSMessage(_ data: Data) async {
        do {
            let parser = BinaryParser(data: data)
            let header = try parser.parseHeader()
            let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
            let nano = NanoTDF(header: header, payload: payload, signature: nil)

            let epk = header.ephemeralPublicKey
            print("Parsed NATS message - EPK: \(epk.hexEncodedString())")

            // Store with correct types
            pendingThoughts[epk] = (
                header: header,
                payload: payload,
                nano: nano
            )
            print("Stored thought in pendingThoughts. Current count: \(pendingThoughts.count)")

            // Send rewrap message
            let rewrapMessage = RewrapMessage(header: header)
            try await client.sendMessage(rewrapMessage.toData())
            print("Sent rewrap message for EPK: \(epk.hexEncodedString())")
        } catch {
            print("Error processing NATS message: \(error)")
        }
    }

    func processStreamThoughts(_ stream: Stream) async {
        print("\nProcessing stream thoughts:")
        for thought in stream.thoughts {
            do {
                print("\nProcessing thought: \(thought.publicID.hexEncodedString())")
                // Check if already processed
                if processedMessageIds.contains(thought.publicID) {
                    print("⚠️ Skipping duplicate thought: \(thought.publicID.hexEncodedString())")
                    continue
                }
                let parser = BinaryParser(data: thought.nano)
                let header = try parser.parseHeader()
                let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
                let nano = NanoTDF(header: header, payload: payload, signature: nil)

                print("Parsed thought - EPK: \(header.ephemeralPublicKey.hexEncodedString())")

                // Store in pending thoughts
                pendingThoughts[header.ephemeralPublicKey] = (header, payload, nano)

                // Send rewrap message
                let rewrapMessage = RewrapMessage(header: header)
                try await client.sendMessage(rewrapMessage.toData())
                print("Sent rewrap message for EPK: \(header.ephemeralPublicKey.hexEncodedString())")
            } catch {
                print("Error processing thought: \(error)")
            }
        }
    }

    private func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async {
        print("\nHandling decrypted thought:")
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)
            print("Deserialized thought model")
            print("Media type: \(thoughtModel.mediaType)")
            // Check if we've already processed this message
            if processedMessageIds.contains(thoughtModel.publicID) {
                print("⚠️ Skipping duplicate message with ID: \(thoughtModel.publicID.hexEncodedString())")
                return
            }
            // Process content based on media type
            let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)
            print("Processed content: \(displayContent)")

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
                // Add this line to prevent reprocessing:
                processedMessageIds.insert(thoughtModel.publicID)
                print("✅ Added message to chat view - Type: \(thoughtModel.mediaType)")

                // Debug current messages
                print("Current messages:")
                for (index, msg) in messages.enumerated() {
                    print("[\(index)] \(msg.username) [\(msg.mediaType)]: \(msg.content)")
                }
            }
        } catch {
            print("❌ Error handling decrypted thought: \(error)")
        }
    }

    private func processContent(_ content: Data, mediaType: MediaType) -> String {
        switch mediaType {
        case .text:
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
}

// MARK: - ArkavoClient Delegate

extension ChatViewModel: ArkavoClientDelegate {
    nonisolated func clientDidChangeState(_: ArkavoClient, state: ArkavoClientState) {
        Task { @MainActor in
            self.connectionState = state
        }
    }

    nonisolated func clientDidReceiveMessage(_: ArkavoClient, message: Data) {
        Task { @MainActor in
            print("\n=== clientDidReceiveMessage ===")
            await self.handleIncomingMessage(message)
        }
    }

    nonisolated func clientDidReceiveError(_: ArkavoClient, error: Error) {
        Task { @MainActor in
            print("Arkavo client error: \(error)")
            // You might want to update UI state here
            // self.errorMessage = error.localizedDescription
            // self.showError = true
        }
    }
}

// MARK: - Enhanced ChatView

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showingAttachmentPicker = false
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasProcessedThoughts = false // Add this line
    let stream: Stream? // Add this line

    var body: some View {
        VStack(spacing: 0) {
            connectionStatusBar

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            MessageInputBar(
                messageText: $messageText,
                placeholder: "Type a message...",
                onAttachmentTap: { showingAttachmentPicker.toggle() },
                onSend: {
                    Task {
                        do {
                            try await viewModel.sendMessage(content: messageText)
                            messageText = ""
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            )
        }
        .task {
            if !hasProcessedThoughts, let stream {
                await viewModel.processStreamThoughts(stream)
                hasProcessedThoughts = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var connectionStatusBar: some View {
        HStack {
            switch viewModel.connectionState {
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected")
            case .connecting, .authenticating:
                ProgressView()
                Text("Connecting...")
            case .disconnected:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Disconnected")
            case let .error(error):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Error: \(error.localizedDescription)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(Color(.systemBackground))
        .shadow(radius: 1)
    }
}

// MARK: - Supporting Views

struct MessageInputBar: View {
    @Binding var messageText: String
    let placeholder: String
    let onAttachmentTap: () -> Void
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onAttachmentTap) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }

                TextField(placeholder, text: $messageText)
                    .textFieldStyle(.roundedBorder)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty ? .gray : .blue)
                }
                .disabled(messageText.isEmpty)
            }
            .padding()
        }
        .background(.bar)
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(message.username.prefix(1))
                        .font(.headline)
                        .foregroundColor(.blue)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    if message.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(.orange)
                    }

                    Text(message.username)
                        .font(.headline)

                    Image(systemName: message.mediaType.icon)
                        .foregroundColor(.blue)

                    Text(message.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Content
                Group {
                    switch message.mediaType {
                    case .text:
                        Text(message.content)
                            .font(.body)
                            .textSelection(.enabled)

                    case .image:
                        ImageMessageView(imageData: message.rawContent)

                    case .video:
                        VStack(alignment: .leading) {
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 200)
                                .overlay(
                                    Image(systemName: "play.rectangle.fill")
                                        .foregroundColor(.gray)
                                )
                        }

                    case .audio:
                        VStack(alignment: .leading) {
                            Text(message.content)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 50)
                                .overlay(
                                    Image(systemName: "waveform")
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                }

                // Reactions
                if !message.reactions.isEmpty {
                    HStack {
                        ForEach(message.reactions) { reaction in
                            ReactionButton(reaction: reaction)
                        }
                    }
                }
            }
        }
    }
}

struct ImageMessageView: View {
    let imageData: Data
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var isExpanded = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onTapGesture {
                        isExpanded = true
                    }
                    .fullScreenCover(isPresented: $isExpanded) {
                        FullScreenImageView(image: image)
                    }
            } else if isLoading {
                ProgressView()
                    .frame(height: 200)
            } else {
                errorView
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private var errorView: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text("Failed to load image")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(height: 200)
    }

    private func loadImage() {
        isLoading = true
        if let uiImage = UIImage(data: imageData) {
            image = uiImage
        }
        isLoading = false
    }
}

struct FullScreenImageView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @GestureState private var magnifyBy = CGFloat(1.0)

    var body: some View {
        NavigationView {
            GeometryReader { proxy in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale * magnifyBy)
                    .gesture(magnification)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                scale *= value
            }
    }
}

struct ReactionButton: View {
    let reaction: MessageReaction

    var body: some View {
        Button(action: { /* Toggle reaction */ }) {
            HStack {
                Text(reaction.emoji)
                Text("\(reaction.count)")
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(reaction.hasReacted ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.2))
            .cornerRadius(12)
        }
    }
}

// MARK: - Enhanced Message Models

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let userId: String
    let username: String
    let content: String
    let timestamp: Date
    let attachments: [MessageAttachment]
    var reactions: [MessageReaction]
    var isPinned: Bool
    let publicID: Data
    let creatorPublicID: Data
    let mediaType: MediaType
    let rawContent: Data // Store original content for media handling

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id
    }
}

struct MessageAttachment: Identifiable {
    let id: String
    let type: AttachmentType
    let url: String
}

enum AttachmentType {
    case image
    case video
    case file
}

struct MessageReaction: Identifiable {
    let id: String
    let emoji: String
    var count: Int
    var hasReacted: Bool
}
