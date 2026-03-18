import Foundation

/// Protocol for streaming LLM providers that return raw token streams.
/// Unlike `LLMResponseProvider` which returns structured `ConstrainedResponse`,
/// this protocol is designed for content creation tasks needing raw text output.
public protocol StreamingLLMProvider: Sendable {
    /// Whether the provider is ready to generate
    var isAvailable: Bool { get async }

    /// Human-readable provider name
    var providerName: String { get }

    /// Generate a streaming response
    /// - Parameters:
    ///   - prompt: The user prompt
    ///   - systemPrompt: System instructions for the model
    ///   - maxTokens: Maximum tokens to generate
    /// - Returns: An async stream of token strings
    func generate(prompt: String, systemPrompt: String, maxTokens: Int) -> AsyncThrowingStream<String, Error>

    /// Cancel any in-progress generation
    func cancelGeneration() async
}

/// Errors specific to streaming LLM operations
public enum StreamingLLMError: Error, LocalizedError {
    case modelNotLoaded
    case generationCancelled
    case modelLoadFailed(String)
    case insufficientMemory(required: Int, available: Int)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            "No model is currently loaded"
        case .generationCancelled:
            "Generation was cancelled"
        case .modelLoadFailed(let reason):
            "Failed to load model: \(reason)"
        case .insufficientMemory(let required, let available):
            "Insufficient memory: need \(required)MB, have \(available)MB"
        case .downloadFailed(let reason):
            "Download failed: \(reason)"
        }
    }
}
