import SwiftUI

struct ChatView: View {
    let group: ForumGroup
    @EnvironmentObject var messagingViewModel: MessagingViewModel
    @EnvironmentObject var encryptionManager: EncryptionManager
    @EnvironmentObject var councilManager: AICouncilManager
    @EnvironmentObject var appState: AppState
    @State private var messageText = ""
    @State private var showingEncryptionInfo = false
    @State private var showingCouncil = false
    @State private var selectedMessageForInsight: ForumMessage?

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
                HStack(spacing: 12) {
                    // AI Council button
                    Button(action: {
                        showingCouncil.toggle()
                    }) {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))
                    }
                    .help("AI Council")

                    // Encryption button
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
        }
        .sheet(isPresented: $showingCouncil) {
            CouncilView(messages: groupMessages)
        }
        .sheet(item: $selectedMessageForInsight) { message in
            MessageInsightView(message: message)
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
    @State private var showingInsightMenu = false

    var body: some View {
        HStack(alignment: .top) {
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

                HStack(spacing: 8) {
                    // AI insight button (for others' messages)
                    if !isCurrentUser {
                        Button(action: {
                            showingInsightMenu.toggle()
                        }) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Get AI insight")
                        .popover(isPresented: $showingInsightMenu) {
                            QuickInsightMenu(message: message)
                        }
                    }

                    // Message content
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

// MARK: - AI Council Views

struct QuickInsightMenu: View {
    let message: ForumMessage
    @EnvironmentObject var councilManager: AICouncilManager
    @State private var selectedAgent: CouncilAgentType?
    @State private var insight: CouncilInsight?
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Council Insight")
                .font(.headline)

            Text("Select an agent perspective:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Agent selection
            VStack(spacing: 8) {
                ForEach(CouncilAgentType.allCases) { agentType in
                    Button(action: {
                        getInsight(type: agentType)
                    }) {
                        HStack {
                            Image(systemName: agentType.icon)
                                .foregroundColor(agentType.color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(agentType.rawValue)
                                    .font(.subheadline)
                                Text(agentType.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if isLoading && selectedAgent == agentType {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }

            if let insight = insight {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: insight.agentType.icon)
                            .foregroundColor(insight.agentType.color)
                        Text(insight.agentType.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    ScrollView {
                        Text(insight.content)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .padding()
        .frame(width: 400)
    }

    private func getInsight(type: CouncilAgentType) {
        selectedAgent = type
        isLoading = true

        Task {
            do {
                let newInsight = try await councilManager.getInsight(for: message, type: type)
                await MainActor.run {
                    insight = newInsight
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("Error getting insight: \(error)")
            }
        }
    }
}

struct MessageInsightView: View {
    let message: ForumMessage
    @EnvironmentObject var councilManager: AICouncilManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))

                Text("AI Council Insight")
                    .font(.title2)

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Message context
            VStack(alignment: .leading, spacing: 8) {
                Text("Message from \(message.senderName):")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(message.content)
                    .font(.body)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
            }
            .padding(.horizontal)

            Divider()

            // Quick Insight Menu
            QuickInsightMenu(message: message)

            Spacer()
        }
        .frame(width: 500, height: 600)
    }
}

struct CouncilView: View {
    let messages: [ForumMessage]
    @EnvironmentObject var councilManager: AICouncilManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: CouncilTab = .insights
    @State private var researchTopic = ""
    @State private var summary: CouncilInsight?
    @State private var researchResult: CouncilInsight?

    enum CouncilTab: String, CaseIterable {
        case insights = "Insights"
        case summary = "Summary"
        case research = "Research"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundColor(Color(red: 1.0, green: 0.4, blue: 0.0))

                Text("AI Council")
                    .font(.title)

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
            .padding()

            Divider()

            // Tabs
            Picker("Mode", selection: $selectedTab) {
                ForEach(CouncilTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            Group {
                switch selectedTab {
                case .insights:
                    InsightsTab(messages: messages)
                case .summary:
                    SummaryTab(messages: messages, summary: $summary)
                case .research:
                    ResearchTab(messages: messages, topic: $researchTopic, result: $researchResult)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 600)
    }
}

struct InsightsTab: View {
    let messages: [ForumMessage]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Per-Message Insights")
                    .font(.headline)
                    .padding(.horizontal)

                Text("Click the AI icon next to any message to get insights from different perspectives.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                Divider()

                ForEach(CouncilAgentType.allCases) { agentType in
                    HStack(spacing: 12) {
                        Image(systemName: agentType.icon)
                            .font(.title2)
                            .foregroundColor(agentType.color)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(agentType.rawValue)
                                .font(.headline)
                            Text(agentType.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct SummaryTab: View {
    let messages: [ForumMessage]
    @Binding var summary: CouncilInsight?
    @EnvironmentObject var councilManager: AICouncilManager
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            if let summary = summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "diagram.connected")
                                .foregroundColor(.green)
                            Text("Conversation Summary")
                                .font(.headline)
                        }

                        Text(summary.content)
                            .font(.body)
                            .textSelection(.enabled)

                        Text("Generated: \(summary.timestamp.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "diagram.connected")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Conversation Summary")
                        .font(.title2)

                    Text("Get an AI-generated summary of the conversation with key points and insights.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                    } else {
                        Button("Generate Summary") {
                            generateSummary()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
        }
    }

    private func generateSummary() {
        isLoading = true

        Task {
            do {
                let result = try await councilManager.summarizeConversation(messages)
                await MainActor.run {
                    summary = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("Error generating summary: \(error)")
            }
        }
    }
}

struct ResearchTab: View {
    let messages: [ForumMessage]
    @Binding var topic: String
    @Binding var result: CouncilInsight?
    @EnvironmentObject var councilManager: AICouncilManager
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 20) {
            if let result = result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "book")
                                .foregroundColor(.purple)
                            Text("Research: \(topic)")
                                .font(.headline)
                        }

                        Text(result.content)
                            .font(.body)
                            .textSelection(.enabled)

                        HStack {
                            Spacer()
                            Button("New Research") {
                                result = nil
                                topic = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "book")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)

                    Text("Research Mode")
                        .font(.title2)

                    Text("Enter a topic to research based on the conversation context.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    TextField("Research topic...", text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                    } else {
                        Button("Research") {
                            researchTopic()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(topic.isEmpty)
                    }
                }
                .padding()
            }
        }
    }

    private func researchTopic() {
        isLoading = true

        Task {
            do {
                let research = try await councilManager.researchTopic(topic, context: messages)
                await MainActor.run {
                    result = research
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
                print("Error researching: \(error)")
            }
        }
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
