//
//  EdgeLLMProvider.swift
//  ArkavoCreator
//
//  LLM provider that uses CreatorAgentService (arkavo-edge) as the backend.
//  Conforms to MuseCore's LLMResponseProvider for integration with the
//  procedural animation and conversation systems.
//

import Foundation
import MuseCore
import OSLog

/// LLM provider that routes generation requests through CreatorAgentService
/// to connected arkavo-edge agents.
@MainActor
final class EdgeLLMProvider: LLMResponseProvider, @unchecked Sendable {
    // MARK: - Properties

    private let agentService: CreatorAgentService
    private let logger = Logger(subsystem: "com.arkavo.creator", category: "EdgeLLM")

    /// The agent ID to use for generation
    private var targetAgentID: String?

    /// Active chat session ID
    private var sessionID: String?

    // MARK: - LLMResponseProvider

    let providerName: String = "Arkavo Edge"
    let priority: Int = 0  // Highest priority — cloud models

    var isAvailable: Bool {
        get async {
            guard let agentID = targetAgentID else { return false }
            return agentService.isConnected(to: agentID)
        }
    }

    // MARK: - Initialization

    init(agentService: CreatorAgentService) {
        self.agentService = agentService
    }

    // MARK: - Configuration

    /// Set the target agent to use for generation
    func setTargetAgent(_ agentID: String) {
        self.targetAgentID = agentID
        self.sessionID = nil  // Reset session for new agent
    }

    /// Connect to the first available agent
    func connectToFirstAvailable() async throws {
        let agents = agentService.discoveredAgents
        guard let agent = agents.first else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        try await agentService.connect(to: agent)
        targetAgentID = agent.id
    }

    // MARK: - LLMResponseProvider

    func generate(prompt: String) async throws -> ConstrainedResponse {
        guard let agentID = targetAgentID,
              agentService.isConnected(to: agentID)
        else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        // Ensure we have a chat session
        if sessionID == nil {
            let session = try await agentService.openChatSession(with: agentID)
            sessionID = session.id
        }

        guard let sessionID = sessionID else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        // Send the prompt
        try await agentService.sendMessage(sessionId: sessionID, content: prompt)

        // Wait for streaming to complete
        let responseText = try await waitForResponse(sessionID: sessionID)

        logger.debug("Edge response: \(responseText.prefix(100))")

        // Parse as ConstrainedResponse
        // Try JSON parsing first, fall back to plain text
        if let data = responseText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ConstrainedResponse.self, from: data)
        {
            return decoded
        }

        return ConstrainedResponse(message: responseText)
    }

    // MARK: - Private

    private func waitForResponse(sessionID: String) async throws -> String {
        // Poll for streaming completion with timeout
        let timeout: TimeInterval = 30
        let start = Date()

        while Date().timeIntervalSince(start) < timeout {
            if !agentService.isStreaming(sessionId: sessionID) {
                // Streaming finished — get the accumulated text
                if let text = agentService.finalizeStream(sessionId: sessionID), !text.isEmpty {
                    return text
                }
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        throw LLMProviderError.timeout
    }
}
