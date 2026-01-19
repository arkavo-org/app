import SwiftUI

/// Unified detail view for both human contacts and agent contacts
struct UnifiedContactDetailView: View {
    let contact: Profile
    let agentService: AgentService
    let onDelete: (Profile) -> Void

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @State private var showDeleteConfirmation = false
    @State private var showChat = false
    @State private var isConnecting = false
    @State private var connectionError: String?

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

    var isConnected: Bool {
        if contact.isAgent {
            return agentService.isConnected(to: contact.agentID ?? "")
        } else {
            return contact.keyStorePublic != nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    contactHeader

                    // Status section
                    statusSection

                    // Agent-specific: Entitlements
                    if contact.isAgent && !contact.entitlements.isEmpty {
                        entitlementsSection
                    }

                    // Available channels
                    if contact.isAgent && !contact.channels.isEmpty {
                        channelsSection
                    }

                    // Actions
                    actionsSection

                    // About section
                    if let blurb = contact.blurb, !blurb.isEmpty {
                        aboutSection(blurb: blurb)
                    } else if let purpose = contact.agentPurpose, !purpose.isEmpty {
                        aboutSection(blurb: purpose)
                    }

                    // Agent model info
                    if let model = contact.agentModel {
                        modelSection(model: model)
                    }

                    // Delete button (not for device agent - this device's AI)
                    if contact.contactTypeEnum != .deviceAgent {
                        deleteSection
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Contact Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Contact?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    dismiss()
                    onDelete(contact)
                }
            } message: {
                if contact.isAgent {
                    Text("Are you sure you want to remove \(contact.name)? You can re-discover it later.")
                } else {
                    Text("Are you sure you want to delete \(contact.name)? You'll also be removed from any chats you only share with this person.")
                }
            }
            .sheet(isPresented: $showChat) {
                UnifiedChatView(contact: contact, agentService: agentService)
            }
        }
    }

    // MARK: - Header

    private var contactHeader: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(avatarGradient.opacity(0.3))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Circle()
                            .stroke(avatarGradient, lineWidth: 3)
                    )
                    .shadow(color: avatarGradient.stops.first?.color.opacity(0.3) ?? .clear, radius: 10, x: 0, y: 5)

                if contact.isAgent {
                    Image(systemName: contact.contactTypeEnum.icon)
                        .font(.system(size: 52))
                        .fontWeight(.bold)
                        .foregroundStyle(avatarGradient)
                } else {
                    Text(contact.name.prefix(1).uppercased())
                        .font(.system(size: 52))
                        .fontWeight(.bold)
                        .foregroundStyle(avatarGradient)
                }

                // Pinned badge for device agent
                if contact.contactTypeEnum == .deviceAgent {
                    Image(systemName: "pin.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .offset(x: 40, y: -40)
                }
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(contact.name)
                        .font(.title)
                        .fontWeight(.bold)

                    if contact.isAgent {
                        Text(contact.contactTypeEnum.displayName)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(6)
                    }
                }

                if let handle = contact.handle {
                    Text("@\(handle)")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }

                if let did = contact.did {
                    Text(shortDID(did))
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Connection status
            Label {
                Text(isConnected ? "Online" : "Offline")
                    .foregroundColor(isConnected ? .green : .secondary)
            } icon: {
                Image(systemName: isConnected ? "circle.fill" : "circle")
                    .foregroundColor(isConnected ? .green : .secondary)
                    .font(.caption)
            }

            // Human-specific status
            if !contact.isAgent {
                if contact.hasHighEncryption {
                    Label {
                        Text("End-to-End Encrypted")
                            .foregroundColor(.green)
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                    }
                }

                if contact.hasHighIdentityAssurance {
                    Label {
                        Text("Identity Verified")
                            .foregroundColor(.green)
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Entitlements Section

    private var entitlementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)

            ForEach(contact.entitlements.displayList, id: \.0) { icon, label in
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text(label)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Channels Section

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Communication Channels")
                .font(.headline)

            ForEach(contact.channels) { channel in
                HStack {
                    Image(systemName: channelIcon(for: channel.type))
                        .foregroundColor(channel.isAvailable ? .green : .secondary)
                        .frame(width: 24)
                    VStack(alignment: .leading) {
                        Text(channelName(for: channel.type))
                        if let lastSeen = channel.lastSeen {
                            Text("Last seen: \(lastSeen.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Circle()
                        .fill(channel.isAvailable ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Primary action button
            Button {
                if contact.isAgent {
                    startAgentChat()
                } else if isConnected {
                    startHumanChat()
                } else {
                    initiateConnection()
                }
            } label: {
                HStack {
                    if isConnecting {
                        ProgressView()
                            .tint(.white)
                    }
                    Label(
                        contact.isAgent ? "Start Chat" : (isConnected ? "Send Message" : "Connect"),
                        systemImage: contact.isAgent ? "bubble.left.and.bubble.right.fill" : (isConnected ? "message.fill" : "link")
                    )
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(avatarGradient)
                .foregroundColor(.white)
                .cornerRadius(14)
                .shadow(color: avatarGradient.stops.first?.color.opacity(0.3) ?? .clear, radius: 8, x: 0, y: 4)
            }
            .disabled(isConnecting)

            // Error message
            if let error = connectionError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // More options
            Button {
                // Show more options
            } label: {
                Label("More Options", systemImage: "ellipsis.circle")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - About Section

    private func aboutSection(blurb: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)

            Text(blurb)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Model Section

    private func modelSection(model: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model")
                .font(.headline)

            Text(model)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button {
            showDeleteConfirmation = true
        } label: {
            Label(contact.isAgent ? "Remove Agent" : "Delete Contact", systemImage: "trash")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.top, 20)
    }

    // MARK: - Actions

    private func startAgentChat() {
        showChat = true
    }

    private func startHumanChat() {
        sharedState.selectedCreatorPublicID = contact.publicID
        sharedState.showChatOverlay = true
        dismiss()
    }

    private func initiateConnection() {
        // Initiate P2P connection flow
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        // TODO: Trigger P2P discovery/connection flow
    }

    // MARK: - Helpers

    private func shortDID(_ did: String) -> String {
        guard did.count > 24 else { return did }
        let prefix = did.prefix(16)
        let suffix = did.suffix(8)
        return "\(prefix)...\(suffix)"
    }

    private func channelIcon(for type: CommunicationChannel.ChannelType) -> String {
        switch type {
        case .localNetwork: return "wifi"
        case .arkavoNetwork: return "network"
        case .p2p: return "dot.radiowaves.left.and.right"
        }
    }

    private func channelName(for type: CommunicationChannel.ChannelType) -> String {
        switch type {
        case .localNetwork: return "Local Network"
        case .arkavoNetwork: return "Arkavo Network"
        case .p2p: return "Peer-to-Peer"
        }
    }
}

// MARK: - LinearGradient Extension

extension LinearGradient {
    var stops: [Gradient.Stop] {
        // This is a workaround since we can't directly access gradient stops
        // We'll use the avatar gradient's first color as approximation
        []
    }
}

#Preview {
    UnifiedContactDetailView(
        contact: Profile(name: "Test Agent"),
        agentService: AgentService(),
        onDelete: { _ in }
    )
    .environmentObject(SharedState())
}
