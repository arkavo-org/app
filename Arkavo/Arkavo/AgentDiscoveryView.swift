import ArkavoAgent
import SwiftUI

/// View for discovering and browsing local A2A agents on the network
struct AgentDiscoveryView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var agentService: AgentService
    @State private var selectedAgent: AgentEndpoint?
    @State private var showingAgentDetail = false
    @State private var errorMessage: String?
    @State private var showError = false

    init(agentService: AgentService) {
        _agentService = StateObject(wrappedValue: agentService)
    }

    var body: some View {
        NavigationView {
            ZStack {
                if agentService.discoveredAgents.isEmpty {
                    emptyStateView
                } else {
                    agentListView
                }
            }
            .navigationTitle("Local Agents")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
            .onAppear {
                agentService.startDiscovery()
            }
            .onDisappear {
                agentService.stopDiscovery()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showingAgentDetail) {
                if let selectedAgent {
                    AgentDetailView(agentService: agentService, agent: selectedAgent)
                }
            }
        }
    }

    // MARK: - Agent List View

    private var agentListView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                ForEach(agentService.discoveredAgents) { agent in
                    AgentCard(
                        agent: agent,
                        isConnected: agentService.isConnected(to: agent.id),
                    )
                    .onTapGesture {
                        selectedAgent = agent
                        showingAgentDetail = true
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await refreshAgents()
        }
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Agents Found")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Make sure an agent is running on your local network")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if agentService.isDiscovering {
                ProgressView()
                    .padding(.top, 8)
            } else {
                Button(action: {
                    agentService.startDiscovery()
                }) {
                    Label("Start Searching", systemImage: "magnifyingglass")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button(action: {
            Task {
                await refreshAgents()
            }
        }) {
            Image(systemName: "arrow.clockwise")
                .imageScale(.large)
        }
    }

    // MARK: - Actions

    private func refreshAgents() async {
        agentService.stopDiscovery()
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        agentService.startDiscovery()
    }
}

// MARK: - Agent Card View

struct AgentCard: View {
    let agent: AgentEndpoint
    let isConnected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with icon and connection status
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(.blue)

                Spacer()

                connectionBadge
            }

            // Agent ID
            Text(agent.id)
                .font(.headline)
                .lineLimit(1)

            // Model info
            HStack(spacing: 4) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(agent.metadata.model)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Purpose
            Text(agent.metadata.purpose)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // Connection info
            HStack {
                Image(systemName: "network")
                    .font(.caption)
                Text("\(agent.host ?? "unknown"):\(agent.port ?? 0)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isConnected ? Color.green : Color.clear, lineWidth: 2)
        )
    }

    private var connectionBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Available")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let agentService = AgentService()
    return AgentDiscoveryView(agentService: agentService)
        .environmentObject(SharedState())
}
