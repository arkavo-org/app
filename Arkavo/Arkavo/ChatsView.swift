import ArkavoKit
import SwiftData
import SwiftUI

/// Unified chats view showing all conversations (1:1, groups, agents) sorted by recency
struct ChatsView: View {
    @EnvironmentObject var sharedState: SharedState
    @EnvironmentObject var agentService: AgentService
    @StateObject private var viewModel: ChatsViewModel = ViewModelFactory.shared.makeChatsViewModel()
    @State private var searchText = ""
    @State private var showSearchBar = false
    @State private var selectedConversation: Conversation?
    @State private var showContactDetail: Profile?
    @State private var showDeleteConfirmation = false
    @State private var conversationToDelete: Conversation?

    var filteredConversations: [Conversation] {
        viewModel.filteredConversations(searchText: searchText)
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header - search toggle (space for + button on left)
                if !viewModel.isLoading && !viewModel.conversations.isEmpty {
                    HStack(spacing: 12) {
                        Spacer()

                        // Search toggle
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showSearchBar.toggle()
                                if !showSearchBar {
                                    searchText = ""
                                }
                            }
                        } label: {
                            Image(systemName: showSearchBar ? "xmark" : "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(showSearchBar ? .primary : .secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                    .padding(.leading, 60) // Space for + button
                    .padding(.trailing, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                }

                // Conversation list
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                } else if filteredConversations.isEmpty && searchText.isEmpty {
                    WaveEmptyStateView()
                } else if filteredConversations.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)

                        Text("No results")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Search bar
                            if showSearchBar {
                                searchBar
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Conversation rows
                            ForEach(filteredConversations) { conversation in
                                ConversationRow(
                                    conversation: conversation,
                                    agentService: agentService,
                                    onTap: {
                                        openConversation(conversation)
                                    },
                                    onAvatarTap: {
                                        if let profile = conversation.profile {
                                            showContactDetail = profile
                                        }
                                    }
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        conversationToDelete = conversation
                                        showDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                    .refreshable {
                        await viewModel.loadConversations()
                    }
                }
            }
        }
        .sheet(isPresented: $sharedState.showCreateView) {
            ChatsCreateView(viewModel: viewModel)
        }
        .sheet(item: $showContactDetail) { profile in
            UnifiedContactDetailView(contact: profile, agentService: agentService) { _ in
                // Handle delete from detail view if needed
            }
        }
        .alert("Delete Conversation?", isPresented: $showDeleteConfirmation, presenting: conversationToDelete) { conversation in
            Button("Cancel", role: .cancel) {
                conversationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteConversation(conversation)
                    conversationToDelete = nil
                }
            }
        } message: { conversation in
            Text("This will remove the conversation with \(conversation.title).")
        }
        // Chat overlay for when conversation is selected
        .overlay {
            if sharedState.showChatOverlay {
                if let streamPublicID = sharedState.selectedStreamPublicID {
                    ChatOverlay(streamPublicID: streamPublicID)
                } else if let contact = selectedConversation?.profile, contact.isAgent {
                    UnifiedChatView(contact: contact, agentService: agentService)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .task {
            viewModel.configure(agentService: agentService)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            TextField("Search", text: $searchText)
                .font(.body)

            if !searchText.isEmpty {
                Button {
                    withAnimation { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func openConversation(_ conversation: Conversation) {
        selectedConversation = conversation

        switch conversation.type {
        case .group:
            // Open group chat via ChatOverlay
            if let stream = conversation.stream {
                sharedState.selectedStreamPublicID = stream.publicID
                sharedState.showChatOverlay = true
            }
        case .direct, .agent:
            // Open 1:1 or agent chat via ChatOverlay
            // TODO: Implement distinct P2P mechanism for human chats
            if conversation.profile != nil {
                sharedState.showChatOverlay = true
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation
    let agentService: AgentService
    let onTap: () -> Void
    let onAvatarTap: () -> Void

    private var isOnline: Bool {
        if let profile = conversation.profile, profile.isAgent {
            return agentService.isConnected(to: profile.agentID ?? "")
        }
        return conversation.profile?.keyStorePublic != nil
    }

    private var accentColor: Color {
        switch conversation.type {
        case .group: return .purple
        case .agent: return .teal
        case .direct: return .blue
        }
    }

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
            onTap()
        }) {
            HStack(spacing: 16) {
                // Avatar (tappable for contact details)
                Button(action: onAvatarTap) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.2), accentColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)

                        Image(systemName: conversation.icon)
                            .font(.title3)
                            .foregroundStyle(accentColor)

                        // Online indicator (for direct/agent chats)
                        if conversation.type != .group {
                            Circle()
                                .fill(isOnline ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemBackground), lineWidth: 2)
                                )
                                .offset(x: 18, y: 18)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(conversation.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let lastMessageTime = conversation.lastMessageTime {
                            Text(lastMessageTime, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let subtitle = conversation.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                // Unread indicator or chevron
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor, in: Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.primary.opacity(0.04), lineWidth: 1)
            )
        }
        .buttonStyle(ContactCardButtonStyle())
    }
}

// MARK: - Chats Create View

struct ChatsCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var sharedState: SharedState
    @EnvironmentObject var agentService: AgentService
    @ObservedObject var viewModel: ChatsViewModel
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @State private var showContactPicker = false
    @State private var showNewGroup = false
    @State private var showNearbyPeople = false
    @State private var showScanAgent = false
    @State private var showShareSheet = false
    @State private var shareableLink: String = ""
    @State private var selectedChatContact: Profile?

    var body: some View {
        NavigationStack {
            List {
                Section("Chat") {
                    Button {
                        showContactPicker = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New Chat")
                                Text("Start a conversation with a contact")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "message")
                                .foregroundStyle(.blue)
                        }
                    }

                    Button {
                        showNewGroup = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New Group")
                                Text("Create a group conversation")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "person.3")
                                .foregroundStyle(.purple)
                        }
                    }
                }

                Section("Add People") {
                    Button {
                        showNearbyPeople = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Find Nearby")
                                Text("Connect with someone next to you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .foregroundStyle(.cyan)
                        }
                    }

                    Button {
                        showInviteRemotely()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Invite via Link")
                                Text("Share your profile link")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section("Agents") {
                    Button {
                        showScanAgent = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan Agent QR")
                                Text("Authorize an AI agent")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("New Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showNewGroup) {
                GroupCreateView(viewModel: ViewModelFactory.shared.makeViewModel())
                    .environmentObject(sharedState)
            }
            .sheet(isPresented: $showNearbyPeople) {
                NearbyConnectionView(peerManager: peerManager) {
                    showNearbyPeople = false
                    // Refresh conversations after adding contact
                    Task {
                        await viewModel.loadConversations()
                    }
                }
            }
            .sheet(isPresented: $showScanAgent) {
                AgentQRScannerView { request in
                    showScanAgent = false
                    // Refresh conversations after adding agent
                    Task {
                        await viewModel.loadConversations()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = URL(string: shareableLink) {
                    ContactShareSheet(activityItems: [url], isPresented: $showShareSheet)
                }
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPickerView(agentService: agentService) { contact in
                    selectedChatContact = contact
                    showContactPicker = false
                    dismiss()
                }
            }
            .sheet(item: $selectedChatContact) { contact in
                UnifiedChatView(contact: contact, agentService: agentService)
            }
        }
    }

    private func showInviteRemotely() {
        if let profile = ViewModelFactory.shared.getCurrentProfile() {
            shareableLink = "https://app.arkavo.com/connect/\(profile.publicID.base58EncodedString)"
            showShareSheet = true
        }
    }
}

// MARK: - Contact Picker View

struct ContactPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let agentService: AgentService
    let onSelect: (Profile) -> Void
    @StateObject private var contactService = UnifiedContactService()
    @State private var searchText = ""

    var filteredContacts: [Profile] {
        contactService.filteredContacts(searchText: searchText)
    }

    var body: some View {
        NavigationStack {
            List {
                if contactService.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if filteredContacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Add contacts to start chatting")
                    )
                } else {
                    ForEach(filteredContacts) { contact in
                        Button {
                            onSelect(contact)
                        } label: {
                            HStack(spacing: 12) {
                                // Avatar
                                ZStack {
                                    Circle()
                                        .fill(contact.isAgent ? Color.teal.opacity(0.2) : Color.blue.opacity(0.2))
                                        .frame(width: 44, height: 44)

                                    if contact.isAgent {
                                        Image(systemName: contact.contactTypeEnum == .deviceAgent ? "iphone" : "globe")
                                            .foregroundStyle(contact.isAgent ? .teal : .blue)
                                    } else {
                                        Text(contact.name.prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name)
                                        .foregroundStyle(.primary)

                                    if contact.isAgent {
                                        Text(contact.contactTypeEnum.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else if let handle = contact.handle {
                                        Text("@\(handle)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                contactService.configure(agentService: agentService)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ChatsView()
        .environmentObject(SharedState())
        .environmentObject(AgentService())
}
