import SwiftUI

// MARK: - Message Models

struct ChatMessage: Identifiable {
    let id: String
    let userId: String
    let username: String
    let content: String
    let timestamp: Date
    let attachments: [MessageAttachment]
    var reactions: [MessageReaction]
    var isPinned: Bool
    var channelId: String?
    var creatorId: String?
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

// MARK: - Chat View

struct ChatView: View {
    @StateObject var viewModel: ChatViewModel
    @State private var messageText = ""
    @State private var showingAttachmentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.filteredMessages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            MessageInputBar(
                messageText: $messageText,
                placeholder: "..",
                onAttachmentTap: { showingAttachmentPicker.toggle() },
                onSend: {
                    viewModel.sendMessage(content: messageText)
                    messageText = ""
                }
            )
        }
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

// MARK: - Sample Data

extension ChatMessage {
    static let sampleMessages = [
        ChatMessage(
            id: "1",
            userId: "user1",
            username: "John Doe",
            content: "Hello everyone! 👋",
            timestamp: Date().addingTimeInterval(-3600),
            attachments: [],
            reactions: [
                MessageReaction(id: "1", emoji: "👍", count: 3, hasReacted: true),
                MessageReaction(id: "2", emoji: "❤️", count: 2, hasReacted: false),
            ],
            isPinned: true,
            channelId: "channel1",
            creatorId: nil
        ),
        ChatMessage(
            id: "2",
            userId: "user2",
            username: "Jane Smith",
            content: "Hi John! How's the project coming along?",
            timestamp: Date().addingTimeInterval(-1800),
            attachments: [],
            reactions: [],
            isPinned: false,
            channelId: "channel1",
            creatorId: nil
        ),
    ]
}

// MARK: - ChatViewModel

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var channel: Channel?
    @Published var creator: Creator?

    init(channel: Channel? = nil, creator: Creator? = nil) {
        self.channel = channel
        self.creator = creator
        loadInitialMessages()
    }

    private func loadInitialMessages() {
        // In real app, fetch from backend
        messages = ChatMessage.sampleMessages
    }

    func sendMessage(content: String) {
        let newMessage = ChatMessage(
            id: UUID().uuidString,
            userId: "currentUser", // In real app, get from auth
            username: "Current User", // In real app, get from auth
            content: content,
            timestamp: Date(),
            attachments: [],
            reactions: [],
            isPinned: false,
            channelId: channel?.id,
            creatorId: creator?.id
        )

        withAnimation {
            messages.append(newMessage)
        }

        // In real app, send to backend
    }

    var filteredMessages: [ChatMessage] {
        messages.filter { message in
            if let channel {
                return message.channelId == channel.id
            }
            if let creator {
                return message.creatorId == creator.id
            }
            return false
        }
    }
}
