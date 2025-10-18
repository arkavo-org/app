import ArkavoAgent
import SwiftUI

/// View displaying active and recent agent chat sessions
struct AgentChatListView: View {
    @ObservedObject var agentService: AgentService
    @State private var selectedSession: (ChatSession, AgentEndpoint)?
    @State private var showingChat = false

    var body: some View {
        ZStack {
            if agentService.getActiveSessions().isEmpty {
                emptyStateView
            } else {
                sessionListView
            }
        }
    }

    // MARK: - Session List View

    private var sessionListView: some View {
        List {
            ForEach(agentService.getActiveSessions(), id: \.id) { session in
                if let agentId = agentService.getAgentId(for: session.id),
                   let agent = findAgent(for: agentId) {
                    SessionRow(session: session, agent: agent)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSession = (session, agent)
                            showingChat = true
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await closeSession(session)
                                }
                            } label: {
                                Label("Close", systemImage: "xmark")
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showingChat) {
            if let (session, agent) = selectedSession {
                AgentChatView(
                    agentService: agentService,
                    agent: agent,
                    session: session
                )
            }
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "message.badge")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Active Chats")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Connect to an agent and start a chat session to see it here")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Helper Methods

    private func findAgent(for agentId: String) -> AgentEndpoint? {
        agentService.discoveredAgents.first { $0.id == agentId }
    }

    private func closeSession(_ session: ChatSession) async {
        await agentService.closeChatSession(sessionId: session.id)
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: ChatSession
    let agent: AgentEndpoint

    var body: some View {
        HStack(spacing: 12) {
            // Agent avatar
            Circle()
                .fill(LinearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "cpu")
                        .font(.title3)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Agent ID
                Text(agent.id)
                    .font(.headline)

                // Session info
                HStack {
                    Text("Session \(session.id.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(agent.metadata.model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Capabilities
                HStack(spacing: 4) {
                    if session.capabilities?.supportsStreaming == true {
                        Label("Streaming", systemImage: "waveform")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    if let messageTypes = session.capabilities?.supportedMessageTypes, !messageTypes.isEmpty {
                        Label("\(messageTypes.count) types", systemImage: "text.bubble")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Time indicator
            VStack(alignment: .trailing, spacing: 4) {
                Text(session.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    let agentService = AgentService()
    return NavigationView {
        AgentChatListView(agentService: agentService)
            .navigationTitle("Agent Chats")
    }
}
