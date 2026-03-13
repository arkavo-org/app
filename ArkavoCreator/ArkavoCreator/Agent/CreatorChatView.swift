import ArkavoKit
import SwiftUI

/// Chat interface for messaging with an A2A agent (macOS)
struct CreatorChatView: View {
    @ObservedObject var agentService: CreatorAgentService

    let agent: AgentEndpoint
    let session: ChatSession

    @State private var messageText = ""
    @State private var messages: [CreatorAgentMessage] = []
    @State private var isStreamingResponse = false
    @State private var currentStreamingMessage: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Chat messages
            messagesView

            // Message input bar
            inputBar
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .foregroundColor(.secondary)
                    Text(agent.metadata.model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            messages.append(CreatorAgentMessage(
                id: "system-welcome",
                role: .system,
                content: "Chat session started with \(agent.metadata.name)",
                timestamp: session.createdAt
            ))
            isInputFocused = true
        }
        .onChange(of: agentService.streamingText[session.id]) { _, newText in
            currentStreamingMessage = newText ?? ""
        }
        .onChange(of: agentService.streamingStates[session.id]) { oldValue, newValue in
            if oldValue == true && newValue == false {
                finalizeStreamingMessage()
            } else if newValue == true {
                isStreamingResponse = true
            } else {
                isStreamingResponse = false
            }
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { message in
                        CreatorMessageRow(message: message)
                            .id(message.id)
                    }

                    if isStreamingResponse {
                        CreatorMessageRow(message: CreatorAgentMessage(
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
                TextField("Message \(agent.metadata.name)...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($isInputFocused)
                    .disabled(isStreamingResponse)
                    .lineLimit(1...5)
                    .onSubmit {
                        Task {
                            await sendMessage()
                        }
                    }

                Button(action: {
                    Task {
                        await sendMessage()
                    }
                }) {
                    Image(systemName: isStreamingResponse ? "stop.circle.fill" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(messageText.isEmpty && !isStreamingResponse ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty && !isStreamingResponse)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions

    private func sendMessage() async {
        guard !messageText.isEmpty else { return }

        let userMessage = CreatorAgentMessage(
            id: UUID().uuidString,
            role: .user,
            content: messageText,
            timestamp: Date()
        )

        messages.append(userMessage)
        let sentContent = messageText
        messageText = ""

        do {
            try await agentService.sendMessage(sessionId: session.id, content: sentContent)
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            showError = true
            isStreamingResponse = false
            currentStreamingMessage = ""
        }
    }

    private func finalizeStreamingMessage() {
        guard let finalText = agentService.finalizeStream(sessionId: session.id),
              !finalText.isEmpty else {
            isStreamingResponse = false
            currentStreamingMessage = ""
            return
        }

        let agentResponse = CreatorAgentMessage(
            id: UUID().uuidString,
            role: .agent,
            content: finalText,
            timestamp: Date()
        )

        messages.append(agentResponse)
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

struct CreatorAgentMessage: Identifiable {
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

// MARK: - Message Row

struct CreatorMessageRow: View {
    let message: CreatorAgentMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(headerText)
                        .font(.headline)
                        .foregroundColor(headerColor)

                    Spacer()

                    Text(message.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var avatarView: some View {
        avatarBackground
            .frame(width: 36, height: 36)
            .overlay(
                Image(systemName: avatarIcon)
                    .font(.subheadline)
                    .foregroundColor(.white)
            )
    }

    private var headerText: String {
        switch message.role {
        case .user: "You"
        case .agent: "Agent"
        case .system: "System"
        }
    }

    private var headerColor: Color {
        switch message.role {
        case .user: .primary
        case .agent: .blue
        case .system: .secondary
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
        case .user: "person.fill"
        case .agent: "cpu"
        case .system: "info.circle.fill"
        }
    }
}
