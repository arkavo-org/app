import ArkavoKit
import Combine
import Foundation
import OSLog
import SwiftData

// MARK: - Conversation Model

/// Represents a unified conversation (group, 1:1, or agent chat)
struct Conversation: Identifiable {
    let id: String
    let type: ConversationType
    let title: String
    let subtitle: String?
    let lastMessageTime: Date?
    let unreadCount: Int

    // Associated data
    let stream: Stream?
    let profile: Profile?

    var icon: String {
        switch type {
        case .group:
            return "person.3.fill"
        case .direct:
            return profile?.name.prefix(1).uppercased() ?? "person.fill"
        case .agent:
            if profile?.contactTypeEnum == .deviceAgent {
                return "iphone"
            }
            return "globe"
        }
    }

    init(
        id: String,
        type: ConversationType,
        title: String,
        subtitle: String? = nil,
        lastMessageTime: Date? = nil,
        unreadCount: Int = 0,
        stream: Stream? = nil,
        profile: Profile? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
        self.stream = stream
        self.profile = profile
    }
}

enum ConversationType {
    case group
    case direct
    case agent
}

// MARK: - ChatsViewModel

@MainActor
final class ChatsViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "ChatsViewModel")

    // MARK: - Published Properties

    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false

    // MARK: - Dependencies

    private var agentService: AgentService?
    private var cancellables = Set<AnyCancellable>()
    private let account: Account

    // MARK: - Initialization

    init(account: Account) {
        self.account = account
    }

    func configure(agentService: AgentService) {
        self.agentService = agentService
        setupBindings()
        Task {
            await loadConversations()
        }
    }

    private func setupBindings() {
        guard let agentService else { return }

        // Update when agent connections change
        agentService.$connectedAgents
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadConversations()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Loading

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }

        var allConversations: [Conversation] = []

        // 1. Load group chat streams
        let groupStreams = account.streams.filter { $0.isGroupChatStream }
        for stream in groupStreams {
            let lastMessage = stream.thoughts.sorted { $0.metadata.createdAt > $1.metadata.createdAt }.first
            let conversation = Conversation(
                id: "stream-\(stream.publicID.base58EncodedString)",
                type: .group,
                title: stream.streamName.isEmpty ? "Group Chat" : stream.streamName,
                subtitle: stream.streamBlurb.isEmpty ? nil : stream.streamBlurb,
                lastMessageTime: lastMessage?.metadata.createdAt,
                unreadCount: 0, // TODO: Track unread
                stream: stream
            )
            allConversations.append(conversation)
        }

        // 2. Load contact conversations (agents and humans)
        do {
            let contacts = try await PersistenceController.shared.fetchAllPeerProfiles()
            let chatContacts = contacts.filter { $0.name != "Me" }

            for contact in chatContacts {
                let conversationType: ConversationType = contact.isAgent ? .agent : .direct
                let subtitle: String?
                if contact.isAgent {
                    subtitle = contact.agentPurpose ?? contact.contactTypeEnum.displayName
                } else {
                    subtitle = contact.handle.map { "@\($0)" }
                }

                let conversation = Conversation(
                    id: "contact-\(contact.publicID.base58EncodedString)",
                    type: conversationType,
                    title: contact.name,
                    subtitle: subtitle,
                    lastMessageTime: nil, // TODO: Track last message time per contact
                    unreadCount: 0,
                    profile: contact
                )
                allConversations.append(conversation)
            }
        } catch {
            logger.error("[ChatsViewModel] Failed to load contacts: \(String(describing: error))")
        }

        // 3. Sort by recency (conversations with messages first, then alphabetical)
        conversations = allConversations.sorted { a, b in
            // Prioritize device agent at top
            if a.profile?.contactTypeEnum == .deviceAgent { return true }
            if b.profile?.contactTypeEnum == .deviceAgent { return false }

            // Then by last message time
            if let aTime = a.lastMessageTime, let bTime = b.lastMessageTime {
                return aTime > bTime
            }
            if a.lastMessageTime != nil { return true }
            if b.lastMessageTime != nil { return false }

            // Then alphabetically
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        logger.log("[ChatsViewModel] Loaded \(self.conversations.count) conversations")
    }

    // MARK: - Filtering

    func filteredConversations(searchText: String) -> [Conversation] {
        guard !searchText.isEmpty else { return conversations }

        let lowercased = searchText.lowercased()
        return conversations.filter { conversation in
            conversation.title.lowercased().contains(lowercased) ||
            (conversation.subtitle?.lowercased().contains(lowercased) ?? false)
        }
    }

    // MARK: - Actions

    func deleteConversation(_ conversation: Conversation) async {
        switch conversation.type {
        case .group:
            // Delete stream
            if let stream = conversation.stream {
                do {
                    PersistenceController.shared.mainContext.delete(stream)
                    try await PersistenceController.shared.saveChanges()
                    conversations.removeAll { $0.id == conversation.id }
                    logger.log("[ChatsViewModel] Deleted group: \(conversation.title)")
                } catch {
                    logger.error("[ChatsViewModel] Failed to delete group: \(String(describing: error))")
                }
            }
        case .direct, .agent:
            // Delete contact profile
            if let profile = conversation.profile {
                do {
                    PersistenceController.shared.mainContext.delete(profile)
                    try await PersistenceController.shared.saveChanges()
                    conversations.removeAll { $0.id == conversation.id }
                    logger.log("[ChatsViewModel] Deleted contact: \(conversation.title)")
                } catch {
                    logger.error("[ChatsViewModel] Failed to delete contact: \(String(describing: error))")
                }
            }
        }
    }
}
