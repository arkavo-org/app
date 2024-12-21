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

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        connectionState = client.currentState
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
            creatorPublicID: profile.publicID
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

    func handleIncomingMessage(_ data: Data) {
        Task {
            do {
                let thoughtModel = try ThoughtServiceModel.deserialize(from: data)
                let content = String(data: thoughtModel.content, encoding: .utf8) ?? ""

                let message = ChatMessage(
                    id: UUID().uuidString,
                    userId: thoughtModel.creatorPublicID.base58EncodedString,
                    username: "User-\(thoughtModel.creatorPublicID.prefix(6).base58EncodedString)",
                    content: content,
                    timestamp: Date(),
                    attachments: [],
                    reactions: [],
                    isPinned: false,
                    publicID: thoughtModel.publicID,
                    creatorPublicID: thoughtModel.creatorPublicID
                )

                await MainActor.run {
                    messages.append(message)
                }
            } catch {
                print("Error handling incoming message: \(error)")
            }
        }
    }

    func processStreamThoughts(_ stream: Stream) async {
        for thought in stream.thoughts {
            do {
                let parser = BinaryParser(data: thought.nano)
                print("thought parsed successfully / \(thought.publicID)")
                try await client.sendMessage(RewrapMessage(header: parser.parseHeader()).toData())
            } catch {
                print("Error processing thought: \(error)")
            }
        }
    }

    private func handleDecryptedThought(payload: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async {
        do {
            // Deserialize the thought model from the decrypted payload
            let thoughtModel = try ThoughtServiceModel.deserialize(from: payload)

            // Create chat message from the thought
            let message = ChatMessage(
                id: UUID().uuidString,
                userId: thoughtModel.creatorPublicID.base58EncodedString,
                username: "User-\(thoughtModel.creatorPublicID.prefix(6).base58EncodedString)",
                content: String(data: thoughtModel.content, encoding: .utf8) ?? "",
                timestamp: Date(),
                attachments: [],
                reactions: [],
                isPinned: false,
                publicID: thoughtModel.publicID,
                creatorPublicID: thoughtModel.creatorPublicID
            )

            // Update UI on main thread
            await MainActor.run {
                messages.append(message)
            }
        } catch {
            print("Error handling decrypted thought: \(error)")
        }
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
            self.handleIncomingMessage(message)
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

                    Text(message.timestamp, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Content
                Text(message.content)
                    .font(.body)

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
