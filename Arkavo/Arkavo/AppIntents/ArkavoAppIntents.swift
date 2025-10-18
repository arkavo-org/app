import AppIntents
import ArkavoAgent
import Foundation

/// Main app intents for Arkavo - enables Siri, Spotlight, and Apple Intelligence integration
@available(iOS 26.0, macOS 26.0, *)
struct SubmitTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Submit Task to Arkavo"
    static var description = IntentDescription("Submit a task to the Arkavo agent system")

    @Parameter(title: "Task Description")
    var taskDescription: String

    @Parameter(title: "Capabilities Hint", default: [])
    var capabilitiesHint: [String]

    func perform() async throws -> some IntentResult {
        // Get the agent service
        let agentService = AgentService()

        // Get device capabilities
        let deviceCaps = agentService.getDeviceCapabilities()

        // Create task offer
        let taskOffer = TaskOffer(
            intentId: UUID().uuidString,
            intent: taskDescription,
            deviceCaps: deviceCaps,
            capabilitiesHint: capabilitiesHint.isEmpty ? nil : capabilitiesHint,
            context: nil
        )

        // Try to submit to Orchestrator
        if let orchestratorId = try await agentService.submitTaskOffer(taskOffer) {
            return .result(dialog: "Task submitted to Orchestrator (\(orchestratorId))")
        } else {
            // No Orchestrator available - try local execution
            return .result(dialog: "No Orchestrator available. Task may be handled locally if possible.")
        }
    }
}

/// Ask a question to an Arkavo agent
@available(iOS 26.0, macOS 26.0, *)
struct AskAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Arkavo Agent"
    static var description = IntentDescription("Ask a question to an Arkavo agent")

    @Parameter(title: "Question")
    var question: String

    @Parameter(title: "Agent Type", default: .orchestrator)
    var agentType: AgentTypeParameter

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let agentService = AgentService()

        // Start discovery to find agents
        agentService.startDiscovery()

        // Wait a moment for discovery
        try await Task.sleep(for: .seconds(2))

        // Find the requested agent type
        guard let agent = findAgent(type: agentType, in: agentService.discoveredAgents) else {
            return .result(value: "No \(agentType.rawValue) agent found", dialog: "Could not find requested agent")
        }

        // Connect to agent
        try await agentService.connect(to: agent)

        // Open chat session
        let session = try await agentService.openChatSession(with: agent.id)

        // Send message
        try await agentService.sendMessage(sessionId: session.id, content: question)

        // Wait for response (simplified - in production, wait for streaming to complete)
        try await Task.sleep(for: .seconds(3))

        // Get response
        let response = agentService.getStreamingText(sessionId: session.id) ?? "No response received"

        // Close session
        await agentService.closeChatSession(sessionId: session.id)

        return .result(value: response, dialog: "Response: \(response)")
    }

    private func findAgent(type: AgentTypeParameter, in agents: [AgentEndpoint]) -> AgentEndpoint? {
        switch type {
        case .orchestrator:
            return agents.first { $0.metadata.purpose.lowercased().contains("orchestrat") }
        case .localAI:
            return agents.first { $0.metadata.purpose.lowercased().contains("local") && $0.metadata.purpose.lowercased().contains("ai") }
        case .any:
            return agents.first
        }
    }
}

/// Agent type parameter for intents
@available(iOS 26.0, macOS 26.0, *)
enum AgentTypeParameter: String, AppEnum {
    case orchestrator = "Orchestrator"
    case localAI = "Local AI"
    case any = "Any Available"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Agent Type")

    static var caseDisplayRepresentations: [AgentTypeParameter: DisplayRepresentation] = [
        .orchestrator: "Orchestrator (for task planning)",
        .localAI: "Local AI (for on-device tasks)",
        .any: "Any available agent",
    ]
}

/// Get sensor data via App Intent
@available(iOS 26.0, macOS 26.0, *)
struct GetSensorDataIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Sensor Data"
    static var description = IntentDescription("Get data from device sensors")

    @Parameter(title: "Sensor Type")
    var sensorType: SensorTypeParameter

    @Parameter(title: "Data Scope", default: .standard)
    var scope: DataScopeParameter

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sensorBridge = SensorBridge()

        let request = SensorRequest(
            taskId: UUID().uuidString,
            sensor: sensorType.toSensorType(),
            scope: scope.toDataScope(),
            policyTag: "app_intent_request"
        )

        do {
            let response = try await sensorBridge.requestSensorData(request)

            // Convert response to string
            if let payload = response.payload.value as? [String: Any] {
                let jsonData = try JSONSerialization.data(withJSONObject: payload)
                let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
                return .result(
                    value: jsonString,
                    dialog: "Sensor data retrieved. Redactions: \(response.redactions.joined(separator: ", "))"
                )
            } else {
                return .result(value: "{}", dialog: "No data available")
            }
        } catch {
            return .result(value: "{}", dialog: "Error: \(error.localizedDescription)")
        }
    }
}

/// Sensor type parameter
@available(iOS 26.0, macOS 26.0, *)
enum SensorTypeParameter: String, AppEnum {
    case location = "Location"
    case motion = "Motion"
    case compass = "Compass"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sensor Type")

    static var caseDisplayRepresentations: [SensorTypeParameter: DisplayRepresentation] = [
        .location: "Location",
        .motion: "Motion",
        .compass: "Compass",
    ]

    func toSensorType() -> SensorType {
        switch self {
        case .location: return .location
        case .motion: return .motion
        case .compass: return .compass
        }
    }
}

/// Data scope parameter
@available(iOS 26.0, macOS 26.0, *)
enum DataScopeParameter: String, AppEnum {
    case minimal = "Minimal"
    case standard = "Standard"
    case detailed = "Detailed"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Data Scope")

    static var caseDisplayRepresentations: [DataScopeParameter: DisplayRepresentation] = [
        .minimal: "Minimal (city-level)",
        .standard: "Standard (street-level)",
        .detailed: "Detailed (precise)",
    ]

    func toDataScope() -> DataScope {
        switch self {
        case .minimal: return .minimal
        case .standard: return .standard
        case .detailed: return .detailed
        }
    }
}

/// App shortcuts provider
@available(iOS 26.0, macOS 26.0, *)
struct ArkavoAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SubmitTaskIntent(),
            phrases: [
                "Submit a task to \(.applicationName)",
                "Ask \(.applicationName) to do something",
                "Tell \(.applicationName) to \(\.$taskDescription)",
            ],
            shortTitle: "Submit Task",
            systemImageName: "paperplane"
        )

        AppShortcut(
            intent: AskAgentIntent(),
            phrases: [
                "Ask \(.applicationName) \(\.$question)",
                "Question for \(.applicationName)",
            ],
            shortTitle: "Ask Agent",
            systemImageName: "bubble.left.and.bubble.right"
        )

        AppShortcut(
            intent: GetSensorDataIntent(),
            phrases: [
                "Get my \(\.$sensorType) from \(.applicationName)",
                "What's my current \(\.$sensorType)",
            ],
            shortTitle: "Get Sensor Data",
            systemImageName: "location"
        )
    }
}
