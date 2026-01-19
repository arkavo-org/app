import ArkavoKit
import Combine
import Foundation
import OSLog
import SwiftData

/// Service that provides a unified view of all contacts (humans and agents)
/// Coordinates between AgentService for agent discovery and PersistenceController for persistence
@MainActor
final class UnifiedContactService: ObservableObject {
    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "UnifiedContactService")

    // MARK: - Published Properties

    /// All contacts (humans + agents), sorted with device agents first, then online, then alphabetical
    @Published var allContacts: [Profile] = []

    /// Only online contacts
    @Published var onlineContacts: [Profile] = []

    /// Human contacts only
    @Published var humanContacts: [Profile] = []

    /// Agent contacts only
    @Published var agentContacts: [Profile] = []

    /// Current filter
    @Published var currentFilter: ContactFilter = .all

    /// Loading state
    @Published var isLoading: Bool = false

    // MARK: - Private Properties

    private var agentService: AgentService?
    private var cancellables = Set<AnyCancellable>()
    private var persistedAgentIDs: Set<String> = []

    // MARK: - Device Agent Constants (fallbacks)

    static let deviceAgentFallbackID = "device-agent-fallback"
    static let deviceAgentFallbackName = "This Device"

    // MARK: - Initialization

    init() {
        logger.log("[UnifiedContactService] Initialized")
    }

    /// Configure the service with AgentService reference
    func configure(agentService: AgentService) {
        self.agentService = agentService
        setupBindings()
        Task {
            await loadContacts()
            await ensureDeviceAgentExists()
        }
    }

    // MARK: - Setup

    private func setupBindings() {
        guard let agentService else { return }

        // Subscribe to discovered agents and update contacts
        agentService.$discoveredAgents
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] agents in
                Task { @MainActor [weak self] in
                    await self?.updateAgentContacts(from: agents)
                }
            }
            .store(in: &cancellables)

        // Subscribe to connected agents for online status
        agentService.$connectedAgents
            .sink { [weak self] connectedAgents in
                Task { @MainActor [weak self] in
                    self?.updateOnlineStatus(connectedAgents: connectedAgents)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Contact Loading

    /// Load all contacts from persistence
    func loadContacts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let peerProfiles = try await PersistenceController.shared.fetchAllPeerProfiles()

            // Filter out "Me" profile and separate humans from agents
            let filtered = peerProfiles.filter { $0.name != "Me" }

            // Track which agent IDs are already persisted
            persistedAgentIDs = Set(filtered.compactMap { $0.isAgent ? $0.agentID : nil })

            // Sort contacts: device agent first, then online, then alphabetical
            let sorted = sortContacts(filtered)

            allContacts = sorted
            humanContacts = sorted.filter { !$0.isAgent }
            agentContacts = sorted.filter { $0.isAgent }
            onlineContacts = sorted.filter { $0.isOnline }

            logger.log("[UnifiedContactService] Loaded \(sorted.count) contacts (\(self.humanContacts.count) humans, \(self.agentContacts.count) agents)")
        } catch {
            logger.error("[UnifiedContactService] Failed to load contacts: \(String(describing: error))")
            allContacts = []
            humanContacts = []
            agentContacts = []
            onlineContacts = []
        }
    }

    // MARK: - Device Agent Management

    /// Ensure the device agent (this device's on-device AI) exists as a pinned contact
    func ensureDeviceAgentExists() async {
        guard let agentService else { return }

        // Get the device agent's unique ID and name for this device
        let deviceAI = agentService.deviceAgent
        let deviceAgentID = deviceAI?.id ?? Self.deviceAgentFallbackID
        let deviceAgentName = deviceAI?.name ?? Self.deviceAgentFallbackName

        // Check if device agent already exists in contacts
        if allContacts.contains(where: { $0.agentID == deviceAgentID || $0.contactTypeEnum == .deviceAgent }) {
            logger.log("[UnifiedContactService] Device agent already exists")
            return
        }

        // Get device agent endpoint from AgentService (if discovered via mDNS)
        let deviceAgentEndpoint = agentService.discoveredAgents.first(where: { $0.id.lowercased().contains("local") })

        await createDeviceAgentContact(
            agentID: deviceAgentID,
            agentName: deviceAgentName,
            endpoint: deviceAgentEndpoint
        )
    }

    private func createDeviceAgentContact(agentID: String, agentName: String, endpoint: AgentEndpoint?) async {
        let profile = Profile.createAgentProfile(
            agentID: agentID,
            name: agentName,
            did: nil,
            purpose: endpoint?.metadata.purpose ?? "On-device AI for intelligence and sensor access",
            model: endpoint?.metadata.model ?? "on-device",
            endpoint: endpoint?.url ?? "local://in-process",
            contactType: .deviceAgent,
            channels: [.localNetwork(endpoint: "local://in-process", isAvailable: true)],
            entitlements: AgentEntitlements(read: true, write: true, execute: true)
        )

        do {
            try await PersistenceController.shared.savePeerProfile(profile)
            persistedAgentIDs.insert(agentID)
            await loadContacts()
            logger.log("[UnifiedContactService] Created device agent contact: \(agentName)")
        } catch {
            logger.error("[UnifiedContactService] Failed to create device agent: \(String(describing: error))")
        }
    }

    // MARK: - Agent Contact Updates

    /// Update agent contacts from discovered agents
    private func updateAgentContacts(from agents: [AgentEndpoint]) async {
        var needsReload = false

        for agent in agents {
            // Skip if already persisted
            if persistedAgentIDs.contains(agent.id) {
                // Update online status instead
                updateAgentOnlineStatus(agentID: agent.id, isOnline: true)
                continue
            }

            // Skip device agent as it's handled separately
            if agent.id.lowercased().contains("local") {
                continue
            }

            // Determine contact type based on agent metadata
            let contactType: ContactType = {
                let purpose = agent.metadata.purpose.lowercased()
                if purpose.contains("orchestrat") {
                    return .remoteAgent
                }
                return .remoteAgent
            }()

            // Create profile for discovered agent
            let profile = Profile.createAgentProfile(
                agentID: agent.id,
                name: agent.metadata.name,
                did: nil,
                purpose: agent.metadata.purpose,
                model: agent.metadata.model,
                endpoint: agent.url,
                contactType: contactType,
                channels: [.localNetwork(endpoint: agent.url, isAvailable: true)]
            )

            do {
                try await PersistenceController.shared.savePeerProfile(profile)
                persistedAgentIDs.insert(agent.id)
                needsReload = true
                logger.log("[UnifiedContactService] Added discovered agent: \(agent.metadata.name)")
            } catch {
                logger.error("[UnifiedContactService] Failed to save agent \(agent.id): \(String(describing: error))")
            }
        }

        if needsReload {
            await loadContacts()
        }
    }

    /// Update online status from connected agents
    private func updateOnlineStatus(connectedAgents: [String: Bool]) {
        for contact in allContacts where contact.isAgent {
            guard let agentID = contact.agentID else { continue }
            let isConnected = connectedAgents[agentID] ?? false
            updateAgentOnlineStatus(agentID: agentID, isOnline: isConnected)
        }

        // Refresh online contacts list
        onlineContacts = allContacts.filter { $0.isOnline }
    }

    /// Update a specific agent's online status
    private func updateAgentOnlineStatus(agentID: String, isOnline: Bool) {
        guard let contact = allContacts.first(where: { $0.agentID == agentID }) else { return }

        var channels = contact.channels
        if let localIndex = channels.firstIndex(where: { $0.type == .localNetwork }) {
            channels[localIndex].isAvailable = isOnline
            channels[localIndex].lastSeen = isOnline ? Date() : channels[localIndex].lastSeen
            contact.channels = channels
        }
    }

    // MARK: - Contact Management

    /// Add a delegated agent contact (from QR code authorization)
    func addDelegatedAgent(
        agentID: String,
        name: String,
        did: String,
        entitlements: AgentEntitlements
    ) async throws {
        // Check if already exists
        if persistedAgentIDs.contains(agentID) || allContacts.contains(where: { $0.did == did }) {
            logger.log("[UnifiedContactService] Delegated agent already exists: \(did)")
            return
        }

        let profile = Profile.createAgentProfile(
            agentID: agentID,
            name: name,
            did: did,
            purpose: "Delegated agent with authorized access",
            model: nil,
            endpoint: nil,
            contactType: .delegatedAgent,
            channels: [.arkavoNetwork(isAvailable: true)],
            entitlements: entitlements
        )

        try await PersistenceController.shared.savePeerProfile(profile)
        persistedAgentIDs.insert(agentID)
        await loadContacts()
        logger.log("[UnifiedContactService] Added delegated agent: \(name)")
    }

    /// Delete a contact
    func deleteContact(_ contact: Profile) async throws {
        if let agentID = contact.agentID {
            persistedAgentIDs.remove(agentID)
        }
        try await PersistenceController.shared.deletePeerProfile(contact)
        await loadContacts()
        logger.log("[UnifiedContactService] Deleted contact: \(contact.name)")
    }

    // MARK: - Filtering

    /// Get filtered contacts based on current filter
    func filteredContacts(searchText: String = "") -> [Profile] {
        var result: [Profile]

        switch currentFilter {
        case .all:
            result = allContacts
        case .people:
            result = humanContacts
        case .agents:
            result = agentContacts
        case .online:
            result = onlineContacts
        }

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { contact in
                contact.name.localizedCaseInsensitiveContains(searchText) ||
                    (contact.handle?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (contact.agentPurpose?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return result
    }

    // MARK: - Sorting

    /// Sort contacts with device agents pinned first, then online, then alphabetical
    private func sortContacts(_ contacts: [Profile]) -> [Profile] {
        contacts.sorted { a, b in
            // Device agents always first (this device's agent)
            if a.contactTypeEnum == .deviceAgent && b.contactTypeEnum != .deviceAgent {
                return true
            }
            if b.contactTypeEnum == .deviceAgent && a.contactTypeEnum != .deviceAgent {
                return false
            }

            // Online contacts before offline
            if a.isOnline && !b.isOnline {
                return true
            }
            if b.isOnline && !a.isOnline {
                return false
            }

            // Alphabetical by name
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Agent Lookup

    /// Find a contact by agent ID
    func findContact(byAgentID agentID: String) -> Profile? {
        allContacts.first { $0.agentID == agentID }
    }

    /// Find a contact by DID
    func findContact(byDID did: String) -> Profile? {
        allContacts.first { $0.did == did }
    }

    /// Find a contact by public ID
    func findContact(byPublicID publicID: Data) -> Profile? {
        allContacts.first { $0.publicID == publicID }
    }
}
