//
//  LLMFallbackChain.swift
//  Muse
//
//  Manages fallback between multiple LLM providers.
//  Tries providers in priority order, gracefully degrades on failures.
//

import Foundation
import OSLog

// MARK: - LLM Fallback Chain

/// Manages a chain of LLM providers with fallback logic.
/// Tries providers in priority order (lowest priority number first).
public final class LLMFallbackChain: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.arkavo.muse", category: "LLMFallbackChain")

    /// Registered providers (sorted by priority)
    private var providers: [any LLMResponseProvider] = []

    /// Lock for thread-safe provider access.
    /// SAFETY: Only use lock.withLock for synchronous snapshots. Never await inside withLock
    /// as NSLock does not support suspension points. All async work must be done outside the lock.
    private let lock = NSLock()

    public init() {}

    // MARK: - Provider Management

    /// Add a provider to the chain
    /// Providers are automatically sorted by priority
    public func addProvider(_ provider: any LLMResponseProvider) {
        lock.lock()
        defer { lock.unlock() }

        providers.append(provider)
        providers.sort { $0.priority < $1.priority }

        logger.info("Added provider: \(provider.providerName) (priority \(provider.priority))")
    }

    /// Remove all providers
    public func clearProviders() {
        lock.lock()
        defer { lock.unlock() }
        providers.removeAll()
    }

    /// Check if any provider is available
    public var hasAvailableProvider: Bool {
        get async {
            let currentProviders = lock.withLock { providers }
            for provider in currentProviders {
                if await provider.isAvailable {
                    return true
                }
            }
            return false
        }
    }

    // MARK: - Generation

    /// Generate a response using the first available provider
    /// Falls back to subsequent providers on failure
    /// - Parameter prompt: The input prompt
    /// - Returns: Tuple of (response, provider name that succeeded)
    public func generate(prompt: String) async throws -> (response: ConstrainedResponse, provider: String) {
        // Use default intent classification
        let intent = IntentClassifier.classify(prompt)
        return try await generate(prompt: prompt, intent: intent)
    }

    /// Generate a response with intent-aware routing
    /// Routes quick chat to fast providers, complex tasks to capable providers
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - intent: The classified user intent
    ///   - locale: Optional voice locale for language-specific routing
    /// - Returns: Tuple of (response, provider name that succeeded)
    public func generate(prompt: String, intent: UserIntent, locale: VoiceLocale? = nil) async throws -> (response: ConstrainedResponse, provider: String) {
        let currentProviders = lock.withLock { providers }

        guard !currentProviders.isEmpty else {
            logger.error("No providers configured")
            throw LLMProviderError.noProvidersConfigured
        }

        // For Japanese, always use Apple Intelligence (Gemma-3 is English-only)
        if locale?.isJapanese == true {
            logger.info("Japanese locale detected → forcing Apple Intelligence")
            if let appleProvider = currentProviders.first(where: { $0.providerName == "Apple Intelligence" }) {
                if await appleProvider.isAvailable {
                    do {
                        let response = try await appleProvider.generate(prompt: prompt)
                        logger.info("Japanese generation succeeded with AppleIntelligence")
                        return (response, appleProvider.providerName)
                    } catch {
                        logger.warning("Apple Intelligence failed for Japanese: \(error.localizedDescription)")
                        throw error
                    }
                } else {
                    logger.error("Apple Intelligence not available for Japanese locale")
                    throw LLMProviderError.noProvidersConfigured
                }
            }
            throw LLMProviderError.noProvidersConfigured
        }

        // Reorder providers based on intent (for English)
        let orderedProviders = reorderProviders(currentProviders, for: intent)
        logger.info("Intent: \(String(describing: intent)) → Provider order: \(orderedProviders.map { $0.providerName }.joined(separator: " → "))")

        var lastError: Error?

        for provider in orderedProviders {
            // Check availability
            guard await provider.isAvailable else {
                logger.debug("\(provider.providerName) not available, skipping")
                continue
            }

            do {
                logger.info("Attempting generation with \(provider.providerName)")
                let response = try await provider.generate(prompt: prompt)
                logger.info("Generation succeeded with \(provider.providerName)")
                return (response, provider.providerName)
            } catch {
                logger.warning("\(provider.providerName) failed: \(error.localizedDescription)")
                lastError = error
                // Continue to next provider
            }
        }

        // All providers failed
        logger.error("All providers failed")
        throw lastError ?? LLMProviderError.allProvidersFailed
    }

    /// Reorder providers based on intent
    /// - Parameters:
    ///   - providers: Current providers list
    ///   - intent: The user intent
    /// - Returns: Reordered provider list optimized for the intent
    private func reorderProviders(_ providers: [any LLMResponseProvider], for intent: UserIntent) -> [any LLMResponseProvider] {
        switch intent {
        case .toolRequired:
            // Gemma excels at short tool-call prompts with constrained output
            return providers.sorted { $0.priority > $1.priority }
        case .quickChat, .greeting, .complexReasoning:
            // Apple Intelligence is more capable for conversation
            return providers.sorted { $0.priority < $1.priority }
        }
    }

    // MARK: - Graceful Degradation

    /// Default fallback response when all providers fail
    public static var gracefulDegradationResponse: ConstrainedResponse {
        ConstrainedResponse(
            message: "I'm having trouble thinking right now. Give me a moment.",
            toolCall: nil
        )
    }

    /// Generate with graceful degradation - never throws
    /// Returns fallback response if all providers fail
    public func generateWithFallback(prompt: String) async -> (response: ConstrainedResponse, provider: String) {
        do {
            return try await generate(prompt: prompt)
        } catch {
            logger.warning("All providers failed, using graceful degradation")
            return (Self.gracefulDegradationResponse, "Fallback")
        }
    }
}
