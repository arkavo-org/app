import ArkavoAgent
import Foundation

/// Fallback provider using LocalAIAgent for on-device AI
@MainActor
final class LocalAICouncilProvider: ObservableObject, CouncilConnectionProvider {
    // MARK: - Properties

    var isConnected: Bool { true } // Always available
    let providerType: CouncilProviderType = .localAgent

    private let localAgent = LocalAIAgent.shared
    private var sessions: [CouncilAgentType: String] = [:]

    // MARK: - Initialization

    init() {}

    // MARK: - Connection Management

    func connect() async throws {
        // No-op: LocalAIAgent is always available
    }

    func disconnect() async {
        // Close all sessions
        for (_, sessionId) in sessions {
            localAgent.closeDirectChatSession(sessionId: sessionId)
        }
        sessions.removeAll()
    }

    // MARK: - Specialist Query

    func executeSpecialistQuery(
        role: CouncilAgentType,
        prompt: String,
        context _: CouncilContext
    ) async throws -> String {
        let sessionId = getOrCreateSession(for: role)
        return try await localAgent.sendDirectMessage(sessionId: sessionId, content: prompt)
    }

    // MARK: - HRM Orchestration (Simulated)

    func executeHRMOrchestration(
        request: HRMOrchestrationRequest
    ) async throws -> AsyncThrowingStream<HRMDelta, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    // Parse specialists from request
                    let specialists = request.specialists.compactMap { CouncilAgentType(rawValue: $0) }

                    // Stage 1: Routing (simulated)
                    continuation.yield(.conductorRouting(specialists: specialists))

                    // Stage 2: Execute specialists sequentially
                    var results: [CouncilAgentType: String] = [:]

                    for specialist in specialists {
                        continuation.yield(.specialistStart(role: specialist))

                        let prompt = self.createPromptForSpecialist(
                            role: specialist,
                            content: request.content,
                            context: request.context
                        )

                        let response = try await self.executeSpecialistQuery(
                            role: specialist,
                            prompt: prompt,
                            context: request.context
                        )

                        results[specialist] = response
                        continuation.yield(.specialistComplete(role: specialist, result: response))
                    }

                    // Stage 3: Critic (simulated - always approves in local mode)
                    if request.options.enableCritic {
                        continuation.yield(.criticReview(feedback: "Local validation passed", approved: true))
                    }

                    // Stage 4: Synthesis
                    if request.options.enableSynthesis {
                        continuation.yield(.synthesisStart)

                        let synthesisPrompt = self.createSynthesisPrompt(
                            results: results,
                            originalContent: request.content
                        )

                        let synthesisResponse = try await self.executeSpecialistQuery(
                            role: .synthesizer,
                            prompt: synthesisPrompt,
                            context: request.context
                        )

                        let insight = CouncilInsight(
                            id: UUID().uuidString,
                            messageId: request.messageId,
                            agentType: .synthesizer,
                            content: synthesisResponse,
                            timestamp: Date()
                        )

                        continuation.yield(.synthesisComplete(result: insight))
                    }

                    continuation.yield(.complete)
                    continuation.finish()

                } catch {
                    continuation.yield(.error(code: -1, message: error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func getOrCreateSession(for role: CouncilAgentType) -> String {
        if let existingSession = sessions[role] {
            return existingSession
        }

        let sessionId = localAgent.openDirectChatSession()
        sessions[role] = sessionId
        return sessionId
    }

    private func createPromptForSpecialist(
        role: CouncilAgentType,
        content: String,
        context: CouncilContext
    ) -> String {
        let contextText = context.conversationHistory
            .map { "\($0.senderName ?? "User"): \($0.content)" }
            .joined(separator: "\n")

        let baseContext = contextText.isEmpty ? content : """
            Recent conversation:
            \(contextText)

            Current message:
            \(content)
            """

        switch role {
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

    private func createSynthesisPrompt(
        results: [CouncilAgentType: String],
        originalContent: String
    ) -> String {
        var specialistContributions = ""

        for (role, content) in results.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            specialistContributions += """

                **\(role.rawValue)**:
                \(content)

                """
        }

        return """
            Original message: \(originalContent)

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
