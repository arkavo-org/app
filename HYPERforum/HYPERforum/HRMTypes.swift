import ArkavoSocial
import Foundation

// MARK: - HRM Orchestration Request

/// Request for full HRM (Hierarchical Reasoning Model) orchestration
struct HRMOrchestrationRequest: Codable, Sendable {
    let messageId: String
    let content: String
    let context: CouncilContext
    let specialists: [String]
    let options: HRMOptions

    init(
        messageId: String,
        content: String,
        context: CouncilContext,
        specialists: [CouncilAgentType],
        options: HRMOptions = .default
    ) {
        self.messageId = messageId
        self.content = content
        self.context = context
        self.specialists = specialists.map(\.rawValue)
        self.options = options
    }
}

/// Options for HRM orchestration behavior
struct HRMOptions: Codable, Sendable {
    let enableCritic: Bool
    let enableSynthesis: Bool
    let maxIterations: Int
    let streamingEnabled: Bool

    init(
        enableCritic: Bool = true,
        enableSynthesis: Bool = true,
        maxIterations: Int = 3,
        streamingEnabled: Bool = true
    ) {
        self.enableCritic = enableCritic
        self.enableSynthesis = enableSynthesis
        self.maxIterations = maxIterations
        self.streamingEnabled = streamingEnabled
    }

    static var `default`: HRMOptions {
        HRMOptions()
    }
}

// MARK: - Context

/// Context for council deliberation
struct CouncilContext: Codable, Sendable {
    let conversationHistory: [ContextMessage]
    let forumId: String?
    let metadata: [String: String]?

    init(
        conversationHistory: [ContextMessage],
        forumId: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.conversationHistory = conversationHistory
        self.forumId = forumId
        self.metadata = metadata
    }

    static var empty: CouncilContext {
        CouncilContext(conversationHistory: [])
    }
}

/// A message in the conversation context
struct ContextMessage: Codable, Sendable {
    let role: String
    let content: String
    let senderName: String?
    let timestamp: Date?

    init(
        role: String,
        content: String,
        senderName: String? = nil,
        timestamp: Date? = nil
    ) {
        self.role = role
        self.content = content
        self.senderName = senderName
        self.timestamp = timestamp
    }

    init(from message: ForumMessage) {
        self.role = "user"
        self.content = message.content
        self.senderName = message.senderName
        self.timestamp = message.timestamp
    }
}

// MARK: - HRM Streaming Deltas

/// Streaming updates from HRM orchestration
enum HRMDelta: Sendable {
    /// Conductor has selected specialists for this task
    case conductorRouting(specialists: [CouncilAgentType])

    /// A specialist has started processing
    case specialistStart(role: CouncilAgentType)

    /// Incremental text from a specialist
    case specialistText(role: CouncilAgentType, text: String)

    /// A specialist has completed with final result
    case specialistComplete(role: CouncilAgentType, result: String)

    /// Critic has reviewed the outputs
    case criticReview(feedback: String, approved: Bool)

    /// Synthesis has started
    case synthesisStart

    /// Incremental text from synthesis
    case synthesisText(text: String)

    /// Final synthesized insight
    case synthesisComplete(result: CouncilInsight)

    /// An error occurred
    case error(code: Int, message: String)

    /// Orchestration complete
    case complete
}

/// Current stage in HRM orchestration
enum HRMStage: String, Sendable {
    case routing
    case specialists
    case critic
    case synthesis
    case complete
}

// MARK: - HRM Response Types

/// Result from a single specialist query
struct SpecialistResult: Codable, Sendable {
    let role: String
    let content: String
    let timestamp: Date
    let criticScore: Double?

    init(
        role: CouncilAgentType,
        content: String,
        timestamp: Date = Date(),
        criticScore: Double? = nil
    ) {
        self.role = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.criticScore = criticScore
    }
}

/// Full HRM orchestration result
struct HRMOrchestrationResult: Sendable {
    let messageId: String
    let specialistResults: [CouncilAgentType: SpecialistResult]
    let criticFeedback: String?
    let synthesis: CouncilInsight
    let totalDuration: TimeInterval

    init(
        messageId: String,
        specialistResults: [CouncilAgentType: SpecialistResult],
        criticFeedback: String?,
        synthesis: CouncilInsight,
        totalDuration: TimeInterval
    ) {
        self.messageId = messageId
        self.specialistResults = specialistResults
        self.criticFeedback = criticFeedback
        self.synthesis = synthesis
        self.totalDuration = totalDuration
    }
}

// MARK: - JSON-RPC Message Parsing

extension HRMDelta {
    /// Parse an HRM delta from a JSON-RPC notification params
    static func parse(from params: [String: Any]) -> HRMDelta? {
        guard let delta = params["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String
        else {
            return nil
        }

        switch deltaType {
        case "conductor_routing":
            let specialistStrings = delta["specialists"] as? [String] ?? []
            let specialists = specialistStrings.compactMap { CouncilAgentType(rawValue: $0) }
            return .conductorRouting(specialists: specialists)

        case "specialist_start":
            guard let roleStr = delta["role"] as? String,
                  let role = CouncilAgentType(rawValue: roleStr)
            else { return nil }
            return .specialistStart(role: role)

        case "specialist_text":
            guard let roleStr = delta["role"] as? String,
                  let role = CouncilAgentType(rawValue: roleStr),
                  let text = delta["text"] as? String
            else { return nil }
            return .specialistText(role: role, text: text)

        case "specialist_complete":
            guard let roleStr = delta["role"] as? String,
                  let role = CouncilAgentType(rawValue: roleStr),
                  let result = delta["result"] as? String
            else { return nil }
            return .specialistComplete(role: role, result: result)

        case "critic_review":
            let feedback = delta["feedback"] as? String ?? ""
            let approved = delta["approved"] as? Bool ?? true
            return .criticReview(feedback: feedback, approved: approved)

        case "synthesis_start":
            return .synthesisStart

        case "synthesis_text":
            guard let text = delta["text"] as? String else { return nil }
            return .synthesisText(text: text)

        case "synthesis_complete":
            guard let resultDict = delta["result"] as? [String: Any],
                  let content = resultDict["content"] as? String
            else { return nil }

            let insight = CouncilInsight(
                id: resultDict["id"] as? String ?? UUID().uuidString,
                messageId: resultDict["message_id"] as? String ?? "",
                agentType: .synthesizer,
                content: content,
                timestamp: Date()
            )
            return .synthesisComplete(result: insight)

        case "error":
            let code = delta["code"] as? Int ?? -1
            let message = delta["message"] as? String ?? "Unknown error"
            return .error(code: code, message: message)

        case "complete":
            return .complete

        default:
            return nil
        }
    }
}

// MARK: - Council Errors

/// Errors that can occur during council operations
enum CouncilError: Error, LocalizedError, Sendable {
    case orchestrationFailed(String)
    case encryptionFailed(String)
    case connectionFailed(String)
    case providerUnavailable
    case invalidResponse(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .orchestrationFailed(let msg):
            return "Orchestration failed: \(msg)"
        case .encryptionFailed(let msg):
            return "Encryption failed: \(msg)"
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .providerUnavailable:
            return "No council provider available"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .timeout:
            return "Operation timed out"
        }
    }
}
