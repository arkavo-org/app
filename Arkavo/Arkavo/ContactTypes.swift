import Foundation

// MARK: - Contact Type

/// Types of contacts in the unified contacts system
enum ContactType: String, Codable, CaseIterable {
    case human = "human"
    case deviceAgent = "deviceAgent"     // On-device AI agent (iPhone, iPad, Mac)
    case remoteAgent = "remoteAgent"     // Network-discovered agent
    case delegatedAgent = "delegatedAgent" // Authorized via QR/delegation

    var displayName: String {
        switch self {
        case .human: return "Person"
        case .deviceAgent: return "Device Agent"
        case .remoteAgent: return "Remote Agent"
        case .delegatedAgent: return "Delegated Agent"
        }
    }

    var icon: String {
        switch self {
        case .human: return "person.fill"
        case .deviceAgent: return "iphone.gen3"
        case .remoteAgent: return "network"
        case .delegatedAgent: return "person.badge.key.fill"
        }
    }

    var isAgent: Bool {
        self != .human
    }
}

// MARK: - Communication Channel

/// Represents a communication channel to reach a contact
struct CommunicationChannel: Codable, Identifiable, Equatable {
    var id: String { "\(type.rawValue)-\(endpoint ?? "default")" }

    let type: ChannelType
    var endpoint: String?
    var isAvailable: Bool
    var lastSeen: Date?

    enum ChannelType: String, Codable {
        case localNetwork = "local"      // mDNS/WebSocket
        case arkavoNetwork = "arkavo"    // Arkavo messaging protocol
        case p2p = "p2p"                 // MultipeerConnectivity
    }

    static func localNetwork(endpoint: String, isAvailable: Bool = false) -> CommunicationChannel {
        CommunicationChannel(type: .localNetwork, endpoint: endpoint, isAvailable: isAvailable, lastSeen: nil)
    }

    static func arkavoNetwork(isAvailable: Bool = false) -> CommunicationChannel {
        CommunicationChannel(type: .arkavoNetwork, endpoint: nil, isAvailable: isAvailable, lastSeen: nil)
    }

    static func p2p(isAvailable: Bool = false) -> CommunicationChannel {
        CommunicationChannel(type: .p2p, endpoint: nil, isAvailable: isAvailable, lastSeen: nil)
    }
}

// MARK: - Agent Entitlements

/// Entitlements granted to an agent
struct AgentEntitlements: Codable, Equatable {
    var read: Bool = false
    var write: Bool = false
    var execute: Bool = false
    var delegate: Bool = false
    var admin: Bool = false

    /// Create from array of entitlement strings (e.g., from QR code)
    init(from entitlementStrings: [String]) {
        for entitlement in entitlementStrings {
            let lowercased = entitlement.lowercased()
            if lowercased.contains("read") {
                read = true
            }
            if lowercased.contains("write") {
                write = true
            }
            if lowercased.contains("execute") || lowercased.contains("tools") {
                execute = true
            }
            if lowercased.contains("delegate") {
                delegate = true
            }
            if lowercased.contains("admin") {
                admin = true
            }
            // Handle chat as read+write
            if lowercased.contains("chat") {
                read = true
                write = true
            }
        }
    }

    init(read: Bool = false, write: Bool = false, execute: Bool = false, delegate: Bool = false, admin: Bool = false) {
        self.read = read
        self.write = write
        self.execute = execute
        self.delegate = delegate
        self.admin = admin
    }

    var displayList: [(String, String)] {
        var result: [(String, String)] = []
        if read { result.append(("eye", "Read")) }
        if write { result.append(("pencil", "Write")) }
        if execute { result.append(("wrench.and.screwdriver", "Execute")) }
        if delegate { result.append(("person.badge.key", "Delegate")) }
        if admin { result.append(("shield.checkered", "Admin")) }
        return result
    }

    var isEmpty: Bool {
        !read && !write && !execute && !delegate && !admin
    }
}

// MARK: - Contact Filter

/// Filter options for the unified contacts view
enum ContactFilter: String, CaseIterable {
    case all = "All"
    case people = "People"
    case agents = "Agents"
    case online = "Online"
}
