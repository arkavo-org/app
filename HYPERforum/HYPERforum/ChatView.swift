import SwiftUI

struct ChatView: View {
    let group: ForumGroup
    @EnvironmentObject var messagingViewModel: MessagingViewModel
    @EnvironmentObject var encryptionManager: EncryptionManager
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var showingEncryptionInfo = false

    var groupMessages: [ForumMessage] {
        messagingViewModel.getMessages(for: group.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with encryption status
            ChatHeaderView(group: group, encryptionEnabled: encryptionManager.encryptionEnabled)

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

            // Message Input with encryption toggle
            MessageInputView(
                messageText: $messageText,
                encryptionEnabled: $encryptionManager.encryptionEnabled,
                onSend: {
                    sendMessage()
                },
                onToggleEncryption: {
                    encryptionManager.toggleEncryption()
                }
            )
        }
        .navigationTitle(group.name)
        .navigationSubtitle("\(group.memberCount) members • \(encryptionManager.encryptionEnabled ? "🔒 Encrypted" : "Unencrypted")")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingEncryptionInfo.toggle()
                }) {
                    Image(systemName: encryptionManager.encryptionEnabled ? "lock.shield.fill" : "lock.open")
                        .foregroundColor(encryptionManager.encryptionEnabled ? .green : .secondary)
                }
                .help("Encryption: \(encryptionManager.encryptionEnabled ? "Enabled" : "Disabled")")
                .popover(isPresented: $showingEncryptionInfo) {
                    EncryptionInfoView(encryptionManager: encryptionManager)
                }
            }
        }
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
    let encryptionEnabled: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(group.color)
                .frame(width: 12, height: 12)

            Text(group.name)
                .font(.headline)

            Spacer()

            if encryptionEnabled {
                Image(systemName: "lock.shield.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

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
    @Binding var encryptionEnabled: Bool
    let onSend: () -> Void
    let onToggleEncryption: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Encryption toggle
            Button(action: onToggleEncryption) {
                Image(systemName: encryptionEnabled ? "lock.shield.fill" : "lock.open")
                    .font(.system(size: 20))
                    .foregroundColor(encryptionEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle encryption: \(encryptionEnabled ? "ON" : "OFF")")

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

// MARK: - Encryption Info

struct EncryptionInfoView: View {
    @ObservedObject var encryptionManager: EncryptionManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: encryptionManager.encryptionEnabled ? "lock.shield.fill" : "lock.open")
                    .font(.title)
                    .foregroundColor(encryptionManager.encryptionEnabled ? .green : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("End-to-End Encryption")
                        .font(.headline)
                    Text(encryptionManager.encryptionEnabled ? "Enabled" : "Disabled")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("About Encryption")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Messages are secured using OpenTDF/NanoTDF encryption with policy-based access control.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if encryptionManager.encryptionEnabled {
                    Label("Your messages are protected end-to-end", systemImage: "checkmark.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)

                    Label("Only group members can decrypt", systemImage: "person.3.fill")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Label("Keys managed by Arkavo KAS", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else {
                    Label("Messages are sent without encryption", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Divider()

            Button(action: {
                encryptionManager.toggleEncryption()
            }) {
                HStack {
                    Image(systemName: encryptionManager.encryptionEnabled ? "lock.open" : "lock.shield.fill")
                    Text(encryptionManager.encryptionEnabled ? "Disable Encryption" : "Enable Encryption")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(encryptionManager.encryptionEnabled ? .red : .green)
        }
        .padding()
        .frame(width: 320)
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
