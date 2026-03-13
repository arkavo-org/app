//
//  LLMProvider.swift
//  Muse
//
//  Protocol and implementations for LLM response providers.
//  Enables fallback chain and testability via dependency injection.
//

import Foundation
import OSLog

// MARK: - LLM Provider Protocol

/// Protocol for LLM response providers.
/// Implementations must be thread-safe (Sendable) for use in async contexts.
public protocol LLMResponseProvider: Sendable {
    /// Check if this provider is available for generation
    var isAvailable: Bool { get async }

    /// Human-readable name for logging
    var providerName: String { get }

    /// Priority for fallback ordering (lower = higher priority)
    var priority: Int { get }

    /// Generate a constrained response
    /// - Parameter prompt: The input prompt
    /// - Returns: Parsed ConstrainedResponse
    func generate(prompt: String) async throws -> ConstrainedResponse
}

// MARK: - Provider Errors

public enum LLMProviderError: LocalizedError {
    case notAvailable(provider: String)
    case allProvidersFailed
    case noProvidersConfigured
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notAvailable(let provider):
            return "\(provider) is not available"
        case .allProvidersFailed:
            return "All LLM providers failed"
        case .noProvidersConfigured:
            return "No LLM providers configured"
        case .timeout:
            return "LLM generation timed out"
        }
    }
}

// MARK: - Mock Provider (for testing)

/// Mock provider for unit testing
public final class MockLLMProvider: LLMResponseProvider, @unchecked Sendable {
    public var mockIsAvailable: Bool = true
    public var mockResponse: ConstrainedResponse = ConstrainedResponse(message: "Mock response")
    public var mockError: Error?
    public var generateCallCount: Int = 0
    public var lastPrompt: String?

    public init() {}

    public var isAvailable: Bool {
        get async { mockIsAvailable }
    }

    public var providerName: String { "Mock" }

    public var priority: Int { 99 }

    public func generate(prompt: String) async throws -> ConstrainedResponse {
        generateCallCount += 1
        lastPrompt = prompt

        if let error = mockError {
            throw error
        }

        return mockResponse
    }
}

#if DEBUG
/// Configurable mock provider for testing fallback chain routing logic.
/// Unlike MockLLMProvider, this allows customizing providerName and priority.
public final class ConfigurableMockLLMProvider: LLMResponseProvider, @unchecked Sendable {
    public var mockIsAvailable: Bool = true
    public var mockResponse: ConstrainedResponse = ConstrainedResponse(message: "Mock response")
    public var mockError: Error?
    public var generateCallCount: Int = 0
    public var lastPrompt: String?
    private let _providerName: String
    private let _priority: Int

    public init(name: String, priority: Int) {
        self._providerName = name
        self._priority = priority
    }

    public var isAvailable: Bool {
        get async { mockIsAvailable }
    }

    public var providerName: String { _providerName }

    public var priority: Int { _priority }

    public func generate(prompt: String) async throws -> ConstrainedResponse {
        generateCallCount += 1
        lastPrompt = prompt

        if let error = mockError {
            throw error
        }

        return mockResponse
    }
}
#endif
