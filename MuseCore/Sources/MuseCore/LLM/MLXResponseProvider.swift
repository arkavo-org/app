import Foundation
import OSLog
import Synchronization

/// Wraps MLXBackend to conform to LLMResponseProvider.
/// Collects the full token stream into a ConstrainedResponse,
/// parsing for tool calls using the FenceParser pattern.
public final class MLXResponseProvider: LLMResponseProvider, @unchecked Sendable {
    private let backend: MLXBackend
    private let logger = Logger(subsystem: "com.arkavo.musecore", category: "MLXResponseProvider")
    private let state = Mutex(ProviderState())

    /// Role determines the system prompt used for generation
    public var activeRole: AvatarRole {
        get { state.withLock { $0.activeRole } }
        set { state.withLock { $0.activeRole = newValue } }
    }

    /// Voice locale for language-specific prompts
    public var voiceLocale: VoiceLocale {
        get { state.withLock { $0.voiceLocale } }
        set { state.withLock { $0.voiceLocale = newValue } }
    }

    /// Optional context injection (stream state for Producer, platform constraints for Publicist)
    public var contextInjection: String? {
        get { state.withLock { $0.contextInjection } }
        set { state.withLock { $0.contextInjection = newValue } }
    }

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
        // Snapshot all three values under a single lock acquisition
        let snapshot = state.withLock { ($0.activeRole, $0.voiceLocale, $0.contextInjection) }
        var prompt = RolePromptProvider.systemPrompt(for: snapshot.0, locale: snapshot.1)
        if let context = snapshot.2 {
            prompt += "\n\n# Current Context\n\(context)"
        }
        return prompt
    }
}

// MARK: - Internal State

private struct ProviderState: ~Copyable {
    var activeRole: AvatarRole = .sidekick
    var voiceLocale: VoiceLocale = .english
    var contextInjection: String?

    init() {}
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
