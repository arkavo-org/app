import ArkavoAgent
import Combine
import Foundation
import SwiftUI

/// Manages AI Council interactions for augmented discourse
@MainActor
class AICouncilManager: ObservableObject {
    // MARK: - Published Properties

    @Published var isProcessing = false
    @Published var currentInsight: CouncilInsight?
    @Published var error: String?
    @Published var availableAgents: [CouncilAgentType] = CouncilAgentType.allCases

    // Connection and HRM state
    @Published var connectionMode: CouncilConnectionMode = .discovering
    @Published var hrmStage: HRMStage?
    @Published var streamingContent: [CouncilAgentType: String] = [:]

    // MARK: - Private Properties

    private let edgeProvider: ArkavoEdgeCouncilProvider
    private let localProvider: LocalAICouncilProvider
    private var activeProvider: (any CouncilConnectionProvider)?

    private var encryptionManager: EncryptionManager?
    private var cancellables = Set<AnyCancellable>()

    // Discovery timeout
    private let discoveryTimeoutSeconds: TimeInterval = 5.0

    // MARK: - Initialization

    init(encryptionManager: EncryptionManager? = nil) {
        self.encryptionManager = encryptionManager
        edgeProvider = ArkavoEdgeCouncilProvider()
        localProvider = LocalAICouncilProvider()

        setupProviderObservers()
    }

    // MARK: - Connection Management

    /// Start discovering Arkavo Edge on the network
    func startDiscovery() {
        connectionMode = .discovering
        edgeProvider.startWithAutoConnect()

        // Set a timeout to fall back to local
        Task {
            try? await Task.sleep(nanoseconds: UInt64(discoveryTimeoutSeconds * 1_000_000_000))
            if connectionMode == .discovering {
                await fallbackToLocal()
            }
        }
    }

    /// Stop discovery and disconnect
    func stopDiscovery() {
        Task {
            await edgeProvider.disconnect()
            await localProvider.disconnect()
        }
        connectionMode = .disconnected
    }

    // MARK: - Public Methods

    /// Get AI insight for a specific message
    func getInsight(for message: ForumMessage, type: CouncilAgentType = .analyst) async throws -> CouncilInsight {
        isProcessing = true
        error = nil

        defer {
            isProcessing = false
        }

        let provider = await selectActiveProvider()
        let prompt = createInsightPrompt(for: message, type: type)
        let context = createContext(for: [message])

        do {
            let response = try await provider.executeSpecialistQuery(
                role: type,
                prompt: prompt,
                context: context
            )

            var insight = CouncilInsight(
                id: UUID().uuidString,
                messageId: message.id,
                agentType: type,
                content: response,
                timestamp: Date()
            )

            // Encrypt if enabled
            if let encrypted = try? await encryptInsight(insight) {
                insight = encrypted
            }

            currentInsight = insight
            return insight

        } catch {
            // Fallback to local on Edge failure
            if provider.providerType == .arkavoEdge {
                return try await fallbackGetInsight(message: message, type: type)
            }
            self.error = "Failed to get insight: \(error.localizedDescription)"
            throw error
        }
    }

    /// Execute full HRM orchestration for a message
    func orchestrateCouncil(
        for message: ForumMessage,
        specialists: [CouncilAgentType] = CouncilAgentType.allCases
    ) async throws -> CouncilInsight {
        isProcessing = true
        error = nil
        streamingContent = [:]
        hrmStage = .routing

        defer {
            isProcessing = false
            hrmStage = nil
        }

        let provider = await selectActiveProvider()
        let context = createContext(for: [message])

        let request = HRMOrchestrationRequest(
            messageId: message.id,
            content: message.content,
            context: context,
            specialists: specialists,
            options: .default
        )

        do {
            let stream = try await provider.executeHRMOrchestration(request: request)

            var finalInsight: CouncilInsight?

            for try await delta in stream {
                processStreamDelta(delta)

                if case let .synthesisComplete(result) = delta {
                    finalInsight = result
                }
            }

            guard var insight = finalInsight else {
                throw CouncilError.orchestrationFailed("No synthesis produced")
            }

            // Encrypt if enabled
            if let encrypted = try? await encryptInsight(insight) {
                insight = encrypted
            }

            currentInsight = insight
            return insight

        } catch {
            // Fallback to local HRM on Edge failure
            if provider.providerType == .arkavoEdge {
                return try await runLocalHRMFallback(message: message, specialists: specialists)
            }
            self.error = "Orchestration failed: \(error.localizedDescription)"
            throw error
        }
    }

    /// Get summary of a conversation
    func summarizeConversation(_ messages: [ForumMessage]) async throws -> CouncilInsight {
        isProcessing = true
        error = nil

        defer {
            isProcessing = false
        }

        let provider = await selectActiveProvider()

        // Create conversation context
        let conversation = messages.map { message in
            "\(message.senderName): \(message.content)"
        }.joined(separator: "\n")

        let prompt = """
            Please summarize this conversation and highlight key points, agreements, and areas of discussion:

            \(conversation)

            Provide a concise summary with:
            1. Main topics discussed
            2. Key points made
            3. Areas of agreement or disagreement
            4. Suggested next steps
            """

        do {
            let response = try await provider.executeSpecialistQuery(
                role: .synthesizer,
                prompt: prompt,
                context: createContext(for: messages)
            )

            let insight = CouncilInsight(
                id: UUID().uuidString,
                messageId: "summary",
                agentType: .synthesizer,
                content: response,
                timestamp: Date()
            )

            currentInsight = insight
            return insight

        } catch {
            self.error = "Failed to summarize: \(error.localizedDescription)"
            throw error
        }
    }

    /// Research a topic based on conversation
    func researchTopic(_ topic: String, context: [ForumMessage]) async throws -> CouncilInsight {
        isProcessing = true
        error = nil

        defer {
            isProcessing = false
        }

        let provider = await selectActiveProvider()

        // Build context from messages
        let contextText = context.prefix(5).map { message in
            "\(message.senderName): \(message.content)"
        }.joined(separator: "\n")

        let prompt = """
            Research topic: \(topic)

            Recent conversation context:
            \(contextText)

            Please provide:
            1. Key concepts and definitions
            2. Different perspectives on this topic
            3. Relevant facts or data points
            4. Potential implications
            5. Questions to explore further
            """

        do {
            let response = try await provider.executeSpecialistQuery(
                role: .researcher,
                prompt: prompt,
                context: createContext(for: context)
            )

            let insight = CouncilInsight(
                id: UUID().uuidString,
                messageId: "research",
                agentType: .researcher,
                content: response,
                timestamp: Date()
            )

            currentInsight = insight
            return insight

        } catch {
            self.error = "Failed to research: \(error.localizedDescription)"
            throw error
        }
    }

    /// Clear all sessions (start fresh)
    func clearSessions() {
        Task {
            await localProvider.disconnect()
        }
        currentInsight = nil
        error = nil
        streamingContent = [:]
        hrmStage = nil
    }

    // MARK: - Provider Selection

    private func selectActiveProvider() async -> any CouncilConnectionProvider {
        // Prefer Edge if connected
        if edgeProvider.isConnected {
            activeProvider = edgeProvider
            connectionMode = .connectedToEdge
            return edgeProvider
        }

        // Fallback to local
        activeProvider = localProvider
        connectionMode = .fallbackToLocal
        return localProvider
    }

    private func fallbackToLocal() async {
        connectionMode = .fallbackToLocal
        activeProvider = localProvider
    }

    // MARK: - Fallback Methods

    private func fallbackGetInsight(message: ForumMessage, type: CouncilAgentType) async throws -> CouncilInsight {
        await fallbackToLocal()

        let prompt = createInsightPrompt(for: message, type: type)
        let context = createContext(for: [message])

        let response = try await localProvider.executeSpecialistQuery(
            role: type,
            prompt: prompt,
            context: context
        )

        return CouncilInsight(
            id: UUID().uuidString,
            messageId: message.id,
            agentType: type,
            content: response,
            timestamp: Date()
        )
    }

    private func runLocalHRMFallback(
        message: ForumMessage,
        specialists: [CouncilAgentType]
    ) async throws -> CouncilInsight {
        await fallbackToLocal()

        // Run each specialist sequentially
        var results: [CouncilAgentType: String] = [:]

        for specialist in specialists {
            hrmStage = .specialists
            streamingContent[specialist] = ""

            let insight = try await getInsight(for: message, type: specialist)
            results[specialist] = insight.content
            streamingContent[specialist] = insight.content
        }

        // Synthesize locally
        hrmStage = .synthesis
        let synthesisPrompt = createSynthesisPrompt(results: results, originalMessage: message)
        let context = createContext(for: [message])

        let synthesisResponse = try await localProvider.executeSpecialistQuery(
            role: .synthesizer,
            prompt: synthesisPrompt,
            context: context
        )

        return CouncilInsight(
            id: UUID().uuidString,
            messageId: message.id,
            agentType: .synthesizer,
            content: synthesisResponse,
            timestamp: Date()
        )
    }

    // MARK: - Stream Processing

    private func processStreamDelta(_ delta: HRMDelta) {
        switch delta {
        case let .conductorRouting(specialists):
            hrmStage = .routing
            for specialist in specialists {
                streamingContent[specialist] = ""
            }

        case let .specialistStart(role):
            hrmStage = .specialists
            if streamingContent[role] == nil {
                streamingContent[role] = ""
            }

        case let .specialistText(role, text):
            streamingContent[role, default: ""] += text

        case let .specialistComplete(role, result):
            streamingContent[role] = result

        case .criticReview:
            hrmStage = .critic

        case .synthesisStart:
            hrmStage = .synthesis

        case let .synthesisText(text):
            streamingContent[.synthesizer, default: ""] += text

        case .synthesisComplete:
            hrmStage = .complete

        case let .error(code, message):
            error = "HRM Error [\(code)]: \(message)"

        case .complete:
            hrmStage = .complete
        }
    }

    // MARK: - Encryption

    private func encryptInsight(_ insight: CouncilInsight) async throws -> CouncilInsight? {
        guard let encryptionManager, encryptionManager.encryptionEnabled else {
            return nil
        }

        guard let data = insight.content.data(using: .utf8) else {
            return nil
        }

        let encrypted = try await encryptionManager.encryptMessage(data, groupId: "council")

        return CouncilInsight(
            id: insight.id,
            messageId: insight.messageId,
            agentType: insight.agentType,
            content: encrypted.base64EncodedString(),
            timestamp: insight.timestamp,
            isEncrypted: true
        )
    }

    // MARK: - Observer Setup

    private func setupProviderObservers() {
        edgeProvider.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                if isConnected {
                    self?.connectionMode = .connectedToEdge
                    self?.activeProvider = self?.edgeProvider
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Prompt Creation

    private func createContext(for messages: [ForumMessage]) -> CouncilContext {
        let history = messages.map { ContextMessage(from: $0) }
        return CouncilContext(conversationHistory: history)
    }

    private func createInsightPrompt(for message: ForumMessage, type: CouncilAgentType) -> String {
        let baseContext = """
            Message from \(message.senderName):
            "\(message.content)"
            """

        switch type {
        case .analyst:
            return """
                \(baseContext)

                As a critical analyst, provide:
                1. Key assumptions in this message
                2. Potential biases or perspectives
                3. Questions to consider
                4. Alternative viewpoints
                """

        case .researcher:
            return """
                \(baseContext)

                As a researcher, provide:
                1. Relevant background information
                2. Supporting or contradicting evidence
                3. Related concepts to explore
                4. References or sources to check
                """

        case .synthesizer:
            return """
                \(baseContext)

                As a synthesizer, provide:
                1. How this connects to the broader discussion
                2. Key insights or patterns
                3. Integration with previous points
                4. Implications for the conversation
                """

        case .advocate:
            return """
                \(baseContext)

                As a devil's advocate, provide:
                1. Counterarguments to consider
                2. Potential weaknesses in the reasoning
                3. Alternative perspectives
                4. Challenges or questions to strengthen the idea
                """

        case .facilitator:
            return """
                \(baseContext)

                As a facilitator, provide:
                1. How to build on this idea
                2. Questions to deepen the discussion
                3. Ways to engage other perspectives
                4. Suggestions for moving forward
                """
        }
    }

    private func createSynthesisPrompt(results: [CouncilAgentType: String], originalMessage: ForumMessage) -> String {
        var specialistContributions = ""

        for (role, content) in results.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            specialistContributions += """

                **\(role.rawValue)**:
                \(content)

                """
        }

        return """
            Original message from \(originalMessage.senderName): \(originalMessage.content)

            The AI Council has analyzed this from multiple perspectives:
            \(specialistContributions)

            As the council synthesizer, create a unified response that:
            1. Integrates key insights from each perspective
            2. Highlights areas of agreement and productive tension
            3. Provides a balanced, actionable conclusion
            4. Notes any remaining questions worth exploring

            Provide a coherent synthesis that honors all perspectives.
            """
    }
}

// MARK: - Models

/// Types of AI Council agents with different perspectives
enum CouncilAgentType: String, CaseIterable, Identifiable {
    case analyst = "Critical Analyst"
    case researcher = "Researcher"
    case synthesizer = "Synthesizer"
    case advocate = "Devil's Advocate"
    case facilitator = "Facilitator"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .analyst: return "chart.bar"
        case .researcher: return "book"
        case .synthesizer: return "diagram.connected"
        case .advocate: return "exclamationmark.triangle"
        case .facilitator: return "person.2"
        }
    }

    var color: Color {
        switch self {
        case .analyst: return .blue
        case .researcher: return .purple
        case .synthesizer: return .green
        case .advocate: return .orange
        case .facilitator: return .cyan
        }
    }

    var description: String {
        switch self {
        case .analyst:
            return "Analyzes assumptions, biases, and perspectives"
        case .researcher:
            return "Provides background, evidence, and references"
        case .synthesizer:
            return "Connects ideas and identifies patterns"
        case .advocate:
            return "Challenges ideas and explores counterarguments"
        case .facilitator:
            return "Guides discussion and suggests next steps"
        }
    }
}

/// AI-generated insight for a message or conversation
struct CouncilInsight: Identifiable {
    let id: String
    let messageId: String
    let agentType: CouncilAgentType
    let content: String
    let timestamp: Date
    var isEncrypted: Bool = false
}

/// AI Council request state
enum CouncilRequestState {
    case idle
    case processing
    case completed(CouncilInsight)
    case error(String)
}
