import ArkavoAgent
import SwiftUI

/// Detailed view for a specific agent showing metadata and connection controls
struct AgentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var agentService: AgentService

    let agent: AgentEndpoint
    @State private var isConnecting = false
    @State private var showingChat = false
    @State private var chatSession: ChatSession?
    @State private var errorMessage: String?
    @State private var showError = false

    var isConnected: Bool {
        // LocalAIAgent doesn't need connection - it's in-process
        if isLocalAgent {
            return agentService.isLocalAgentPublishing
        }
        return agentService.isConnected(to: agent.id)
    }

    var isLocalAgent: Bool {
        agent.id.lowercased().contains("local") ||
        agent.metadata.purpose.lowercased().contains("local")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Agent Icon and Status
                    agentHeaderView

                    // Connection Section
                    connectionSection

                    // Metadata Section
                    metadataSection

                    // Chat Sessions Section
                    // LocalAIAgent: Always available (in-process)
                    // Remote agents: Only when connected
                    if isLocalAgent || isConnected {
                        chatSessionsSection
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Agent Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showingChat) {
                if let chatSession {
                    AgentChatView(
                        agentService: agentService,
                        agent: agent,
                        session: chatSession
                    )
                }
            }
        }
    }

    // MARK: - Agent Header View

    private var agentHeaderView: some View {
        VStack(spacing: 16) {
            // Large agent icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)

                Image(systemName: "cpu")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }

            // Agent ID
            Text(agent.id)
                .font(.title2)
                .fontWeight(.semibold)

            // Status badge
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)

                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.subheadline)
                    .foregroundColor(isConnected ? .green : .secondary)
            }
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        VStack(spacing: 16) {
            // Connection button (not needed for LocalAIAgent - it's in-process)
            if isLocalAgent {
                HStack {
                    Image(systemName: "iphone.circle.fill")
                    Text("In-Process Agent")
                    Spacer()
                    Text(isConnected ? "Running" : "Stopped")
                        .foregroundColor(isConnected ? .green : .secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(12)
            } else if isConnecting {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            } else if isConnected {
                Button(action: {
                    Task {
                        await disconnectAgent()
                    }
                }) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                        Text("Disconnect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                }
            } else {
                Button(action: {
                    Task {
                        await connectAgent()
                    }
                }) {
                    HStack {
                        Image(systemName: "link.circle.fill")
                        Text("Connect")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

            // Connection info
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "URL", value: agent.url)
                if let host = agent.host {
                    InfoRow(label: "Host", value: host)
                }
                if let port = agent.port {
                    InfoRow(label: "Port", value: "\(port)")
                }
                InfoRow(label: "Service", value: "_a2a._tcp.")
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Properties")
                .font(.headline)

            VStack(spacing: 8) {
                // Core metadata
                InfoRow(label: "Name", value: agent.metadata.name)
                InfoRow(label: "Model", value: agent.metadata.model)
                InfoRow(label: "Purpose", value: agent.metadata.purpose)

                // Additional properties
                ForEach(Array(agent.metadata.properties.keys.sorted()), id: \.self) { key in
                    if let value = agent.metadata.properties[key] {
                        InfoRow(label: key.capitalized, value: value)
                    }
                }

                if agent.metadata.properties.isEmpty {
                    Text("No additional properties")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Chat Sessions Section

    private var chatSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chat Sessions")
                .font(.headline)

            // LocalAIAgent: Can start chat without connection
            // Remote agents: Need connection first
            if isLocalAgent || isConnected {
                Button(action: {
                    Task {
                        await openChatSession()
                    }
                }) {
                    HStack {
                        Image(systemName: "message.fill")
                        Text("Start New Chat")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                Text("Connect to agent first to start a chat session")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
            }

            // Active sessions list
            if !agentService.getSessions(for: agent.id).isEmpty {
                VStack(spacing: 8) {
                    ForEach(agentService.getSessions(for: agent.id), id: \.id) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Session \(session.id.prefix(8))...")
                                    .font(.subheadline)
                                Text("Started: \(session.createdAt, style: .relative) ago")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button(action: {
                                chatSession = session
                                showingChat = true
                            }) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func connectAgent() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            try await agentService.connect(to: agent)
        } catch {
            errorMessage = "Failed to connect: \(error.localizedDescription)"
            showError = true
        }
    }

    private func disconnectAgent() async {
        await agentService.disconnect(from: agent.id)
    }

    private func openChatSession() async {
        do {
            let session = try await agentService.openChatSession(with: agent.id)
            chatSession = session
            showingChat = true
        } catch {
            errorMessage = "Failed to open chat: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
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
    AgentDetailView(agentService: agentService, agent: mockAgent)
}
