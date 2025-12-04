import ArkavoKit
import SwiftUI

// MARK: - Network Status

enum NetworkStatus {
    case connected
    case connecting
    case disconnected
    case error(String)

    var color: Color {
        switch self {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .gray
        case .error: .red
        }
    }

    var icon: String {
        switch self {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .disconnected: "circle"
        case .error: "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Network Section View

struct NetworkSectionView<Content: View>: View {
    let title: String
    let icon: String
    let status: NetworkStatus
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Text(title)
                        .font(.headline)

                    Spacer()

                    Image(systemName: status.icon)
                        .foregroundStyle(status.color)

                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal)

                content()
                    .padding()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Network Connections View

struct NetworkConnectionsView: View {
    @EnvironmentObject private var sharedState: SharedState
    @EnvironmentObject private var agentService: AgentService
    @EnvironmentObject private var remoteStreamer: RemoteCameraStreamer

    @StateObject private var cameraDiscovery = CameraDiscoveryService()

    @State private var isLocalNetworkExpanded = true
    @State private var isArkavoSocialExpanded = true
    @State private var isTrustNetworkExpanded = true
    @State private var isEdgeAgentExpanded = true

    private var hasProfile: Bool {
        ViewModelFactory.shared.getCurrentProfile() != nil
    }

    private var arkavoSocialStatus: NetworkStatus {
        sharedState.isOfflineMode ? .disconnected : .connected
    }

    private var edgeAgents: [AgentEndpoint] {
        agentService.discoveredAgents.filter { agent in
            let id = agent.id.lowercased()
            let purpose = agent.metadata.purpose.lowercased()
            return id.contains("edge") || purpose.contains("edge") || purpose.contains("orchestrat")
        }
    }

    private var edgeAgentStatus: NetworkStatus {
        if edgeAgents.isEmpty {
            return agentService.isDiscovering ? .connecting : .disconnected
        }
        let anyConnected = edgeAgents.contains { agentService.isConnected(to: $0.id) }
        return anyConnected ? .connected : .disconnected
    }

    private var localAIAgent: AgentEndpoint? {
        agentService.discoveredAgents.first { $0.id.lowercased().contains("local") }
    }

    private var localNetworkStatus: NetworkStatus {
        if remoteStreamer.connectionState == .streaming {
            return .connected
        }
        if !cameraDiscovery.discoveredServers.isEmpty || localAIAgent != nil {
            return .connected
        }
        return .connecting
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection

            ScrollView {
                LazyVStack(spacing: 16) {
                    localNetworkSection
                    arkavoSocialSection
                    trustNetworkSection
                    edgeAgentSection
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .topTrailing) {
            reconnectButton
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .padding(.top, 20)

            Text("Network Connections")
                .font(.title2)
                .fontWeight(.bold)

            Text("Connect to local devices and networks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Local Network Section

    private var isRemoteStreaming: Bool {
        remoteStreamer.connectionState == .streaming
    }

    private var localNetworkSection: some View {
        NetworkSectionView(
            title: "Local Network",
            icon: "network",
            status: localNetworkStatus,
            isExpanded: $isLocalNetworkExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Remote Camera Streaming Status
                if isRemoteStreaming {
                    HStack(spacing: 12) {
                        Image(systemName: "video.fill")
                            .foregroundStyle(.green)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remote Camera Active")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(remoteStreamer.connectionState.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            remoteStreamer.stopStreaming()
                        } label: {
                            Text("Stop")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .padding(.vertical, 4)

                    Divider()
                }

                if cameraDiscovery.discoveredServers.isEmpty && localAIAgent == nil && !isRemoteStreaming {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching for devices...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    // Discovered servers (ArkavoCreator, Remote Cameras)
                    ForEach(cameraDiscovery.discoveredServers) { server in
                        LocalDeviceRow(
                            name: server.name,
                            detail: "\(server.host):\(server.port)",
                            icon: server.name.lowercased().contains("creator") ? "desktopcomputer" : "camera.fill",
                            isConnected: false
                        )
                    }

                    // Local AI Agent
                    if let agent = localAIAgent {
                        LocalDeviceRow(
                            name: agent.metadata.name,
                            detail: "On-device AI",
                            icon: "cpu",
                            isConnected: agentService.isConnected(to: agent.id)
                        )
                    }
                }

                // Auto-connect toggle
                Toggle(isOn: Binding(
                    get: { RemoteCameraStreamer.isAutoConnectEnabled },
                    set: { RemoteCameraStreamer.isAutoConnectEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-connect to Creator")
                            .font(.subheadline)
                        Text("Automatically connect when app launches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Arkavo Social Network Section

    private var arkavoSocialSection: some View {
        NetworkSectionView(
            title: "Arkavo Social Network",
            icon: "globe",
            status: arkavoSocialStatus,
            isExpanded: $isArkavoSocialExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if sharedState.isOfflineMode {
                    Text("Register or sign in to access the Arkavo social network")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        sharedState.shouldShowRegistration = true
                    } label: {
                        HStack {
                            Image(systemName: "person.badge.plus")
                            Text("Register / Sign In")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let profile = ViewModelFactory.shared.getCurrentProfile() {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Connected")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(profile.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Trust Network Section

    private var trustNetworkSection: some View {
        NetworkSectionView(
            title: "Trust Network",
            icon: "person.3.fill",
            status: .disconnected,
            isExpanded: $isTrustNetworkExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Peer-to-peer mesh networking for secure local communication")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text("Nearby Devices")
                        .font(.subheadline)
                    Spacer()
                    Text("0 connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("Use Communities tab to discover and connect with nearby peers")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Edge Agent Section

    private var edgeAgentSection: some View {
        NetworkSectionView(
            title: "Edge Agent Network",
            icon: "cpu",
            status: edgeAgentStatus,
            isExpanded: $isEdgeAgentExpanded
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if edgeAgents.isEmpty {
                    if agentService.isDiscovering {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Discovering edge agents...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No edge agents discovered on local network")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            agentService.startDiscovery()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Start Discovery")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ForEach(edgeAgents) { agent in
                        EdgeAgentRow(
                            agent: agent,
                            isConnected: agentService.isConnected(to: agent.id),
                            onConnect: {
                                Task {
                                    try? await agentService.connect(to: agent)
                                }
                            },
                            onDisconnect: {
                                Task {
                                    await agentService.disconnect(from: agent.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Reconnect Button

    private var reconnectButton: some View {
        Button {
            Data.didPostRetryConnection = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("Reconnect")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85))
            .clipShape(Capsule())
        }
        .padding()
    }
}

// MARK: - Local Device Row

struct LocalDeviceRow: View {
    let name: String
    let detail: String
    let icon: String
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edge Agent Row

struct EdgeAgentRow: View {
    let agent: AgentEndpoint
    let isConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.metadata.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(agent.metadata.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if isConnected {
                    onDisconnect()
                } else {
                    onConnect()
                }
            } label: {
                Text(isConnected ? "Disconnect" : "Connect")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(isConnected ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NetworkConnectionsView()
        .environmentObject(SharedState())
        .environmentObject(AgentService())
}
