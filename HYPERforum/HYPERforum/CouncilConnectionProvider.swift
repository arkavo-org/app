import Foundation

// MARK: - Provider Types

/// Type of council provider backend
enum CouncilProviderType: String, Sendable {
    case arkavoEdge
    case localAgent
}

/// Connection mode for the council
enum CouncilConnectionMode: Equatable, Sendable {
    case discovering
    case connectedToEdge
    case fallbackToLocal
    case disconnected
}

// MARK: - Provider Protocol

/// Protocol for council AI providers (Edge or Local)
@MainActor
protocol CouncilConnectionProvider: AnyObject {
    /// Whether the provider is currently connected
    var isConnected: Bool { get }

    /// The type of this provider
    var providerType: CouncilProviderType { get }

    /// Connect to the provider
    func connect() async throws

    /// Disconnect from the provider
    func disconnect() async

    /// Execute a single specialist query
    /// - Parameters:
    ///   - role: The council agent role to query
    ///   - prompt: The prompt to send
    ///   - context: Conversation context
    /// - Returns: The specialist's response
    func executeSpecialistQuery(
        role: CouncilAgentType,
        prompt: String,
        context: CouncilContext
    ) async throws -> String

    /// Execute full HRM orchestration with streaming
    /// - Parameter request: The orchestration request
    /// - Returns: An async stream of HRM deltas
    func executeHRMOrchestration(
        request: HRMOrchestrationRequest
    ) async throws -> AsyncThrowingStream<HRMDelta, Error>
}

// MARK: - Provider Delegate

/// Delegate for provider connection status changes
@MainActor
protocol CouncilConnectionDelegate: AnyObject {
    /// Called when connection status changes
    func providerDidChangeStatus(_ provider: any CouncilConnectionProvider, status: CouncilConnectionMode)

    /// Called when an error occurs
    func providerDidEncounterError(_ provider: any CouncilConnectionProvider, error: Error)
}

// MARK: - Default Implementations

extension CouncilConnectionProvider {
    /// Default empty context
    func executeSpecialistQuery(role: CouncilAgentType, prompt: String) async throws -> String {
        try await executeSpecialistQuery(role: role, prompt: prompt, context: .empty)
    }
}
