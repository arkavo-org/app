import ArkavoAgent
import Foundation
import SwiftUI

/// Manages AI Council interactions for augmented discourse
@MainActor
class AICouncilManager: ObservableObject {
    @Published var isProcessing = false
    @Published var currentInsight: CouncilInsight?
    @Published var error: String?
    @Published var availableAgents: [CouncilAgentType] = CouncilAgentType.allCases

    private let localAgent = LocalAIAgent.shared
    private var activeSessions: [String: String] = [:] // agentType -> sessionId

    // MARK: - Public Methods

    /// Get AI insight for a specific message
    func getInsight(for message: ForumMessage, type: CouncilAgentType = .analyst) async throws -> CouncilInsight {
        isProcessing = true
        error = nil

        defer {
            isProcessing = false
        }

        do {
            // Get or create session for this agent type
            let sessionId = getOrCreateSession(for: type)

            // Create context-aware prompt
            let prompt = createInsightPrompt(for: message, type: type)

            // Get response from local AI agent
            let response = try await localAgent.sendDirectMessage(sessionId: sessionId, content: prompt)

            // Create insight
            let insight = CouncilInsight(
                id: UUID().uuidString,
                messageId: message.id,
                agentType: type,
                content: response,
                timestamp: Date()
            )

            currentInsight = insight
            return insight
        } catch {
            self.error = "Failed to get insight: \(error.localizedDescription)"
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

        do {
            let sessionId = getOrCreateSession(for: .synthesizer)

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

            let response = try await localAgent.sendDirectMessage(sessionId: sessionId, content: prompt)

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

        do {
            let sessionId = getOrCreateSession(for: .researcher)

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

            let response = try await localAgent.sendDirectMessage(sessionId: sessionId, content: prompt)

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
        activeSessions.removeAll()
        currentInsight = nil
        error = nil
    }

    // MARK: - Private Methods

    private func getOrCreateSession(for type: CouncilAgentType) -> String {
        if let existingSession = activeSessions[type.rawValue] {
            return existingSession
        }

        let sessionId = localAgent.openDirectChatSession()
        activeSessions[type.rawValue] = sessionId
        return sessionId
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
}

/// AI Council request state
enum CouncilRequestState {
    case idle
    case processing
    case completed(CouncilInsight)
    case error(String)
}
