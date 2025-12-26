@preconcurrency import ArkavoAgent
import Combine
import Foundation

/// Provider that connects to Arkavo Edge for HRM orchestration
@MainActor
final class ArkavoEdgeCouncilProvider: ObservableObject, CouncilConnectionProvider {
    // MARK: - Published Properties

    @Published private(set) var isConnected: Bool = false
    @Published private(set) var connectionStatus: ConnectionStatus = .disconnected

    let providerType: CouncilProviderType = .arkavoEdge

    // MARK: - Private Properties

    private let discoveryService: AgentDiscoveryService
    private var edgeConnection: AgentConnection?
    private var streamHandler: CouncilStreamHandler?
    private var sessionId: String?
    private var cancellables = Set<AnyCancellable>()

    // Configuration
    private let edgeServicePrefix = "arkavo-edge"
    private let discoveryTimeoutSeconds: TimeInterval = 5.0

    // MARK: - Initialization

    init() {
        discoveryService = AgentDiscoveryService()
        setupDiscoveryObserver()
    }

    // MARK: - Connection Management

    func connect() async throws {
        connectionStatus = .connecting

        // Start discovery if not already running
        if !discoveryService.isDiscovering {
            discoveryService.startDiscovery()
        }

        // Wait for edge to be discovered
        let edgeEndpoint = try await waitForEdgeDiscovery()

        // Create and connect
        let connection = AgentConnection(endpoint: edgeEndpoint)
        try await connection.connect()

        edgeConnection = connection
        isConnected = true
        connectionStatus = .connected

        // Open HRM session
        sessionId = try await openHRMSession()

        print("Connected to Arkavo Edge at \(edgeEndpoint.url)")
    }

    func disconnect() async {
        if let connection = edgeConnection {
            await connection.disconnect()
        }

        edgeConnection = nil
        streamHandler = nil
        sessionId = nil
        isConnected = false
        connectionStatus = .disconnected

        discoveryService.stopDiscovery()
    }

    /// Start background discovery and auto-connect
    func startWithAutoConnect() {
        discoveryService.startDiscovery()
    }

    // MARK: - Specialist Query

    func executeSpecialistQuery(
        role: CouncilAgentType,
        prompt: String,
        context: CouncilContext
    ) async throws -> String {
        guard let connection = edgeConnection, await connection.isConnected() else {
            throw CouncilError.connectionFailed("Not connected to Arkavo Edge")
        }

        nonisolated(unsafe) let params: [String: Any] = [
            "session_id": sessionId ?? "",
            "role": role.rawValue,
            "prompt": prompt,
            "context": encodeContext(context),
        ]
        let response = try await connection.call(method: "hrm.specialist", params: params)

        switch response {
        case let .success(_, result):
            if let resultDict = result.value as? [String: Any],
               let content = resultDict["content"] as? String
            {
                return content
            }
            throw CouncilError.invalidResponse("Missing content in response")

        case let .error(_, code, message):
            throw CouncilError.orchestrationFailed("[\(code)] \(message)")
        }
    }

    // MARK: - HRM Orchestration

    func executeHRMOrchestration(
        request: HRMOrchestrationRequest
    ) async throws -> AsyncThrowingStream<HRMDelta, Error> {
        guard let connection = edgeConnection, await connection.isConnected() else {
            throw CouncilError.connectionFailed("Not connected to Arkavo Edge")
        }

        // Create stream handler for this session
        let handler = CouncilStreamHandler()
        streamHandler = handler

        // Set up notification handling
        await connection.setNotificationHandler(handler)

        // Send orchestration request
        nonisolated(unsafe) let orchestrateParams: [String: Any] = [
            "session_id": sessionId ?? "",
            "message_id": request.messageId,
            "content": request.content,
            "context": encodeContext(request.context),
            "specialists": request.specialists,
            "options": [
                "enable_critic": request.options.enableCritic,
                "enable_synthesis": request.options.enableSynthesis,
                "max_iterations": request.options.maxIterations,
                "streaming_enabled": request.options.streamingEnabled,
            ] as [String: Any],
        ]
        _ = try await connection.call(method: "hrm.orchestrate", params: orchestrateParams)

        // Return the stream from the handler
        return handler.deltaStream
    }

    // MARK: - Private Methods

    private func setupDiscoveryObserver() {
        discoveryService.$discoveredAgents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agents in
                self?.handleDiscoveredAgents(agents)
            }
            .store(in: &cancellables)
    }

    private func handleDiscoveredAgents(_ agents: [AgentEndpoint]) {
        // Look for arkavo-edge in discovered agents
        if let edgeAgent = agents.first(where: { isEdgeAgent($0) }) {
            print("Found Arkavo Edge: \(edgeAgent.id) at \(edgeAgent.url)")

            // Auto-connect if not already connected
            if !isConnected {
                Task {
                    do {
                        try await connectToEdge(edgeAgent)
                    } catch {
                        print("Auto-connect failed: \(error)")
                    }
                }
            }
        }
    }

    private func isEdgeAgent(_ agent: AgentEndpoint) -> Bool {
        let id = agent.id.lowercased()
        let name = agent.metadata.name.lowercased()
        let purpose = agent.metadata.purpose.lowercased()

        return id.contains("edge") ||
            id.contains("hrm") ||
            name.contains("edge") ||
            purpose.contains("orchestrat")
    }

    private func waitForEdgeDiscovery() async throws -> AgentEndpoint {
        // Check if already discovered
        if let edge = discoveryService.discoveredAgents.first(where: { isEdgeAgent($0) }) {
            return edge
        }

        // Wait for discovery with timeout
        let deadline = Date().addingTimeInterval(discoveryTimeoutSeconds)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            if let edge = discoveryService.discoveredAgents.first(where: { isEdgeAgent($0) }) {
                return edge
            }
        }

        throw CouncilError.connectionFailed("Arkavo Edge not found on network")
    }

    private func connectToEdge(_ endpoint: AgentEndpoint) async throws {
        connectionStatus = .connecting

        let connection = AgentConnection(endpoint: endpoint)
        try await connection.connect()

        edgeConnection = connection
        isConnected = true
        connectionStatus = .connected

        sessionId = try await openHRMSession()
    }

    private func openHRMSession() async throws -> String {
        guard let connection = edgeConnection else {
            throw CouncilError.connectionFailed("No connection available")
        }

        let response = try await connection.call(method: "hrm.session.open", params: [:])

        switch response {
        case let .success(_, result):
            if let resultDict = result.value as? [String: Any],
               let id = resultDict["session_id"] as? String
            {
                return id
            }
            // If no session_id returned, generate one client-side
            return UUID().uuidString

        case let .error(_, code, message):
            // Some servers don't require explicit sessions - use UUID
            print("Session open warning: [\(code)] \(message)")
            return UUID().uuidString
        }
    }

    private func encodeContext(_ context: CouncilContext) -> [String: Any] {
        var result: [String: Any] = [:]

        result["conversation_history"] = context.conversationHistory.map { msg in
            [
                "role": msg.role,
                "content": msg.content,
                "sender_name": msg.senderName ?? "",
                "timestamp": msg.timestamp?.timeIntervalSince1970 ?? 0,
            ] as [String: Any]
        }

        if let forumId = context.forumId {
            result["forum_id"] = forumId
        }

        if let metadata = context.metadata {
            result["metadata"] = metadata
        }

        return result
    }
}

// MARK: - Connection Status Extension

extension ConnectionStatus {
    var isConnectedOrConnecting: Bool {
        switch self {
        case .connected, .connecting:
            return true
        default:
            return false
        }
    }
}
