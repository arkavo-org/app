import SwiftUI

struct ChatView: View {
    let group: ForumGroup
    @EnvironmentObject var messagingViewModel: MessagingViewModel
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var showingEncryptionToggle = false

    var groupMessages: [ForumMessage] {
        messagingViewModel.getMessages(for: group.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeaderView(group: group)

            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groupMessages) { message in
                            MessageBubble(message: message, isCurrentUser: message.senderId == appState.currentUser)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: groupMessages.count) { _, _ in
                    // Auto-scroll to bottom when new messages arrive
                    if let lastMessage = groupMessages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Message Input
            MessageInputView(
                messageText: $messageText,
                onSend: {
                    sendMessage()
                }
            )
        }
        .navigationTitle(group.name)
        .navigationSubtitle("\(group.memberCount) members")
        .onAppear {
            messagingViewModel.loadMessages(for: group.id)
        }
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        Task {
            await messagingViewModel.sendMessage(content: text, groupId: group.id)
            messageText = ""
        }
    }
}

// MARK: - Chat Header

struct ChatHeaderView: View {
    let group: ForumGroup

    var body: some View {
        HStack {
            Circle()
                .fill(group.color)
                .frame(width: 12, height: 12)

            Text(group.name)
                .font(.headline)

            Spacer()

            Text("\(group.memberCount) members")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ForumMessage
    let isCurrentUser: Bool

    var body: some View {
        HStack {
            if isCurrentUser {
                Spacer()
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                // Sender name (only show for others)
                if !isCurrentUser {
                    Text(message.senderName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))
                }

                // Message content
                HStack(spacing: 8) {
                    Text(message.content)
                        .font(.body)
                        .foregroundColor(isCurrentUser ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isCurrentUser
                                ? Color(red: 1.0, green: 0.4, blue: 0.0)
                                : Color(NSColor.controlBackgroundColor)
                        )
                        .cornerRadius(16)

                    // Encryption indicator
                    if message.isEncrypted {
                        Image(systemName: "lock.shield.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }

                // Timestamp
                Text(formatTimestamp(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isCurrentUser {
                Spacer()
            }
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday " + date.formatted(date: .omitted, time: .shortened)
        } else {
            formatter.dateFormat = "MMM d, HH:mm"
        }

        return formatter.string(from: date)
    }
}

// MARK: - Message Input

struct MessageInputView: View {
    @Binding var messageText: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Type a message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(20)
                .lineLimit(1...5)
                .onSubmit {
                    if !messageText.isEmpty {
                        onSend()
                    }
                }

            // Send button
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .gray : Color(red: 1.0, green: 0.4, blue: 0.0))
            }
            .buttonStyle(.plain)
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Preview

#Preview {
    let sampleGroup = ForumGroup(
        name: "General",
        color: Color(red: 1.0, green: 0.4, blue: 0.0),
        memberCount: 142,
        description: "General discussion"
    )

    return ChatView(group: sampleGroup)
        .frame(width: 800, height: 600)
}
