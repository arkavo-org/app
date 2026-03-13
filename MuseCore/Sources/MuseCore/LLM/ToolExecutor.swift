import Foundation
import OSLog
import VRMMetalKit

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Tool Executor

/// Executes tool calls from either Apple Intelligence (@Generable) or fence-parsed format
@MainActor
public final class ToolExecutor {

    private let logger = Logger(subsystem: "com.arkavo.muse", category: "ToolExecutor")

    /// Context for tool execution (provides avatar control)
    public weak var context: ToolContext?

    /// Context text for sentiment-based fallback (user prompt or response text)
    public var sentimentContext: String?

    public init() {}

    // MARK: - Apple Intelligence Tool Execution

    /// Execute a tool call from Apple Intelligence structured output
    @available(iOS 26.0, macOS 26.0, *)
    public func execute(_ toolCall: ToolCall) async -> ToolResult {
        logger.info("Executing tool call: \(String(describing: toolCall))")

        switch toolCall {
        case .playAnimation(let tool):
            return executePlayAnimation(animation: tool.animation, loop: tool.loop)

        case .setExpression(let tool):
            return executeSetExpression(expression: tool.expression, intensity: tool.intensity)

        case .getTime(let tool):
            return executeGetTime(timezone: tool.timezone)

        case .getDate(let tool):
            return executeGetDate(format: tool.format)
        }
    }

    // MARK: - Fence-Parsed Tool Execution

    /// Execute a tool call parsed from fence format (Gemma-3)
    public func execute(_ parsed: ParsedToolCall) async -> ToolResult {
        logger.info("Executing fence-parsed tool: \(parsed.name)")

        switch parsed.name {
        case "play_animation":
            let animation = parsed.getString("animation") ?? "idle"
            let loop = parsed.getBool("loop") ?? false
            return executePlayAnimation(animation: animation, loop: loop)

        case "set_expression":
            let expression = parsed.getString("expression") ?? "neutral"
            let intensity = parsed.getFloat("intensity") ?? 0.8
            return executeSetExpression(expression: expression, intensity: intensity)

        case "get_time":
            let timezone = parsed.getString("timezone") ?? ""
            return executeGetTime(timezone: timezone)

        case "get_date":
            let format = parsed.getString("format") ?? "long"
            return executeGetDate(format: format)

        default:
            logger.warning("Unknown tool: \(parsed.name)")
            return .failure("Unknown tool: \(parsed.name)")
        }
    }

    // MARK: - Tool Implementations

    private func executePlayAnimation(animation: String, loop: Bool) -> ToolResult {
        guard let context = context else {
            logger.error("No context available for playAnimation")
            return .failure("Avatar context not available")
        }

        // Map animation name to emote or use sentiment analysis
        var resolvedAnimation = animation

        // If animation is a known emote name, use it directly
        // Otherwise use sentiment analysis to determine appropriate emote
        if !AvailableAnimations.all.contains(animation) {
            if let contextText = sentimentContext {
                let sentiment = SentimentAnalyzer.sentimentScore(for: contextText) ?? 0.0
                let emote = EmotionMapper.mapSentimentToEmote(sentiment, context: contextText)
                resolvedAnimation = emote.rawValue
                logger.info("Resolved animation via sentiment: \(animation) → emote:\(resolvedAnimation) (sentiment: \(sentiment))")
            } else {
                logger.warning("Invalid animation with no context: \(animation), using idle")
                return .success("No animation triggered (idle)")
            }
        }

        context.playAnimation(named: resolvedAnimation, loop: loop)
        logger.info("Triggered emote: \(resolvedAnimation)")

        return .success("Triggered emote: \(resolvedAnimation)")
    }

    private func executeSetExpression(expression: String, intensity: Double) -> ToolResult {
        guard let context = context else {
            logger.error("No context available for setExpression")
            return .failure("Avatar context not available")
        }

        var resolvedExpression = expression.lowercased()
        var resolvedIntensity = intensity

        // If expression is invalid, use sentiment analysis to pick one
        if !AvailableExpressions.all.contains(resolvedExpression) {
            if let contextText = sentimentContext {
                let sentiment = SentimentAnalyzer.sentimentScore(for: contextText) ?? 0.0
                let mapped = EmotionMapper.mapSentimentToExpression(sentiment, context: contextText)
                resolvedExpression = mapped.preset.rawValue
                resolvedIntensity = Double(mapped.intensity)
                logger.info("Resolved expression via sentiment: \(expression) → \(resolvedExpression) (sentiment: \(sentiment))")
            } else {
                logger.warning("Invalid expression with no context: \(expression), defaulting to neutral")
                resolvedExpression = "neutral"
            }
        }

        // Clamp intensity to valid range
        let clampedIntensity = Float(max(0.0, min(1.0, resolvedIntensity)))

        context.setExpression(resolvedExpression, intensity: clampedIntensity)
        logger.info("Set expression: \(resolvedExpression) at \(Int(clampedIntensity * 100))%")

        return .success("Set expression to \(resolvedExpression)")
    }

    private func executeGetTime(timezone: String) -> ToolResult {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        // Set timezone if provided
        if !timezone.isEmpty, let tz = TimeZone(identifier: timezone) {
            formatter.timeZone = tz
        }

        let timeString = formatter.string(from: Date())
        logger.info("Got time: \(timeString)")

        return .success("Current time: \(timeString)", speakable: "The time is \(timeString)")
    }

    private func executeGetDate(format: String) -> ToolResult {
        let formatter = DateFormatter()
        formatter.timeStyle = .none

        switch format.lowercased() {
        case "short":
            formatter.dateStyle = .short
        default:
            formatter.dateStyle = .full
        }

        let dateString = formatter.string(from: Date())
        logger.info("Got date: \(dateString)")

        return .success("Current date: \(dateString)", speakable: "Today is \(dateString)")
    }
}

// MARK: - Response Processing

extension ToolExecutor {

    /// Process an LLM response that may contain fence-formatted tool calls
    /// Returns the text to speak (with tool calls removed) and executes any tools found
    public func processFenceResponse(_ response: String) async -> (displayText: String, toolResults: [ToolResult]) {
        let toolCalls = FenceParser.parse(response)
        var results: [ToolResult] = []

        for call in toolCalls {
            let result = await execute(call)
            results.append(result)
            logger.info("Tool \(call.name) result: \(result.message)")
        }

        let displayText = FenceParser.extractRemainingText(response)

        return (displayText, results)
    }

    /// Process an Apple Intelligence structured response
    /// - Parameters:
    ///   - response: The structured response from Apple Intelligence
    ///   - userPrompt: The original user prompt (used for sentiment-based fallback)
    /// - Returns: Display text and optional tool result
    @available(iOS 26.0, macOS 26.0, *)
    public func processStructuredResponse(
        _ response: AssistantResponse,
        userPrompt: String? = nil
    ) async -> (displayText: String, toolResult: ToolResult?) {
        var toolResult: ToolResult?

        if let toolCall = response.toolCall {
            // Set sentiment context from user prompt or response for fallback resolution
            sentimentContext = userPrompt ?? response.message
            toolResult = await execute(toolCall)
            sentimentContext = nil
            logger.info("Tool executed: \(toolResult?.message ?? "no message")")
        }

        return (response.message, toolResult)
    }
}
