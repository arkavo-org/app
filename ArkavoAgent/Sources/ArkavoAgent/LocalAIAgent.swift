import Foundation
import Network

/// LocalAIAgent: A participant agent that exposes on-device capabilities via A2A protocol
/// - Publishes itself as an A2A service via mDNS
/// - Handles sensor requests with policy enforcement
/// - Executes local tool calls (Foundation Models, Writing Tools, Image Playground)
/// - Routes to Orchestrator for task planning
@MainActor
public final class LocalAIAgent: NSObject, ObservableObject {
    public static let shared = LocalAIAgent()

    @Published public private(set) var isPublishing = false
    @Published public private(set) var lastError: String?

    private var listener: NWListener?
    private let sensorBridge: SensorBridge
    private let appleIntelligenceClient: AppleIntelligenceClient
    private let writingTools: WritingToolsIntegration
    private let imagePlayground: ImagePlaygroundIntegration
    private var connections: [UUID: NWConnection] = [:]

    private let agentId = "local_ai_agent"
    private let agentName = "LocalAI Agent"
    private let agentPurpose = "Local AI for on-device intelligence and sensor access"

    private override init() {
        sensorBridge = SensorBridge()
        appleIntelligenceClient = AppleIntelligenceClient()
        writingTools = WritingToolsIntegration()
        imagePlayground = ImagePlaygroundIntegration()
        super.init()
    }

    /// Start publishing the LocalAIAgent as an A2A service
    public func startPublishing(port: UInt16 = 0) throws {
        guard !isPublishing else {
            print("[LocalAIAgent] Already publishing")
            return
        }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true

        let options = NWProtocolWebSocket.Options()
        params.defaultProtocolStack.applicationProtocols.insert(options, at: 0)

        listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

        listener?.service = NWListener.Service(
            name: agentName,
            type: "_a2a._tcp",
            txtRecord: buildTxtRecord()
        )

        listener?.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                await self?.handleListenerState(state)
            }
        }

        listener?.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                await self?.handleNewConnection(connection)
            }
        }

        listener?.start(queue: .main)
        isPublishing = true

        print("[LocalAIAgent] Started publishing on port \(port)")
    }

    /// Stop publishing the A2A service
    public func stopPublishing() {
        listener?.cancel()
        listener = nil

        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()

        isPublishing = false
        print("[LocalAIAgent] Stopped publishing")
    }

    private func buildTxtRecord() -> NWTXTRecord {
        var record = NWTXTRecord()

        record["agent_id"] = agentId
        record["name"] = agentName
        record["purpose"] = agentPurpose
        record["model"] = "on-device"
        record["capabilities"] = "sensors,foundation_models,writing_tools,image_playground"

        return record
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener?.port {
                print("[LocalAIAgent] Listener ready on port \(port)")
            }
        case let .failed(error):
            print("[LocalAIAgent] Listener failed: \(error)")
            lastError = error.localizedDescription
            isPublishing = false
        case .cancelled:
            print("[LocalAIAgent] Listener cancelled")
            isPublishing = false
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        connections[connectionId] = connection

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                await self?.handleConnectionState(connectionId, state: state)
            }
        }

        connection.start(queue: .main)

        receiveMessage(from: connection, connectionId: connectionId)

        print("[LocalAIAgent] New connection: \(connectionId)")
    }

    private func handleConnectionState(_ connectionId: UUID, state: NWConnection.State) {
        switch state {
        case .ready:
            print("[LocalAIAgent] Connection ready: \(connectionId)")
        case let .failed(error):
            print("[LocalAIAgent] Connection failed: \(connectionId), error: \(error)")
            connections.removeValue(forKey: connectionId)
        case .cancelled:
            print("[LocalAIAgent] Connection cancelled: \(connectionId)")
            connections.removeValue(forKey: connectionId)
        default:
            break
        }
    }

    private func receiveMessage(from connection: NWConnection, connectionId: UUID) {
        connection.receiveMessage { [weak self] completeContent, contentContext, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    print("[LocalAIAgent] Receive error: \(error)")
                    return
                }

                if let data = completeContent {
                    await self.handleMessage(data, from: connection, connectionId: connectionId)
                }

                if !isComplete {
                    self.receiveMessage(from: connection, connectionId: connectionId)
                }
            }
        }
    }

    private func handleMessage(_ data: Data, from connection: NWConnection, connectionId: UUID) async {
        do {
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw LocalAIAgentError.invalidMessageEncoding
            }

            let request = try JSONDecoder().decode(AgentRequest.self, from: Data(jsonString.utf8))

            print("[LocalAIAgent] Received request: \(request.method)")

            let response = try await processRequest(request)

            try await sendResponse(response, to: connection)
        } catch {
            print("[LocalAIAgent] Error handling message: \(error)")

            let errorResponse = AgentResponse.error(
                id: UUID().uuidString,
                code: -32603,
                message: error.localizedDescription
            )

            try? await sendResponse(errorResponse, to: connection)
        }
    }

    private func processRequest(_ request: AgentRequest) async throws -> AgentResponse {
        switch request.method {
        case "sensor_request":
            return try await handleSensorRequest(request)
        case "tool_call":
            return try await handleToolCall(request)
        case "task_offer":
            return try await handleTaskOffer(request)
        case "chat_open":
            return try await handleChatOpen(request)
        default:
            throw LocalAIAgentError.unknownMethod(request.method)
        }
    }

    private func handleSensorRequest(_ request: AgentRequest) async throws -> AgentResponse {
        let sensorRequest = try decodeParams(SensorRequest.self, from: request.params)

        let sensorResponse = try await sensorBridge.requestSensorData(sensorRequest)

        return AgentResponse.success(
            id: request.id,
            result: AnyCodable(sensorResponse)
        )
    }

    private func handleToolCall(_ request: AgentRequest) async throws -> AgentResponse {
        let toolCall = try decodeParams(ToolCall.self, from: request.params)

        guard toolCall.locality == .local else {
            throw LocalAIAgentError.remoteToolCallNotSupported
        }

        let result = try await executeLocalToolCall(toolCall)

        return AgentResponse.success(
            id: request.id,
            result: AnyCodable(result)
        )
    }

    private func executeLocalToolCall(_ toolCall: ToolCall) async throws -> ToolCallResult {
        // Route to appropriate local capability based on tool name
        if toolCall.name.starts(with: "foundation_models_") {
            return try await appleIntelligenceClient.executeToolCall(toolCall)
        } else if toolCall.name.starts(with: "writing_tools_") {
            return try await writingTools.executeToolCall(toolCall)
        } else if toolCall.name.starts(with: "image_playground_") {
            return try await imagePlayground.executeToolCall(toolCall)
        } else {
            throw LocalAIAgentError.toolNotImplemented(toolCall.name)
        }
    }

    private func handleTaskOffer(_ request: AgentRequest) async throws -> AgentResponse {
        let taskOffer = try decodeParams(TaskOffer.self, from: request.params)

        print("[LocalAIAgent] Received task offer: \(taskOffer.intent)")

        throw LocalAIAgentError.orchestratorRequired
    }

    private func handleChatOpen(_ request: AgentRequest) async throws -> AgentResponse {
        print("[LocalAIAgent] Opening chat session")

        throw LocalAIAgentError.notImplemented
    }

    private func sendResponse(_ response: AgentResponse, to connection: NWConnection) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(response)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, from params: AnyCodable) throws -> T {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(params)
        return try decoder.decode(type, from: data)
    }

    /// Get current device capabilities
    public func getDeviceCapabilities() -> DeviceCapabilities {
        DeviceCapabilities(
            aiCapabilities: [
                .foundationModels,
                .writingTools,
                .imagePlayground,
                .speechRecognition,
                .textToSpeech,
            ],
            sensors: [
                .location,
                .camera,
                .microphone,
                .motion,
                .nearbyDevices,
                .compass,
            ],
            platform: getCurrentPlatform(),
            osVersion: getOSVersion()
        )
    }

    private func getCurrentPlatform() -> DevicePlatform {
        #if os(iOS)
            return .ios
        #elseif os(macOS)
            return .macos
        #elseif os(tvOS)
            return .tvos
        #elseif os(watchOS)
            return .watchos
        #else
            return .ios
        #endif
    }

    private func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

public enum LocalAIAgentError: Error, LocalizedError {
    case invalidMessageEncoding
    case unknownMethod(String)
    case remoteToolCallNotSupported
    case toolNotImplemented(String)
    case orchestratorRequired
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .invalidMessageEncoding:
            return "Invalid message encoding"
        case let .unknownMethod(method):
            return "Unknown method: \(method)"
        case .remoteToolCallNotSupported:
            return "Remote tool calls must be sent to Orchestrator"
        case let .toolNotImplemented(name):
            return "Tool not yet implemented: \(name)"
        case .orchestratorRequired:
            return "Task offers must be sent to Orchestrator for planning"
        case .notImplemented:
            return "Feature not yet implemented"
        }
    }
}
