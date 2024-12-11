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
    let channel: Channel?
    let creator: Creator?
    @State private var messages: [ChatMessage] = []
    @State private var messageText = ""
    @State private var showingAttachmentPicker = false

    init(channel: Channel? = nil, creator: Creator? = nil) {
        self.channel = channel
        self.creator = creator
    }

    private var title: String {
        if let channel {
            return "#\(channel.name)"
        }
        if let creator {
            return creator.name
        }
        return "Chat"
    }

    private var placeholder: String {
        if let channel {
            return "Message in #\(channel.name)"
        }
        if let creator {
            return "Message in \(creator.name)'s chat"
        }
        return "Type a message..."
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredMessages) { message in
                        MessageRow(message: message)
                    }
                }
                .padding()
            }

            // Message Input
            MessageInputBar(
                messageText: $messageText,
                placeholder: placeholder,
                onAttachmentTap: { showingAttachmentPicker.toggle() },
                onSend: sendMessage
            )
        }
        .navigationTitle(title)
        .onAppear {
            loadMessages()
        }
    }

    private var filteredMessages: [ChatMessage] {
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

    private func loadMessages() {
        // Load messages based on channel.id and/or creator.id
        messages = ChatMessage.sampleMessages
    }

    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        // Create and send message
        _ = ChatMessage(
            id: UUID().uuidString,
            userId: "currentUser",
            username: "Current User",
            content: messageText,
            timestamp: Date(),
            attachments: [],
            reactions: [],
            isPinned: false,
            channelId: channel?.id,
            creatorId: creator?.id
        )
        // Add to messages array or send to backend
        messageText = ""
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

// MARK: - Preview

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ChatView(
                channel: Channel(
                    id: "channel1",
                    name: "general",
                    type: .text,
                    unreadCount: 0,
                    isActive: true
                )
            )
        }

        NavigationStack {
            ChatView(
                creator: Creator(
                    id: "creator1",
                    name: "Digital Art Master",
                    imageURL: "https://example.com/creator1",
                    latestUpdate: "Just posted a new digital painting tutorial!",
                    tier: .premium,
                    socialLinks: [],
                    notificationCount: 3,
                    bio: "Professional digital artist with 10+ years of experience."
                )
            )
        }
    }
}
