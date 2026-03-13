import ArkavoKit
import Combine
import Foundation
import OSLog

/// Service wrapper for ArkavoAgent integration in ArkavoCreator
/// Provides ObservableObject interface for SwiftUI views and manages agent lifecycle
/// Adapted from iOS AgentService with creator-specific additions
@MainActor
final class CreatorAgentService: ObservableObject {
    private let logger = Logger(subsystem: "com.arkavo.ArkavoCreator", category: "CreatorAgentService")

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

    /// Manual connection URL
    @Published var manualConnectionURL: String {
        didSet {
            UserDefaults.standard.set(manualConnectionURL, forKey: "CreatorAgent.ManualURL")
        }
    }

    /// Auto-discover toggle
    @Published var autoDiscoverEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoDiscoverEnabled, forKey: "CreatorAgent.AutoDiscover")
        }
    }

    /// Daily budget cap
    @Published var dailyBudgetCap: Double {
        didSet {
            UserDefaults.standard.set(dailyBudgetCap, forKey: "CreatorAgent.DailyBudgetCap")
        }
    }

    // MARK: - Private Properties

    private let agentManager: AgentManager
    private let chatManager: AgentChatSessionManager
    private let localAgent: LocalAIAgent
    private var cancellables = Set<AnyCancellable>()

    /// Stream handlers for active sessions (session_id -> AgentStreamHandler)
    private var streamHandlers: [String: AgentStreamHandler] = [:]

    /// Access to the device agent for ID and name
    var deviceAgent: LocalAIAgent? {
        localAgent
    }

    // MARK: - Helper Methods

    /// Check if an agent ID refers to THIS device's agent (on-device LLM)
    private func isThisDeviceAgent(_ agentId: String) -> Bool {
        agentId == localAgent.id
    }

    // MARK: - Initialization

    init() {
        self.agentManager = AgentManager.shared
        self.chatManager = AgentChatSessionManager(agentManager: AgentManager.shared)
        self.localAgent = LocalAIAgent.shared

        // Load persisted settings
        self.manualConnectionURL = UserDefaults.standard.string(forKey: "CreatorAgent.ManualURL") ?? "ws://localhost:8342"
        self.autoDiscoverEnabled = UserDefaults.standard.object(forKey: "CreatorAgent.AutoDiscover") as? Bool ?? true
        self.dailyBudgetCap = UserDefaults.standard.object(forKey: "CreatorAgent.DailyBudgetCap") as? Double ?? 5.0

        // Add built-in device agent as first agent (always available, no discovery)
        let localAgentEndpoint = AgentEndpoint(
            id: localAgent.id,
            url: "local://in-process",
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
        connectedAgents[localAgent.id] = true

        setupBindings()
        logger.log("[CreatorAgentService] Initialized with built-in device agent")
    }

    // MARK: - Setup

    private func setupBindings() {
        agentManager.$agents
            .map { [weak self] discoveredAgents in
                guard let self else { return [] }

                let remoteAgents = discoveredAgents.filter { agent in
                    !self.isThisDeviceAgent(agent.id)
                }

                let builtInLocal = self.discoveredAgents.first { $0.id == self.localAgent.id }

                if let builtInLocal {
                    return [builtInLocal] + remoteAgents
                } else {
                    return remoteAgents
                }
            }
            .assign(to: &$discoveredAgents)

        localAgent.$isPublishing
            .assign(to: &$isDeviceAgentPublishing)
    }

    // MARK: - Device Agent Management

    func startDeviceAgent(port: UInt16 = 0) throws {
        logger.log("[CreatorAgentService] Starting device agent")
        try localAgent.startPublishing(port: port)
    }

    func stopDeviceAgent() {
        logger.log("[CreatorAgentService] Stopping device agent")
        localAgent.stopPublishing()
    }

    func getDeviceCapabilities() -> DeviceCapabilities {
        localAgent.getDeviceCapabilities()
    }

    // MARK: - Discovery

    func startDiscovery() {
        logger.log("[CreatorAgentService] Starting agent discovery")
        isDiscovering = true
        agentManager.startDiscovery()
    }

    func stopDiscovery() {
        logger.log("[CreatorAgentService] Stopping agent discovery")
        isDiscovering = false
        agentManager.stopDiscovery()
    }

    // MARK: - Connection Management

    func connect(to agent: AgentEndpoint) async throws {
        logger.log("[CreatorAgentService] Connecting to agent: \(agent.id)")

        if isThisDeviceAgent(agent.id) {
            connectedAgents[agent.id] = true
            return
        }

        do {
            try await agentManager.connect(to: agent)
            connectedAgents[agent.id] = true
            logger.log("[CreatorAgentService] Successfully connected to agent: \(agent.id)")
        } catch {
            logger.error("[CreatorAgentService] Failed to connect to agent \(agent.id): \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    func disconnect(from agentId: String) async {
        logger.log("[CreatorAgentService] Disconnecting from agent: \(agentId)")

        if isThisDeviceAgent(agentId) {
            connectedAgents[agentId] = false
            return
        }

        await agentManager.disconnect(from: agentId)
        connectedAgents[agentId] = false
    }

    func isConnected(to agentId: String) -> Bool {
        connectedAgents[agentId] ?? false
    }

    /// Connect manually to a WebSocket URL
    func connectManually(url: String) async throws {
        logger.log("[CreatorAgentService] Connecting manually to: \(url)")
        let agentId = "manual-\(url.hashValue)"
        let endpoint = AgentEndpoint(
            id: agentId,
            url: url,
            metadata: AgentMetadata(
                name: "Manual Agent",
                purpose: "Manually connected arkavo-edge instance",
                model: "unknown"
            )
        )

        // Add to discovered agents if not already present
        if !discoveredAgents.contains(where: { $0.id == agentId }) {
            discoveredAgents.append(endpoint)
        }

        try await connect(to: endpoint)
    }

    // MARK: - Chat Session Management

    func openChatSession(with agentId: String) async throws -> ChatSession {
        logger.log("[CreatorAgentService] Opening chat session with agent: \(agentId)")

        if isThisDeviceAgent(agentId) {
            let sessionId = localAgent.openDirectChatSession()
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
            return session
        }

        do {
            let session = try await chatManager.openSession(with: agentId)
            activeSessions[session.id] = session
            sessionAgentMap[session.id] = agentId
            return session
        } catch {
            logger.error("[CreatorAgentService] Failed to open chat session: \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    func sendMessage(sessionId: String, content: String) async throws {
        logger.log("[CreatorAgentService] Sending message to session: \(sessionId)")

        guard let agentId = sessionAgentMap[sessionId] else {
            throw AgentError.notConnected
        }

        if isThisDeviceAgent(agentId) {
            do {
                streamingStates[sessionId] = true
                let response = try await localAgent.sendDirectMessage(sessionId: sessionId, content: content)
                streamingText[sessionId] = response
                try? await Task.sleep(nanoseconds: 100_000_000)
                streamingStates[sessionId] = false
                return
            } catch {
                logger.error("[CreatorAgentService] Failed to send direct message: \(String(describing: error))")
                streamingStates[sessionId] = false
                throw error
            }
        }

        guard let connection = agentManager.getConnection(for: agentId) else {
            throw AgentError.notConnected
        }

        do {
            let streamHandler: AgentStreamHandler
            if let existingHandler = streamHandlers[sessionId] {
                streamHandler = existingHandler
            } else {
                streamHandler = AgentStreamHandler(sessionId: sessionId, connection: connection)
                streamHandlers[sessionId] = streamHandler
                await connection.setNotificationHandler(streamHandler)

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

            try await streamHandler.subscribe()
            try await chatManager.sendMessage(sessionId: sessionId, content: content)
            logger.log("[CreatorAgentService] Message sent successfully, streaming started")
        } catch {
            logger.error("[CreatorAgentService] Failed to send message: \(String(describing: error))")
            lastError = error as? AgentError
            throw error
        }
    }

    func closeChatSession(sessionId: String) async {
        logger.log("[CreatorAgentService] Closing chat session: \(sessionId)")

        if let agentId = sessionAgentMap[sessionId], isThisDeviceAgent(agentId) {
            localAgent.closeDirectChatSession(sessionId: sessionId)
            activeSessions.removeValue(forKey: sessionId)
            sessionAgentMap.removeValue(forKey: sessionId)
            streamingText.removeValue(forKey: sessionId)
            return
        }

        if let streamHandler = streamHandlers[sessionId] {
            await streamHandler.unsubscribe()
            streamHandlers.removeValue(forKey: sessionId)
        }

        streamingText.removeValue(forKey: sessionId)
        streamingStates.removeValue(forKey: sessionId)
        await chatManager.closeSession(sessionId: sessionId)
        activeSessions.removeValue(forKey: sessionId)
        sessionAgentMap.removeValue(forKey: sessionId)
    }

    func getActiveSessions() -> [ChatSession] {
        Array(activeSessions.values)
    }

    func getSession(by sessionId: String) -> ChatSession? {
        activeSessions[sessionId]
    }

    func getSessions(for agentId: String) -> [ChatSession] {
        sessionAgentMap
            .filter { $0.value == agentId }
            .compactMap { activeSessions[$0.key] }
    }

    func getAgentId(for sessionId: String) -> String? {
        sessionAgentMap[sessionId]
    }

    // MARK: - Streaming Helpers

    func isStreaming(sessionId: String) -> Bool {
        streamingStates[sessionId] ?? false
    }

    func getStreamingText(sessionId: String) -> String? {
        streamingText[sessionId]
    }

    func finalizeStream(sessionId: String) -> String? {
        let text = streamingText[sessionId]
        streamingText.removeValue(forKey: sessionId)
        streamingStates[sessionId] = false
        return text
    }

    // MARK: - Budget Methods

    /// Get budget status for an agent via JSON-RPC
    func getBudgetStatus(agentId: String) async throws -> BudgetStatusResponse? {
        guard let connection = agentManager.getConnection(for: agentId) else {
            return nil
        }

        let response = try await connection.call(
            method: "GetBudgetStatus",
            params: [:] as [String: String]
        )

        guard case .success(_, let result) = response else {
            return nil
        }

        let data = try JSONSerialization.data(withJSONObject: result.value)
        return try JSONDecoder().decode(BudgetStatusResponse.self, from: data)
    }

    /// Set budget cap for an agent via JSON-RPC
    func setBudgetCap(agentId: String, daily: Double) async throws {
        guard let connection = agentManager.getConnection(for: agentId) else {
            throw AgentError.notConnected
        }

        let params: [String: Any] = [
            "daily_limit_usd": daily
        ]

        nonisolated(unsafe) let paramsForCall = params
        _ = try await connection.call(
            method: "SetAgentBudget",
            params: paramsForCall
        )
    }

    // MARK: - Creator-Specific Convenience Methods

    /// Draft a social post using AI
    func draftSocialPost(platform: String, tone: String, topic: String, sessionId: String) async throws {
        let prompt = """
        Draft a \(platform) post about "\(topic)" with a \(tone) tone. \
        Follow \(platform) best practices for formatting and length. \
        Include relevant hashtags if appropriate for the platform.
        """
        try await sendMessage(sessionId: sessionId, content: prompt)
    }

    /// Generate a stream title and tags
    func generateStreamTitle(game: String, topic: String, sessionId: String) async throws {
        let prompt = """
        Generate a catchy stream title and 5 relevant tags for a livestream about \
        "\(topic)" playing "\(game)". Format as:
        Title: [title]
        Tags: [tag1], [tag2], [tag3], [tag4], [tag5]
        """
        try await sendMessage(sessionId: sessionId, content: prompt)
    }

    /// Generate a video description
    func describeRecording(context: String, sessionId: String) async throws {
        let prompt = """
        Write a YouTube video description for a recording about "\(context)". \
        Include a brief summary, timestamps placeholder, and SEO-optimized tags. \
        Keep it engaging and searchable.
        """
        try await sendMessage(sessionId: sessionId, content: prompt)
    }

    /// Analyze content
    func analyzeContent(text: String, sessionId: String) async throws {
        let prompt = """
        Analyze the following content and provide:
        - Sentiment (positive/negative/neutral with confidence)
        - Reading level (grade level)
        - Key themes (top 3-5)
        - Suggested improvements

        Content:
        \(text)
        """
        try await sendMessage(sessionId: sessionId, content: prompt)
    }

    // MARK: - Lifecycle

    func onAppearActive() {
        logger.log("[CreatorAgentService] App became active")

        do {
            try startDeviceAgent()
        } catch {
            logger.error("[CreatorAgentService] Failed to start device agent: \(String(describing: error))")
            lastError = .connectionFailed("Failed to start device agent")
        }

        if autoDiscoverEnabled {
            startDiscovery()
        }
    }

    func onDisappear() {
        logger.log("[CreatorAgentService] App going to background")
        stopDiscovery()
        stopDeviceAgent()

        Task {
            for sessionId in activeSessions.keys {
                await closeChatSession(sessionId: sessionId)
            }
        }
    }

    func cleanup() async {
        logger.log("[CreatorAgentService] Cleaning up")
        stopDiscovery()
        stopDeviceAgent()

        for sessionId in activeSessions.keys {
            await closeChatSession(sessionId: sessionId)
        }

        for agentId in connectedAgents.keys {
            await disconnect(from: agentId)
        }

        cancellables.removeAll()
    }
}
