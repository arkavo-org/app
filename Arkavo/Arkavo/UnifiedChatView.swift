import ArkavoKit
import OSLog
import SwiftUI

/// Message model for unified chat
struct UnifiedChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isFromUser: Bool
    let timestamp: Date
    var isStreaming: Bool = false

    init(id: UUID = UUID(), content: String, isFromUser: Bool, timestamp: Date = Date(), isStreaming: Bool = false) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

/// Unified chat view that routes to the appropriate backend based on contact type
struct UnifiedChatView: View {
    let contact: Profile
    let agentService: AgentService

    @Environment(\.dismiss) var dismiss
    @State private var messageText = ""
    @State private var messages: [UnifiedChatMessage] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var sessionId: String?
    @State private var isConnecting = false

    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "UnifiedChatView")

    var avatarGradient: LinearGradient {
        if contact.isAgent {
            return LinearGradient(
                colors: [Color.green, Color.teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [Color.blue, Color.purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(messages) { message in
                                MessageBubble(message: message, avatarGradient: avatarGradient, contactName: contact.name)
                                    .id(message.id)
                            }

                            // Streaming indicator
                            if let sessionId = sessionId, agentService.isStreaming(sessionId: sessionId) {
                                HStack {
                                    StreamingIndicator()
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Error message
                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                // Input area
                HStack(spacing: 12) {
                    TextField("Message...", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .padding(12)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(20)

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(avatarGradient)
                    }
                    .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle(contact.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        Task {
                            await closeSession()
                        }
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack {
                        // Contact avatar
                        ZStack {
                            Circle()
                                .fill(avatarGradient.opacity(0.3))
                                .frame(width: 32, height: 32)

                            if contact.isAgent {
                                Image(systemName: contact.contactTypeEnum.icon)
                                    .font(.caption)
                                    .foregroundStyle(avatarGradient)
                            } else {
                                Text(contact.name.prefix(1).uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(avatarGradient)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(.headline)

                            if contact.isAgent {
                                Text(contact.contactTypeEnum.displayName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        connectionStatusIndicator
                    }
                }
            }
        }
        .task {
            await setupChat()
        }
        .onReceive(agentService.$streamingText) { streamingTexts in
            handleStreamingUpdate(streamingTexts)
        }
        .onReceive(agentService.$streamingStates) { states in
            handleStreamingStateChange(states)
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionStatusIndicator: some View {
        if contact.isAgent {
            let isConnected = agentService.isConnected(to: contact.agentID ?? "")
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
        } else {
            EmptyView()
        }
    }

    // MARK: - Chat Setup

    private func setupChat() async {
        guard contact.isAgent else {
            // For human contacts, chat is handled differently (P2P messaging)
            logger.log("[UnifiedChat] Human contact - P2P messaging not implemented in this view")
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        guard let agentID = contact.agentID else {
            error = "Invalid agent contact"
            return
        }

        // Connect to agent if not already connected
        if !agentService.isConnected(to: agentID) {
            do {
                // Find the agent endpoint
                guard let endpoint = agentService.discoveredAgents.first(where: { $0.id == agentID }) else {
                    // For delegated agents, try connecting via Arkavo network
                    logger.log("[UnifiedChat] Agent not discovered locally, using Arkavo network")
                    // TODO: Implement Arkavo network routing
                    error = "Agent not available on local network"
                    return
                }

                try await agentService.connect(to: endpoint)
                logger.log("[UnifiedChat] Connected to agent: \(agentID)")
            } catch {
                logger.error("[UnifiedChat] Failed to connect: \(String(describing: error))")
                self.error = "Failed to connect to agent"
                return
            }
        }

        // Open chat session
        do {
            let session = try await agentService.openChatSession(with: agentID)
            sessionId = session.id
            logger.log("[UnifiedChat] Opened session: \(session.id)")

            // Add welcome message
            let welcomeMessage = UnifiedChatMessage(
                content: "Connected to \(contact.name). How can I help you?",
                isFromUser: false
            )
            messages.append(welcomeMessage)
        } catch {
            logger.error("[UnifiedChat] Failed to open session: \(String(describing: error))")
            self.error = "Failed to start chat session"
        }
    }

    // MARK: - Send Message

    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Add user message to chat
        let userMessage = UnifiedChatMessage(content: trimmedText, isFromUser: true)
        messages.append(userMessage)
        messageText = ""
        error = nil

        // Route based on contact type
        if contact.isAgent {
            sendAgentMessage(trimmedText)
        } else {
            sendHumanMessage(trimmedText)
        }
    }

    private func sendAgentMessage(_ content: String) {
        guard let sessionId = sessionId else {
            error = "No active session"
            return
        }

        isLoading = true

        Task {
            do {
                // Add placeholder for streaming response
                let placeholderId = UUID()
                await MainActor.run {
                    let placeholder = UnifiedChatMessage(id: placeholderId, content: "", isFromUser: false, isStreaming: true)
                    messages.append(placeholder)
                }

                try await agentService.sendMessage(sessionId: sessionId, content: content)
                logger.log("[UnifiedChat] Message sent")
            } catch {
                logger.error("[UnifiedChat] Failed to send: \(String(describing: error))")
                await MainActor.run {
                    self.error = "Failed to send message"
                    // Remove placeholder on error
                    if let lastIndex = messages.indices.last, messages[lastIndex].isStreaming {
                        messages.remove(at: lastIndex)
                    }
                }
            }

            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func sendHumanMessage(_ content: String) {
        // For human contacts, use P2P encrypted messaging
        // This would integrate with the existing P2P messaging system
        logger.log("[UnifiedChat] Human P2P messaging not implemented in this view")
        error = "P2P messaging coming soon"
    }

    // MARK: - Streaming Updates

    private func handleStreamingUpdate(_ streamingTexts: [String: String]) {
        guard let sessionId = sessionId,
              let text = streamingTexts[sessionId],
              !text.isEmpty else { return }

        // Update the last streaming message
        if let index = messages.lastIndex(where: { $0.isStreaming }) {
            messages[index] = UnifiedChatMessage(
                id: messages[index].id,
                content: text,
                isFromUser: false,
                timestamp: messages[index].timestamp,
                isStreaming: true
            )
        }
    }

    private func handleStreamingStateChange(_ states: [String: Bool]) {
        guard let sessionId = sessionId else { return }

        let isStreaming = states[sessionId] ?? false

        if !isStreaming {
            // Streaming ended - finalize the message
            if let index = messages.lastIndex(where: { $0.isStreaming }) {
                // Get final text from AgentService
                let finalText = agentService.finalizeStream(sessionId: sessionId) ?? messages[index].content

                if !finalText.isEmpty {
                    messages[index] = UnifiedChatMessage(
                        id: messages[index].id,
                        content: finalText,
                        isFromUser: false,
                        timestamp: messages[index].timestamp,
                        isStreaming: false
                    )
                } else {
                    // Remove empty placeholder
                    messages.remove(at: index)
                }
            }
        }
    }

    // MARK: - Cleanup

    private func closeSession() async {
        guard let sessionId = sessionId else { return }
        await agentService.closeChatSession(sessionId: sessionId)
        logger.log("[UnifiedChat] Closed session: \(sessionId)")
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: UnifiedChatMessage
    let avatarGradient: LinearGradient
    let contactName: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isFromUser {
                Spacer(minLength: 60)
            } else {
                // Contact avatar
                ZStack {
                    Circle()
                        .fill(avatarGradient.opacity(0.3))
                        .frame(width: 28, height: 28)

                    Text(contactName.prefix(1).uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(avatarGradient)
                }
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isFromUser ? avatarGradient : LinearGradient(colors: [Color(.secondarySystemBackground)], startPoint: .leading, endPoint: .trailing))
                    .foregroundColor(message.isFromUser ? .white : .primary)
                    .cornerRadius(18)
                    .overlay(
                        message.isStreaming ?
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(avatarGradient, lineWidth: 1)
                            .opacity(0.5)
                        : nil
                    )

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.isFromUser {
                // User avatar
                Circle()
                    .fill(avatarGradient.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            } else {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Streaming Indicator

struct StreamingIndicator: View {
    @State private var dotOpacity: [Double] = [0.3, 0.3, 0.3]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(dotOpacity[index])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .onAppear {
            animateDots()
        }
    }

    private func animateDots() {
        for i in 0..<3 {
            withAnimation(
                .easeInOut(duration: 0.4)
                .repeatForever(autoreverses: true)
                .delay(Double(i) * 0.15)
            ) {
                dotOpacity[i] = 1.0
            }
        }
    }
}

#Preview {
    let profile = Profile(name: "Test Device Agent")
    profile.contactType = "deviceAgent"
    profile.agentID = "test-device-agent"
    profile.agentPurpose = "Test device agent for preview"

    return UnifiedChatView(
        contact: profile,
        agentService: AgentService()
    )
}
