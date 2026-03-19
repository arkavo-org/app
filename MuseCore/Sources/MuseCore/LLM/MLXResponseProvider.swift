import Foundation
import OSLog

/// Wraps MLXBackend to conform to LLMResponseProvider.
/// Collects the full token stream into a ConstrainedResponse,
/// parsing for tool calls using the FenceParser pattern.
public final class MLXResponseProvider: LLMResponseProvider, @unchecked Sendable {
    private let backend: MLXBackend
    private let logger = Logger(subsystem: "com.arkavo.musecore", category: "MLXResponseProvider")

    /// Role determines the system prompt used for generation
    public var activeRole: AvatarRole = .sidekick

    /// Voice locale for language-specific prompts
    public var voiceLocale: VoiceLocale = .english

    /// Optional context injection (stream state for Producer, platform constraints for Publicist)
    public var contextInjection: String?

    public init(backend: MLXBackend) {
        self.backend = backend
    }

    public var isAvailable: Bool {
        get async {
            await backend.isAvailable
        }
    }

    public var providerName: String { "MLX Local" }

    public var priority: Int { 2 }

    public func generate(prompt: String) async throws -> ConstrainedResponse {
        let systemPrompt = buildSystemPrompt()

        let stream = backend.generate(
            prompt: prompt,
            systemPrompt: systemPrompt,
            maxTokens: 512
        )

        var fullText = ""
        for try await token in stream {
            fullText += token
        }

        // Try parsing tool calls from the response
        let parsed = FenceParser.parse(fullText)
        if let toolCall = parsed.first {
            let remaining = FenceParser.extractRemainingText(fullText)
            return ConstrainedResponse(
                message: remaining.isEmpty ? fullText : remaining,
                toolCall: toolCall.toConstrainedToolCall()
            )
        }

        return ConstrainedResponse(message: fullText)
    }

    private func buildSystemPrompt() -> String {
        var prompt = RolePromptProvider.systemPrompt(for: activeRole, locale: voiceLocale)
        if let context = contextInjection {
            prompt += "\n\n# Current Context\n\(context)"
        }
        return prompt
    }
}

// MARK: - ParsedToolCall Extension

extension ParsedToolCall {
    func toConstrainedToolCall() -> ConstrainedToolCall? {
        switch name.lowercased() {
        case "playanimation", "play_animation":
            if case .string(let animation) = arguments["animation"] {
                var loop = false
                if case .bool(let l) = arguments["loop"] { loop = l }
                return .playAnimation(animation: animation, loop: loop)
            }
        case "setexpression", "set_expression":
            if case .string(let expression) = arguments["expression"] {
                var intensity = 0.5
                if case .float(let i) = arguments["intensity"] { intensity = i }
                return .setExpression(expression: expression, intensity: intensity)
            }
        case "gettime", "get_time":
            var timezone: String?
            if case .string(let tz) = arguments["timezone"] { timezone = tz }
            return .getTime(timezone: timezone)
        case "getdate", "get_date":
            var format = "short"
            if case .string(let f) = arguments["format"] { format = f }
            return .getDate(format: format)
        default:
            break
        }
        return nil
    }
}
