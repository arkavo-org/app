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
            .navigationTitle("Agents")
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
            // Header with agent type icon and connection status
            HStack {
                agentIcon
                    .font(.title2)
                    .foregroundColor(agentColor)

                Spacer()

                connectionBadge
            }

            // Agent name and type badge
            HStack {
                Text(agent.metadata.name)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                agentTypeBadge
            }

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

            // Capabilities
            if !capabilities.isEmpty {
                capabilitiesView
            }

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

    // MARK: - Agent Type Detection

    private var agentType: AgentType {
        let purpose = agent.metadata.purpose.lowercased()
        if purpose.contains("orchestrat") {
            return .orchestrator
        } else if purpose.contains("local") && purpose.contains("ai") {
            return .localAI
        } else {
            return .remote
        }
    }

    private var agentIcon: Image {
        switch agentType {
        case .orchestrator:
            return Image(systemName: "cpu.fill")
        case .localAI:
            return Image(systemName: "iphone")
        case .remote:
            return Image(systemName: "globe")
        }
    }

    private var agentColor: Color {
        switch agentType {
        case .orchestrator:
            return .purple
        case .localAI:
            return .blue
        case .remote:
            return .green
        }
    }

    private var agentTypeBadge: some View {
        Text(agentType.rawValue)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(agentColor)
            .cornerRadius(6)
    }

    // MARK: - Capabilities

    private var capabilities: [String] {
        if let caps = agent.metadata.properties["capabilities"] {
            return caps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    private var capabilitiesView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Capabilities")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(capabilities.prefix(4), id: \.self) { capability in
                    capabilityChip(capability)
                }
                if capabilities.count > 4 {
                    Text("+\(capabilities.count - 4)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func capabilityChip(_ capability: String) -> some View {
        Text(capability)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(4)
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

// MARK: - Agent Type Enum

enum AgentType: String {
    case orchestrator = "Orchestrator"
    case localAI = "Local AI"
    case remote = "Remote"
}

// MARK: - Flow Layout for Chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(origin: CGPoint(x: currentX, y: currentY), size: size))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Preview

#Preview {
    let agentService = AgentService()
    return AgentDiscoveryView(agentService: agentService)
        .environmentObject(SharedState())
}
