import ArkavoKit
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

    /// Streaming text for active sessions (session_id -> accumulated text)
    @Published var streamingText: [String: String] = [:]

    /// Streaming state for sessions (session_id -> isStreaming)
    @Published var streamingStates: [String: Bool] = [:]

    /// Discovery state
    @Published var isDiscovering: Bool = false

    /// Device agent publishing state
    @Published var isDeviceAgentPublishing: Bool = false

    /// Error state
    @Published var lastError: AgentError?

    // MARK: - Private Properties

    private let agentManager: AgentManager
    private let chatManager: AgentChatSessionManager
    private let localAgent: LocalAIAgent
    private var cancellables = Set<AnyCancellable>()

    /// Access to the device agent for ID and name
    var deviceAgent: LocalAIAgent? {
        localAgent
    }

    /// Stream handlers for active sessions (session_id -> AgentStreamHandler)
    private var streamHandlers: [String: AgentStreamHandler] = [:]

    // MARK: - Helper Methods

    /// Check if an agent ID refers to THIS device's agent (on-device LLM)
    /// Other devices' agents (even with device_agent_ prefix) are remote and need WebSocket
    private func isThisDeviceAgent(_ agentId: String) -> Bool {
        return agentId == localAgent.id
    }

    // MARK: - Initialization

    init() {
        self.agentManager = AgentManager.shared
        self.chatManager = AgentChatSessionManager(agentManager: AgentManager.shared)
        self.localAgent = LocalAIAgent.shared

        // Add built-in device agent as first agent (always available, no discovery)
        // Use unique ID from device agent instance (device-specific)
        let localAgentEndpoint = AgentEndpoint(
            id: localAgent.id,
            url: "local://in-process", // Not used, but required
            metadata: AgentMetadata(
                name: localAgent.name,
                purpose: "On-device intelligence and sensor access",
                model: "on-device",
                properties: [
                    "capabilities": "sensors,foundation_models,writing_tools,image_playground,sentiment_analysis"
                ]
            )
        )
        discoveredAgents.append(localAgentEndpoint)
        connectedAgents[localAgent.id] = true // Always "connected" (in-process)

        setupBindings()
        logger.log("[AgentService] Initialized with built-in device agent")
    }

    // MARK: - Setup

    private func setupBindings() {
        // Bind AgentManager.agents to our published property
        // Filter out device agent if it appears in mDNS discovery (it shouldn't discover itself)
        // Then prepend our built-in device agent endpoint
        agentManager.$agents
            .map { [weak self] discoveredAgents in
                guard let self = self else { return [] }

                // Filter out any device agent from mDNS discovery
                let remoteAgents = discoveredAgents.filter { agent in
                    // Exclude device agents (they're handled in-process)
                    return !self.isThisDeviceAgent(agent.id)
                }

                // Get built-in device agent (first in list)
                let builtInLocal = self.discoveredAgents.first { $0.id == self.localAgent.id }

                // Return built-in device agent first, then remote agents
                if let builtInLocal = builtInLocal {
                    return [builtInLocal] + remoteAgents
                } else {
                    return remoteAgents
                }
            }
            .assign(to: &$discoveredAgents)

        // Bind device agent publishing state
        localAgent.$isPublishing
            .assign(to: &$isDeviceAgentPublishing)
    }

    // MARK: - Device Agent Management

    /// Start publishing device agent as an A2A service
    func startDeviceAgent(port: UInt16 = 0) throws {
        logger.log("[AgentService] Starting device agent")
        try localAgent.startPublishing(port: port)
    }

    /// Stop publishing device agent
    func stopDeviceAgent() {
        logger.log("[AgentService] Stopping device agent")
        localAgent.stopPublishing()
    }

    /// Get device capabilities from device agent
    func getDeviceCapabilities() -> DeviceCapabilities {
        localAgent.getDeviceCapabilities()
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

        // device agent doesn't need WebSocket connection - it's in-process
        if isThisDeviceAgent(agent.id) {
            logger.log("[AgentService] Skipping WebSocket connection for device agent (in-process)")
            connectedAgents[agent.id] = true // Mark as "connected" for UI purposes
            return
        }

        // For remote agents, establish WebSocket connection
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

        // device agent doesn't have WebSocket connection to disconnect
        if isThisDeviceAgent(agentId) {
            logger.log("[AgentService] device agent disconnect (no-op, in-process)")
            connectedAgents[agentId] = false
            return
        }

        // For remote agents, disconnect WebSocket
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

        // For device agent, use direct in-process call (no WebSocket)
        if isThisDeviceAgent(agentId) {
            logger.log("[AgentService] Using direct in-process chat for device agent")
            let sessionId = localAgent.openDirectChatSession()

            // Create a ChatSession compatible with UI
            let session = ChatSession(
                id: sessionId,
                capabilities: ChatCapabilities(
                    supportedMessageTypes: ["text"],
                    maxMessageLength: 10000,
                    supportsStreaming: false
                ),
                createdAt: Date()
            )

            activeSessions[session.id] = session
            sessionAgentMap[session.id] = agentId
            logger.log("[AgentService] Opened direct chat session: \(session.id)")
            return session
        }

        // For remote agents, use WebSocket connection
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

    /// Send a message in an existing chat session with streaming support
    func sendMessage(sessionId: String, content: String) async throws {
        logger.log("[AgentService] Sending message to session: \(sessionId)")

        // Get agent ID for this session
        guard let agentId = sessionAgentMap[sessionId] else {
            throw AgentError.notConnected
        }

        // For device agent, use direct in-process call
        if isThisDeviceAgent(agentId) {
            logger.log("[AgentService] Using direct in-process message send for device agent")
            do {
                // Start streaming state
                streamingStates[sessionId] = true

                let response = try await localAgent.sendDirectMessage(sessionId: sessionId, content: content)

                // Update streaming text with the response
                logger.log("[AgentService] Got response from device agent: '\(response)' (length: \(response.count))")
                streamingText[sessionId] = response
                logger.log("[AgentService] Set streamingText[\(sessionId)] = '\(response)'")
                logger.log("[AgentService] Direct message sent and received response")

                // Small delay to ensure UI processes the text update before we end streaming
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                // End streaming state (triggers message finalization in UI)
                streamingStates[sessionId] = false
                logger.log("[AgentService] Set streamingStates[\(sessionId)] = false")

                return
            } catch {
                logger.error("[AgentService] Failed to send direct message: \(String(describing: error))")
                streamingStates[sessionId] = false
                throw error
            }
        }

        // For remote agents, use WebSocket streaming
        guard let connection = agentManager.getConnection(for: agentId) else {
            throw AgentError.notConnected
        }

        do {
            // Create or get stream handler for this session
            let streamHandler: AgentStreamHandler
            if let existingHandler = streamHandlers[sessionId] {
                streamHandler = existingHandler
            } else {
                streamHandler = AgentStreamHandler(sessionId: sessionId, connection: connection)
                streamHandlers[sessionId] = streamHandler

                // Set up notification handler on the connection
                await connection.setNotificationHandler(streamHandler)

                // Bind stream handler's published properties to our own
                streamHandler.$streamingText
                    .sink { [weak self] text in
                        self?.streamingText[sessionId] = text
                    }
                    .store(in: &cancellables)

                streamHandler.$isStreaming
                    .sink { [weak self] isStreaming in
                        self?.streamingStates[sessionId] = isStreaming
                    }
                    .store(in: &cancellables)
            }

            // Subscribe to streaming before sending the message
            try await streamHandler.subscribe()

            // Send the message
            try await chatManager.sendMessage(sessionId: sessionId, content: content)

            // DISABLED: Auto-acknowledgment causes infinite loop
            // TODO: Fix auto-acknowledgment task lifecycle
            // streamHandler.startAutoAcknowledgment()

            logger.log("[AgentService] Message sent successfully, streaming started")
        } catch {
            logger.error("[AgentService] Failed to send message: \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    /// Close a chat session
    func closeChatSession(sessionId: String) async {
        logger.log("[AgentService] Closing chat session: \(sessionId)")

        // Check if this is a device agent session
        if let agentId = sessionAgentMap[sessionId], isThisDeviceAgent(agentId) {
            logger.log("[AgentService] Closing direct device agent session")
            localAgent.closeDirectChatSession(sessionId: sessionId)
            activeSessions.removeValue(forKey: sessionId)
            sessionAgentMap.removeValue(forKey: sessionId)
            streamingText.removeValue(forKey: sessionId)
            return
        }

        // For remote agents, unsubscribe from streaming
        if let streamHandler = streamHandlers[sessionId] {
            await streamHandler.unsubscribe()
            streamHandlers.removeValue(forKey: sessionId)
        }

        // Clean up streaming state
        streamingText.removeValue(forKey: sessionId)
        streamingStates.removeValue(forKey: sessionId)

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

    // MARK: - Streaming Helpers

    /// Check if a session is currently streaming
    func isStreaming(sessionId: String) -> Bool {
        streamingStates[sessionId] ?? false
    }

    /// Get the current streaming text for a session
    func getStreamingText(sessionId: String) -> String? {
        streamingText[sessionId]
    }

    /// Get the final accumulated text and complete streaming
    func finalizeStream(sessionId: String) -> String? {
        let text = streamingText[sessionId]
        streamingText.removeValue(forKey: sessionId)
        streamingStates[sessionId] = false
        return text
    }

    // MARK: - Lifecycle

    /// Call when app goes to foreground
    func onAppearActive() {
        logger.log("[AgentService] App became active")

        // Start device agent to publish on-device capabilities
        do {
            try startDeviceAgent()
        } catch {
            logger.error("[AgentService] Failed to start device agent: \(String(describing: error))")
            lastError = .connectionFailed("Failed to start device agent")
        }

        // Start discovering other agents
        startDiscovery()
    }

    /// Call when app goes to background
    func onDisappear() {
        logger.log("[AgentService] App going to background")
        stopDiscovery()
        stopDeviceAgent()

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
        stopDeviceAgent()

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

    // MARK: - Task Submission

    /// Submit a task offer to the Orchestrator (if available)
    /// Returns the agent ID of the Orchestrator if found, nil otherwise
    func submitTaskOffer(_ taskOffer: TaskOffer) async throws -> String? {
        // Find the Orchestrator agent (look for purpose "orchestrator" or "Orchestrator")
        guard let orchestrator = discoveredAgents.first(where: { agent in
            agent.metadata.purpose.lowercased().contains("orchestrat")
        }) else {
            logger.warning("[AgentService] No Orchestrator found - task cannot be submitted")
            return nil
        }

        logger.log("[AgentService] Submitting task offer to Orchestrator: \(orchestrator.id)")

        // Connect if not already connected
        if !isConnected(to: orchestrator.id) {
            try await connect(to: orchestrator)
        }

        // Get connection
        guard let connection = agentManager.getConnection(for: orchestrator.id) else {
            throw AgentError.notConnected
        }

        // Send task_offer request
        let params = AnyCodable(taskOffer)
        let request = AgentRequest(
            method: "task_offer",
            params: params,
            id: UUID().uuidString
        )

        _ = try await connection.sendRequest(request)

        logger.log("[AgentService] Task offer submitted successfully")
        return orchestrator.id
    }
}

// MARK: - Helper Extensions
// Note: AgentEndpoint already conforms to Identifiable in the ArkavoAgent package
