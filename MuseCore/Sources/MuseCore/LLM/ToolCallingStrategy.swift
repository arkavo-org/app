import Foundation
import OSLog

// MARK: - Tool Calling Strategy Protocol

/// Protocol for abstracting different tool calling approaches
/// Enables A/B comparison between fence-based and constrained decoding
public protocol ToolCallingStrategy: Sendable {
    /// Human-readable name for the strategy
    var name: String { get }

    /// Build the prompt with tool instructions for the LLM
    /// - Parameters:
    ///   - userMessage: The user's input message
    ///   - tools: Available tool definitions
    /// - Returns: Complete prompt string
    func buildPrompt(userMessage: String, tools: [FenceToolDefinition]) -> String

    /// Parse the LLM response to extract tool calls
    /// - Parameter response: Raw LLM output
    /// - Returns: Array of parsed tool calls (empty if none)
    func parseResponse(_ response: String) -> [ParsedToolCall]

    /// Whether this strategy uses constrained generation
    var usesConstrainedGeneration: Bool { get }
}

// MARK: - Fence-Based Strategy

/// Strategy using markdown code fences for tool calls
/// Compatible with any text-generating model
public struct FenceBasedStrategy: ToolCallingStrategy {
    public let name = "Fence-Based"
    public let usesConstrainedGeneration = false

    /// Whether to use enhanced prompts (recommended for small models)
    public let useEnhancedPrompts: Bool

    public init(useEnhancedPrompts: Bool = true) {
        self.useEnhancedPrompts = useEnhancedPrompts
    }

    public func buildPrompt(userMessage: String, tools: [FenceToolDefinition]) -> String {
        var prompt = ""

        // Add tool documentation
        if useEnhancedPrompts {
            prompt += FencePromptGenerator.generateEnhanced(tools: tools)
        } else {
            prompt += FencePromptGenerator.generate(tools: tools)
        }

        // Add user message
        prompt += "\n\nUser: \(userMessage)\nAssistant:"

        return prompt
    }

    public func parseResponse(_ response: String) -> [ParsedToolCall] {
        return FenceParser.parse(response)
    }
}

// MARK: - Constrained Decoding Strategy

/// Strategy using JSON schema + grammar for guaranteed valid output
/// Requires mlx-swift-structured library
public struct ConstrainedDecodingStrategy: ToolCallingStrategy {
    public let name = "Constrained-Decoding"
    public let usesConstrainedGeneration = true

    public init() {}

    public func buildPrompt(userMessage: String, tools: [FenceToolDefinition]) -> String {
        // Simpler prompt since output format is enforced by grammar
        let toolNames = tools.map { $0.name }.joined(separator: ", ")

        return """
        You are a helpful assistant with access to tools: \(toolNames)

        Respond with JSON format:
        {"message": "your spoken response", "toolCall": null or {"type": "toolName", ...params}}

        Only use tools when explicitly asked. For regular conversation, set toolCall to null.

        User: \(userMessage)
        """
    }

    public func parseResponse(_ response: String) -> [ParsedToolCall] {
        // Response should already be valid JSON from constrained generation
        guard let data = response.data(using: .utf8) else {
            return []
        }

        do {
            let decoded = try JSONDecoder().decode(ConstrainedResponse.self, from: data)
            if let toolCall = decoded.toolCall {
                return [toolCall.toParsedToolCall()]
            }
            return []
        } catch {
            // Fallback to fence parsing if JSON decode fails
            return FenceParser.parse(response)
        }
    }
}

// MARK: - Hybrid Strategy

/// Strategy that uses heuristics to choose between approaches
/// Fast fence-based for simple cases, constrained for complex
public struct HybridStrategy: ToolCallingStrategy {
    public let name = "Hybrid"
    public let usesConstrainedGeneration = true

    private let fenceStrategy = FenceBasedStrategy()
    private let constrainedStrategy = ConstrainedDecodingStrategy()

    /// Complexity threshold for switching to constrained decoding
    public let complexityThreshold: Int

    public init(complexityThreshold: Int = 3) {
        self.complexityThreshold = complexityThreshold
    }

    public func buildPrompt(userMessage: String, tools: [FenceToolDefinition]) -> String {
        // Use heuristic to determine complexity
        if shouldUseConstrained(userMessage: userMessage, tools: tools) {
            return constrainedStrategy.buildPrompt(userMessage: userMessage, tools: tools)
        } else {
            return fenceStrategy.buildPrompt(userMessage: userMessage, tools: tools)
        }
    }

    public func parseResponse(_ response: String) -> [ParsedToolCall] {
        // Try JSON first (constrained output)
        if let data = response.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ConstrainedResponse.self, from: data),
           let toolCall = decoded.toolCall {
            return [toolCall.toParsedToolCall()]
        }

        // Fall back to fence parsing
        return fenceStrategy.parseResponse(response)
    }

    private func shouldUseConstrained(userMessage: String, tools: [FenceToolDefinition]) -> Bool {
        // Use constrained for:
        // 1. Multiple potential tools mentioned
        // 2. Complex parameter requirements
        // 3. Ambiguous requests

        let lowered = userMessage.lowercased()

        // Check for multiple tool triggers
        var triggerCount = 0
        if lowered.contains("wave") || lowered.contains("dance") || lowered.contains("animation") {
            triggerCount += 1
        }
        if lowered.contains("look") || lowered.contains("expression") || lowered.contains("face") {
            triggerCount += 1
        }
        if lowered.contains("time") {
            triggerCount += 1
        }
        if lowered.contains("date") {
            triggerCount += 1
        }

        return triggerCount >= complexityThreshold
    }
}

// MARK: - Strategy Factory

/// Factory for creating tool calling strategies
public enum ToolCallingStrategyFactory {

    /// Create the default strategy based on available capabilities
    public static func defaultStrategy() -> ToolCallingStrategy {
        #if canImport(MLXStructured)
        // Prefer constrained decoding when available
        return ConstrainedDecodingStrategy()
        #else
        // Fall back to fence-based
        return FenceBasedStrategy(useEnhancedPrompts: true)
        #endif
    }

    /// Create a specific strategy by name
    public static func strategy(named name: String) -> ToolCallingStrategy? {
        switch name.lowercased() {
        case "fence", "fence-based":
            return FenceBasedStrategy()
        case "constrained", "constrained-decoding":
            return ConstrainedDecodingStrategy()
        case "hybrid":
            return HybridStrategy()
        default:
            return nil
        }
    }

    /// Get all available strategies for comparison
    public static func allStrategies() -> [ToolCallingStrategy] {
        return [
            FenceBasedStrategy(useEnhancedPrompts: true),
            ConstrainedDecodingStrategy(),
            HybridStrategy()
        ]
    }
}

// MARK: - Comparison Metrics

/// Metrics collected during tool calling evaluation
public struct ToolCallingMetrics: Sendable {
    public let successRate: Double           // Correct tool + params
    public let formatAdherence: Double       // Valid syntax produced
    public let parameterAccuracy: Double     // Correct param values
    public let falsePositiveRate: Double     // Tool when shouldn't
    public let falseNegativeRate: Double     // No tool when should
    public let meanLatencyMs: Double         // Average generation time
    public let p95LatencyMs: Double          // 95th percentile latency
    public let tokensPerSecond: Double       // Generation throughput
    public let avgConfidence: Double         // Average confidence score

    public init(
        successRate: Double,
        formatAdherence: Double,
        parameterAccuracy: Double,
        falsePositiveRate: Double,
        falseNegativeRate: Double,
        meanLatencyMs: Double,
        p95LatencyMs: Double,
        tokensPerSecond: Double,
        avgConfidence: Double
    ) {
        self.successRate = successRate
        self.formatAdherence = formatAdherence
        self.parameterAccuracy = parameterAccuracy
        self.falsePositiveRate = falsePositiveRate
        self.falseNegativeRate = falseNegativeRate
        self.meanLatencyMs = meanLatencyMs
        self.p95LatencyMs = p95LatencyMs
        self.tokensPerSecond = tokensPerSecond
        self.avgConfidence = avgConfidence
    }

    /// Calculate overall score (0-10 scale)
    public var overallScore: Double {
        let weights: [(Double, Double)] = [
            (0.40, successRate),
            (0.25, formatAdherence),
            (0.25, parameterAccuracy),
            (0.10, 1.0 - min(meanLatencyMs / 5000.0, 1.0))  // Latency penalty (5s = 0)
        ]

        let score = weights.reduce(0.0) { $0 + $1.0 * $1.1 }
        return score * 10.0
    }
}

// MARK: - Comparison Report

/// Report comparing multiple strategies
public struct StrategyComparisonReport: Sendable {
    public let strategies: [String]
    public let metrics: [String: ToolCallingMetrics]
    public let testCount: Int
    public let timestamp: Date
    public let recommendation: String

    public init(
        strategies: [String],
        metrics: [String: ToolCallingMetrics],
        testCount: Int,
        timestamp: Date = Date()
    ) {
        self.strategies = strategies
        self.metrics = metrics
        self.testCount = testCount
        self.timestamp = timestamp

        // Generate recommendation based on metrics
        if let bestStrategy = metrics.max(by: { $0.value.overallScore < $1.value.overallScore }) {
            self.recommendation = bestStrategy.key
        } else {
            self.recommendation = "Fence-Based"
        }
    }

    /// Print formatted comparison report
    public func printReport() {
        print("\n" + String(repeating: "=", count: 70))
        print("TOOL CALLING STRATEGY COMPARISON REPORT")
        print(String(repeating: "=", count: 70))
        print("Timestamp: \(timestamp)")
        print("Test cases: \(testCount)")
        print("")

        // Header
        print(String(format: "%-25s %10s %10s %10s %10s",
                     "Strategy", "Score", "Success", "Format", "Latency"))
        print(String(repeating: "-", count: 70))

        // Each strategy
        for strategy in strategies {
            if let m = metrics[strategy] {
                print(String(format: "%-25s %10.1f %9.1f%% %9.1f%% %8.0fms",
                             strategy,
                             m.overallScore,
                             m.successRate * 100,
                             m.formatAdherence * 100,
                             m.meanLatencyMs))
            }
        }

        print(String(repeating: "-", count: 70))
        print("")
        print("RECOMMENDATION: \(recommendation)")

        // Detailed breakdown
        print("")
        print("Detailed Metrics:")
        for strategy in strategies {
            if let m = metrics[strategy] {
                print("")
                print("  \(strategy):")
                print(String(format: "    Overall Score:      %.1f/10", m.overallScore))
                print(String(format: "    Success Rate:       %.1f%%", m.successRate * 100))
                print(String(format: "    Format Adherence:   %.1f%%", m.formatAdherence * 100))
                print(String(format: "    Parameter Accuracy: %.1f%%", m.parameterAccuracy * 100))
                print(String(format: "    False Positive:     %.1f%%", m.falsePositiveRate * 100))
                print(String(format: "    False Negative:     %.1f%%", m.falseNegativeRate * 100))
                print(String(format: "    Mean Latency:       %.0fms", m.meanLatencyMs))
                print(String(format: "    P95 Latency:        %.0fms", m.p95LatencyMs))
                print(String(format: "    Tokens/sec:         %.1f", m.tokensPerSecond))
                print(String(format: "    Avg Confidence:     %.2f", m.avgConfidence))
            }
        }

        print(String(repeating: "=", count: 70))
    }
}
