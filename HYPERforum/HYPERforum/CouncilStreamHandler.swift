import ArkavoAgent
import ArkavoSocial
import Foundation

/// Handles streaming notifications from HRM orchestration
@MainActor
final class CouncilStreamHandler: AgentNotificationHandler {
    // MARK: - Properties

    /// Stream of HRM deltas
    var deltaStream: AsyncThrowingStream<HRMDelta, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
        }
    }

    private var continuation: AsyncThrowingStream<HRMDelta, Error>.Continuation?
    private var isComplete = false

    // MARK: - Initialization

    init() {}

    // MARK: - AgentNotificationHandler

    func handleNotification(method: String, params: AnyCodable) async {
        // Handle HRM stream notifications
        guard method == "hrm_stream" || method == "hrm.stream" else {
            return
        }

        guard let paramsDict = params.value as? [String: Any] else {
            return
        }

        // Parse the delta
        if let delta = HRMDelta.parse(from: paramsDict) {
            continuation?.yield(delta)

            // Check for completion
            if case .complete = delta {
                isComplete = true
                continuation?.finish()
            } else if case .error = delta {
                isComplete = true
                continuation?.finish()
            }
        }
    }

    // MARK: - Manual Control

    /// Manually emit a delta (for testing or local simulation)
    func emit(_ delta: HRMDelta) {
        guard !isComplete else { return }
        continuation?.yield(delta)
    }

    /// Manually complete the stream
    func complete() {
        guard !isComplete else { return }
        isComplete = true
        continuation?.yield(.complete)
        continuation?.finish()
    }

    /// Manually fail the stream
    func fail(with error: Error) {
        guard !isComplete else { return }
        isComplete = true
        continuation?.finish(throwing: error)
    }

    /// Cancel the stream
    func cancel() {
        guard !isComplete else { return }
        isComplete = true
        continuation?.finish()
    }
}

// MARK: - Streaming Accumulator

/// Accumulates streaming content for display
@MainActor
final class StreamingContentAccumulator: ObservableObject {
    @Published var specialistContent: [CouncilAgentType: String] = [:]
    @Published var synthesisContent: String = ""
    @Published var currentStage: HRMStage = .routing
    @Published var activeSpecialists: [CouncilAgentType] = []
    @Published var completedSpecialists: Set<CouncilAgentType> = []
    @Published var criticFeedback: String?
    @Published var isApproved: Bool = true

    init() {}

    /// Process an HRM delta and update state
    func process(_ delta: HRMDelta) {
        switch delta {
        case let .conductorRouting(specialists):
            currentStage = .routing
            activeSpecialists = specialists
            // Initialize content for each specialist
            for specialist in specialists {
                specialistContent[specialist] = ""
            }

        case let .specialistStart(role):
            currentStage = .specialists
            if specialistContent[role] == nil {
                specialistContent[role] = ""
            }

        case let .specialistText(role, text):
            specialistContent[role, default: ""] += text

        case let .specialistComplete(role, result):
            specialistContent[role] = result
            completedSpecialists.insert(role)

        case let .criticReview(feedback, approved):
            currentStage = .critic
            criticFeedback = feedback
            isApproved = approved

        case .synthesisStart:
            currentStage = .synthesis
            synthesisContent = ""

        case let .synthesisText(text):
            synthesisContent += text

        case let .synthesisComplete(result):
            synthesisContent = result.content
            currentStage = .complete

        case let .error(code, message):
            criticFeedback = "Error [\(code)]: \(message)"
            isApproved = false

        case .complete:
            currentStage = .complete
        }
    }

    /// Reset all accumulated state
    func reset() {
        specialistContent.removeAll()
        synthesisContent = ""
        currentStage = .routing
        activeSpecialists = []
        completedSpecialists = []
        criticFeedback = nil
        isApproved = true
    }
}
