import ArkavoKit
import SwiftUI

/// Chat interface for messaging with an A2A agent
struct AgentChatView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var agentService: AgentService

    let agent: AgentEndpoint
    let session: ChatSession

    @State private var messageText = ""
    @State private var messages: [AgentMessage] = []
    @State private var isStreamingResponse = false
    @State private var currentStreamingMessage: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Chat messages
                messagesView

                // Message input bar
                inputBar
            }
            .navigationTitle(agent.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        Task {
                            await closeSession()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    sessionInfoButton
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { /* Dismisses alert */ }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .onAppear {
                // Add system message showing session info
                messages.append(AgentMessage(
                    id: "system-welcome",
                    role: .system,
                    content: "Chat session started with \(agent.id)",
                    timestamp: session.createdAt
                ))
                isInputFocused = true
            }
            .onChange(of: agentService.streamingText[session.id]) { _, newText in
                // Update streaming message as text arrives
                currentStreamingMessage = newText ?? ""
            }
            .onChange(of: agentService.streamingStates[session.id]) { oldValue, newValue in
                // Handle streaming state changes
                if oldValue == true && newValue == false {
                    // Stream ended, finalize the message
                    finalizeStreamingMessage()
                } else if newValue == true {
                    // Stream started
                    isStreamingResponse = true
                } else {
                    isStreamingResponse = false
                }
            }
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        AgentMessageRow(message: message)
                            .id(message.id)
                    }

                    // Show streaming message if active
                    if isStreamingResponse {
                        AgentMessageRow(message: AgentMessage(
                            id: "streaming",
                            role: .agent,
                            content: currentStreamingMessage.isEmpty ? "Thinking..." : currentStreamingMessage,
                            timestamp: Date()
                        ))
                        .id("streaming")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation {
                    scrollToBottom(proxy: scrollProxy)
                }
            }
            .onChange(of: currentStreamingMessage) { _, _ in
                withAnimation {
                    scrollProxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                TextField("Message \(agent.id)...", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .disabled(isStreamingResponse)

                Button(action: {
                    Task {
                        await sendMessage()
                    }
                }) {
                    Image(systemName: isStreamingResponse ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty && !isStreamingResponse ? .gray : .blue)
                }
                .disabled(messageText.isEmpty && !isStreamingResponse)
            }
            .padding()
        }
        .background(.bar)
    }

    // MARK: - Session Info Button

    private var sessionInfoButton: some View {
        Button(action: {
            // Show session info
        }) {
            Image(systemName: "info.circle")
        }
    }

    // MARK: - Actions

    private func sendMessage() async {
        guard !messageText.isEmpty else { return }

        let userMessage = AgentMessage(
            id: UUID().uuidString,
            role: .user,
            content: messageText,
            timestamp: Date()
        )

        messages.append(userMessage)
        let sentContent = messageText
        messageText = ""

        // Streaming will be managed automatically by AgentService
        do {
            try await agentService.sendMessage(sessionId: session.id, content: sentContent)
            // Stream handler will update currentStreamingMessage via onChange bindings
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            showError = true
            isStreamingResponse = false
            currentStreamingMessage = ""
        }
    }

    private func closeSession() async {
        await agentService.closeChatSession(sessionId: session.id)
        dismiss()
    }

    private func finalizeStreamingMessage() {
        // Get the final text from the stream
        guard let finalText = agentService.finalizeStream(sessionId: session.id),
              !finalText.isEmpty else {
            isStreamingResponse = false
            currentStreamingMessage = ""
            return
        }

        // Add the completed message to the messages array
        let agentResponse = AgentMessage(
            id: UUID().uuidString,
            role: .agent,
            content: finalText,
            timestamp: Date()
        )

        messages.append(agentResponse)

        // Clear streaming state
        isStreamingResponse = false
        currentStreamingMessage = ""
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = messages.last {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        } else if isStreamingResponse {
            proxy.scrollTo("streaming", anchor: .bottom)
        }
    }
}

// MARK: - Agent Message Model

struct AgentMessage: Identifiable {
    let id: String
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole {
        case user
        case agent
        case system
    }
}

// MARK: - Agent Message Row

struct AgentMessageRow: View {
    let message: AgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                // Header
                HStack {
                    Text(headerText)
                        .font(.headline)
                        .foregroundColor(headerColor)

                    Spacer()

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var avatarView: some View {
        avatarBackground
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: avatarIcon)
                    .font(.headline)
                    .foregroundColor(.white)
            )
    }

    private var headerText: String {
        switch message.role {
        case .user:
            return "You"
        case .agent:
            return "Agent"
        case .system:
            return "System"
        }
    }

    private var headerColor: Color {
        switch message.role {
        case .user:
            return .primary
        case .agent:
            return .blue
        case .system:
            return .secondary
        }
    }

    @ViewBuilder
    private var avatarBackground: some View {
        switch message.role {
        case .user:
            Circle().fill(Color.blue.opacity(0.2))
        case .agent:
            Circle().fill(LinearGradient(
                colors: [.purple, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .system:
            Circle().fill(Color.gray.opacity(0.2))
        }
    }

    private var avatarIcon: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .agent:
            return "cpu"
        case .system:
            return "info.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    let agentService = AgentService()
    let mockAgent = AgentEndpoint(
        id: "test-agent",
        url: "ws://10.0.0.101:8342",
        metadata: AgentMetadata(
            name: "Test Agent",
            purpose: "Test agent for preview",
            model: "claude-3-5-sonnet"
        )
    )

    // Create mock session from JSON since ChatSession only has Codable initializers
    let sessionJSON = """
    {
        "session_id": "session-123",
        "created_at": "\(ISO8601DateFormatter().string(from: Date()))",
        "capabilities": {
            "supports_streaming": true,
            "supported_message_types": ["text"],
            "max_message_length": 10000
        }
    }
    """
    let mockSession = try! JSONDecoder().decode(ChatSession.self, from: sessionJSON.data(using: .utf8)!)

    AgentChatView(
        agentService: agentService,
        agent: mockAgent,
        session: mockSession
    )
}
