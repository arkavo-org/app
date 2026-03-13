import Foundation
import OSLog

// MARK: - GoodbyeDetector

@MainActor
public final class GoodbyeDetector {
    private let logger = Logger(subsystem: "com.arkavo.muse", category: "GoodbyeDetector")

    /// Common goodbye phrases for detection
    private static let goodbyePhrases: Set<String> = [
        "bye", "goodbye", "good bye", "see ya", "see you", "gotta go",
        "got to go", "have to go", "need to go", "i'm out", "i'm off",
        "later", "catch you later", "talk later", "peace", "peace out",
        "take care", "good night", "goodnight", "night", "heading out",
        "leaving now", "signing off", "that's all", "that's it for now"
    ]

    /// Japanese goodbye phrases
    private static let japaneseGoodbyePhrases: Set<String> = [
        "さようなら", "バイバイ", "じゃあね", "またね", "おやすみ",
        "おやすみなさい", "行ってきます", "失礼します", "お先に"
    ]

    public init() {}

    /// Detect if a message is a goodbye
    /// Only triggers for short messages that are primarily goodbyes
    public func isGoodbye(_ message: String) -> Bool {
        let lowercased = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Only check short messages (goodbyes are typically brief)
        // This prevents false positives like "I'll tell you later"
        guard lowercased.count < 50 else { return false }

        // Check if message starts with or is a goodbye phrase
        for phrase in Self.goodbyePhrases {
            if lowercased == phrase ||
               lowercased.hasPrefix(phrase + " ") ||
               lowercased.hasPrefix(phrase + ",") ||
               lowercased.hasPrefix(phrase + "!") ||
               lowercased.hasPrefix(phrase + ".") {
                return true
            }
        }

        // Check Japanese goodbye phrases
        for phrase in Self.japaneseGoodbyePhrases {
            if message.contains(phrase) {
                return true
            }
        }

        return false
    }

    /// Generate a goodbye response that closes the conversation warmly
    public func generateResponse(
        userMessage: String,
        llmChain: LLMFallbackChain,
        userName: String?,
        locale: VoiceLocale
    ) async -> String {
        var prompt = """
        You are Muse, and the person is saying goodbye. They said: "\(userMessage)"
        """

        if let name = userName {
            prompt += "\nTheir name is \(name)."
        }

        prompt += """

        Generate a warm, natural farewell that:
        - Acknowledges they're leaving
        - \(userName != nil ? "Uses their name naturally (once, not forced)" : "Doesn't need their name")
        - Implies you'll be here when they come back
        - Matches their energy (casual goodbye = casual response)
        - Is SHORT (1 sentence)
        - Sounds like a real friend, not a customer service bot

        Generate ONLY the goodbye, nothing else.
        """

        do {
            let (response, _) = try await llmChain.generate(
                prompt: prompt,
                intent: .greeting,
                locale: locale
            )

            var text = response.message.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.hasPrefix("\"") && text.hasSuffix("\"") {
                text = String(text.dropFirst().dropLast())
            }
            return text
        } catch {
            logger.error("Goodbye generation failed: \(error.localizedDescription)")
            return ""
        }
    }
}
