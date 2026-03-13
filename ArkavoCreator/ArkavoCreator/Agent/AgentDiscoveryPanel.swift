import ArkavoKit
import SwiftUI

/// Panel for discovering and connecting to A2A agents (macOS)
struct AgentDiscoveryPanel: View {
    @ObservedObject var agentService: CreatorAgentService
    @State private var selectedAgent: AgentEndpoint?
    @State private var showingChat = false
    @State private var chatSession: ChatSession?
    @State private var manualURL: String = ""
    @State private var isConnectingManually = false
    @State private var errorMessage: String?
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Discovery header
                discoveryHeader

                // Agent list
                if agentService.discoveredAgents.isEmpty {
                    emptyStateView
                } else {
                    agentListView
                }

                Divider()

                // Manual connection
                manualConnectionSection
            }
            .padding()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { /* Dismisses alert */ }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $showingChat) {
            if let chatSession, let selectedAgent {
                CreatorChatView(
                    agentService: agentService,
                    agent: selectedAgent,
                    session: chatSession
                )
                .frame(minWidth: 500, minHeight: 400)
            }
        }
        .onAppear {
            manualURL = agentService.manualConnectionURL
        }
    }

    // MARK: - Discovery Header

    private var discoveryHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discovered Agents")
                    .font(.headline)
                Text("\(agentService.discoveredAgents.count) agent(s) found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if agentService.isDiscovering {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: {
                agentService.stopDiscovery()
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    agentService.startDiscovery()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh agent discovery")
        }
    }

    // MARK: - Agent List

    private var agentListView: some View {
        VStack(spacing: 12) {
            ForEach(agentService.discoveredAgents) { agent in
                CreatorAgentCard(
                    agent: agent,
                    isConnected: agentService.isConnected(to: agent.id),
                    onConnect: {
                        Task {
                            do {
                                try await agentService.connect(to: agent)
                            } catch {
                                errorMessage = "Failed to connect: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    },
                    onDisconnect: {
                        Task {
                            await agentService.disconnect(from: agent.id)
                        }
                    },
                    onChat: {
                        Task {
                            do {
                                let session = try await agentService.openChatSession(with: agent.id)
                                selectedAgent = agent
                                chatSession = session
                                showingChat = true
                            } catch {
                                errorMessage = "Failed to open chat: \(error.localizedDescription)"
                                showError = true
                            }
                        }
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("No Remote Agents Found")
                .font(.subheadline)
                .fontWeight(.medium)

            Text("Start arkavo-edge on your local network, or connect manually below.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Manual Connection

    private var manualConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Connection")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("ws://localhost:8342", text: $manualURL)
                    .textFieldStyle(.roundedBorder)

                Button(action: {
                    isConnectingManually = true
                    Task {
                        do {
                            try await agentService.connectManually(url: manualURL)
                            agentService.manualConnectionURL = manualURL
                        } catch {
                            errorMessage = "Failed to connect: \(error.localizedDescription)"
                            showError = true
                        }
                        isConnectingManually = false
                    }
                }) {
                    if isConnectingManually {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .disabled(manualURL.isEmpty || isConnectingManually)
            }

            Text("Enter the WebSocket URL of a running arkavo-edge instance.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Creator Agent Card

struct CreatorAgentCard: View {
    let agent: AgentEndpoint
    let isConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onChat: () -> Void

    private var agentType: String {
        let purpose = agent.metadata.purpose.lowercased()
        if purpose.contains("orchestrat") {
            return "Orchestrator"
        } else if purpose.contains("on-device") || agent.url.hasPrefix("local://") {
            return "Device"
        } else {
            return "Remote"
        }
    }

    private var agentColor: Color {
        switch agentType {
        case "Orchestrator": .purple
        case "Device": .blue
        default: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: agentType == "Device" ? "desktopcomputer" : "cpu.fill")
                    .foregroundColor(agentColor)

                Text(agent.metadata.name)
                    .font(.headline)

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isConnected ? "Connected" : "Available")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Type badge
                Text(agentType)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(agentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Model info
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(agent.metadata.model)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Purpose
            Text(agent.metadata.purpose)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Capabilities
            if let caps = agent.metadata.properties["capabilities"] {
                let capList = caps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                HStack(spacing: 4) {
                    ForEach(capList.prefix(4), id: \.self) { cap in
                        Text(cap)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if capList.count > 4 {
                        Text("+\(capList.count - 4)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Connection info
            if agent.host != nil || agent.port != nil {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.caption)
                    Text("\(agent.host ?? "local"):\(agent.port ?? 0)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Action buttons
            HStack(spacing: 8) {
                if isConnected {
                    Button("Chat") {
                        onChat()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if agentType != "Device" {
                        Button("Disconnect") {
                            onDisconnect()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button("Connect") {
                        onConnect()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isConnected ? Color.green.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }
}
