import ArkavoAgent
import Combine
import Foundation
import OSLog

/// Service wrapper for ArkavoAgent integration
/// Provides ObservableObject interface for SwiftUI views and manages agent lifecycle
@MainActor
final class AgentService: ObservableObject {
    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "AgentService")

    // MARK: - Published Properties

    /// List of discovered agents
    @Published var discoveredAgents: [AgentEndpoint] = []

    /// Currently connected agents (agent_id -> connection status)
    @Published var connectedAgents: [String: Bool] = [:]

    /// Active chat sessions (session_id -> ChatSession)
    @Published var activeSessions: [String: ChatSession] = [:]

    /// Session to agent mapping (session_id -> agent_id)
    private var sessionAgentMap: [String: String] = [:]

    /// Discovery state
    @Published var isDiscovering: Bool = false

    /// Error state
    @Published var lastError: AgentError?

    // MARK: - Private Properties

    private let agentManager: AgentManager
    private let chatManager: AgentChatSessionManager
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        self.agentManager = AgentManager.shared
        self.chatManager = AgentChatSessionManager(agentManager: AgentManager.shared)

        setupBindings()
        logger.log("[AgentService] Initialized")
    }

    // MARK: - Setup

    private func setupBindings() {
        // Bind AgentManager.agents to our published property
        agentManager.$agents
            .assign(to: &$discoveredAgents)
    }

    // MARK: - Discovery

    /// Start discovering agents on the local network
    func startDiscovery() {
        logger.log("[AgentService] Starting agent discovery")
        isDiscovering = true
        agentManager.startDiscovery()
    }

    /// Stop discovering agents
    func stopDiscovery() {
        logger.log("[AgentService] Stopping agent discovery")
        isDiscovering = false
        agentManager.stopDiscovery()
    }

    // MARK: - Connection Management

    /// Connect to a specific agent
    func connect(to agent: AgentEndpoint) async throws {
        logger.log("[AgentService] Connecting to agent: \(agent.id)")

        do {
            try await agentManager.connect(to: agent)
            connectedAgents[agent.id] = true
            logger.log("[AgentService] Successfully connected to agent: \(agent.id)")
        } catch {
            logger.error("[AgentService] Failed to connect to agent \(agent.id): \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    /// Disconnect from a specific agent
    func disconnect(from agentId: String) async {
        logger.log("[AgentService] Disconnecting from agent: \(agentId)")
        await agentManager.disconnect(from: agentId)
        connectedAgents[agentId] = false
    }

    /// Check if connected to a specific agent
    func isConnected(to agentId: String) -> Bool {
        connectedAgents[agentId] ?? false
    }

    // MARK: - Chat Session Management

    /// Open a new chat session with an agent
    func openChatSession(with agentId: String) async throws -> ChatSession {
        logger.log("[AgentService] Opening chat session with agent: \(agentId)")

        do {
            let session = try await chatManager.openSession(with: agentId)
            activeSessions[session.id] = session
            sessionAgentMap[session.id] = agentId
            logger.log("[AgentService] Opened chat session: \(session.id)")
            return session
        } catch {
            logger.error("[AgentService] Failed to open chat session: \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    /// Send a message in an existing chat session
    func sendMessage(sessionId: String, content: String) async throws {
        logger.log("[AgentService] Sending message to session: \(sessionId)")

        do {
            try await chatManager.sendMessage(sessionId: sessionId, content: content)
            logger.log("[AgentService] Message sent successfully")
        } catch {
            logger.error("[AgentService] Failed to send message: \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    /// Close a chat session
    func closeChatSession(sessionId: String) async {
        logger.log("[AgentService] Closing chat session: \(sessionId)")
        await chatManager.closeSession(sessionId: sessionId)
        activeSessions.removeValue(forKey: sessionId)
        sessionAgentMap.removeValue(forKey: sessionId)
    }

    /// Get all active chat sessions
    func getActiveSessions() -> [ChatSession] {
        Array(activeSessions.values)
    }

    /// Get session by ID
    func getSession(by sessionId: String) -> ChatSession? {
        activeSessions[sessionId]
    }

    /// Get sessions for a specific agent
    func getSessions(for agentId: String) -> [ChatSession] {
        sessionAgentMap
            .filter { $0.value == agentId }
            .compactMap { activeSessions[$0.key] }
    }

    /// Get agent ID for a session
    func getAgentId(for sessionId: String) -> String? {
        sessionAgentMap[sessionId]
    }

    // MARK: - Lifecycle

    /// Call when app goes to foreground
    func onAppearActive() {
        logger.log("[AgentService] App became active")
        startDiscovery()
    }

    /// Call when app goes to background
    func onDisappear() {
        logger.log("[AgentService] App going to background")
        stopDiscovery()

        // Close all active sessions
        Task {
            for sessionId in activeSessions.keys {
                await closeChatSession(sessionId: sessionId)
            }
        }
    }

    /// Clean up all connections and sessions
    func cleanup() async {
        logger.log("[AgentService] Cleaning up")
        stopDiscovery()

        // Close all sessions
        for sessionId in activeSessions.keys {
            await closeChatSession(sessionId: sessionId)
        }

        // Disconnect all agents
        for agentId in connectedAgents.keys {
            await disconnect(from: agentId)
        }

        cancellables.removeAll()
    }
}

// MARK: - Helper Extensions
// Note: AgentEndpoint already conforms to Identifiable in the ArkavoAgent package
