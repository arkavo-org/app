//
//  IntentClassifier.swift
//  Muse
//
//  Classifies user messages into intents for LLM routing.
//  Routes quick chat to Apple Intelligence, complex tasks to Gemma-3.
//

import Foundation

// MARK: - User Intent

/// Classification of user intent for routing decisions
public enum UserIntent: Sendable {
    /// Simple conversational exchanges (greetings, short questions)
    /// Routed to Apple Intelligence for fast response
    case quickChat

    /// Requests requiring tool execution (animations, expressions)
    /// Routed to Gemma-3 for structured output
    case toolRequired

    /// Complex reasoning tasks (explanations, multi-step thinking)
    /// Routed to Gemma-3 for thorough processing
    case complexReasoning

    /// System-generated greetings (avatar initiates conversation)
    /// Routed to fastest available provider
    case greeting
}

// MARK: - Intent Classifier

/// Classifies user messages into intents for smart LLM routing
public struct IntentClassifier {

    // MARK: - English Keywords

    /// Tool-related keywords that suggest structured output is needed
    private static let toolKeywords: Set<String> = [
        "show", "set", "change", "make", "animate", "play",
        "expression", "emotion", "wave", "nod", "smile", "frown",
        "happy", "sad", "angry", "surprised", "look", "face",
        "move", "dance", "bow", "gesture"
    ]

    /// Greeting patterns for quick chat
    private static let greetingPatterns: Set<String> = [
        "hi", "hello", "hey", "sup", "yo", "greetings",
        "good morning", "good afternoon", "good evening", "good night",
        "what's up", "how are you", "how's it going"
    ]

    /// Question words that might indicate complex reasoning
    private static let complexQuestionWords: Set<String> = [
        "why", "how", "explain", "describe", "analyze", "compare",
        "what do you think", "tell me about", "help me understand"
    ]

    // MARK: - Japanese Keywords

    /// Japanese tool keywords for animations and expressions
    private static let japaneseToolKeywords: Set<String> = [
        "見せて", "表示", "変えて", "アニメーション", "再生",
        "表情", "感情", "笑顔", "怒り", "悲しい", "驚き",
        "手を振って", "うなずいて", "お辞儀", "踊って",
        "笑って", "泣いて", "怒って", "喜んで",
        "ウェーブ", "ダンス", "ポーズ"
    ]

    /// Japanese greeting patterns
    private static let japaneseGreetingPatterns: Set<String> = [
        "こんにちは", "こんばんは", "おはよう", "おはようございます",
        "やあ", "ハロー", "元気", "調子はどう", "お元気ですか",
        "久しぶり", "どうも", "ただいま", "おかえり"
    ]

    /// Japanese complex question patterns
    private static let japaneseComplexPatterns: Set<String> = [
        "なぜ", "どうして", "説明して", "教えて",
        "どうやって", "比較して", "分析して", "理由は",
        "について教えて", "詳しく"
    ]

    /// Classify a user message into an intent
    /// - Parameter message: The user's input message
    /// - Returns: The classified UserIntent
    public static func classify(_ message: String) -> UserIntent {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for Japanese text first
        if containsJapaneseCharacters(trimmed) {
            return classifyJapanese(trimmed)
        }

        // English classification
        return classifyEnglish(trimmed)
    }

    // MARK: - Japanese Classification

    private static func classifyJapanese(_ message: String) -> UserIntent {
        // Check for Japanese tool keywords first (highest priority)
        if containsJapaneseToolKeywords(message) {
            return .toolRequired
        }

        // Check for Japanese greetings
        if isJapaneseGreeting(message) {
            return .quickChat
        }

        // Check for complex patterns
        if containsJapaneseComplexPatterns(message) {
            return .complexReasoning
        }

        // Default: short messages → quick chat, long → complex
        return message.count < 30 ? .quickChat : .complexReasoning
    }

    private static func containsJapaneseCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            // Hiragana, Katakana, or CJK ranges
            (0x3040...0x309F).contains(scalar.value) ||  // Hiragana
            (0x30A0...0x30FF).contains(scalar.value) ||  // Katakana
            (0x4E00...0x9FFF).contains(scalar.value)     // CJK
        }
    }

    private static func containsJapaneseToolKeywords(_ text: String) -> Bool {
        for keyword in japaneseToolKeywords {
            if text.contains(keyword) {
                return true
            }
        }
        return false
    }

    private static func isJapaneseGreeting(_ text: String) -> Bool {
        for greeting in japaneseGreetingPatterns {
            if text.hasPrefix(greeting) || text == greeting {
                return true
            }
        }
        return false
    }

    private static func containsJapaneseComplexPatterns(_ text: String) -> Bool {
        for pattern in japaneseComplexPatterns {
            if text.contains(pattern) {
                return true
            }
        }
        return false
    }

    // MARK: - English Classification

    private static func classifyEnglish(_ message: String) -> UserIntent {
        let lowercased = message.lowercased()
        let words = Set(lowercased.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty })

        // Check for tool keywords first (highest priority)
        if containsToolKeywords(words) {
            return .toolRequired
        }

        // Check for simple greetings
        if isGreeting(lowercased) {
            return .quickChat
        }

        // Check message length and complexity
        let wordCount = lowercased.split(separator: " ").count

        // Short messages (< 10 words) without complex patterns → quick chat
        if wordCount < 10 && !containsComplexPatterns(lowercased) {
            return .quickChat
        }

        // Longer messages or those with complex question words → complex reasoning
        if wordCount > 20 || containsComplexPatterns(lowercased) {
            return .complexReasoning
        }

        // Default to quick chat for moderate-length simple messages
        return .quickChat
    }

    private static func containsToolKeywords(_ words: Set<String>) -> Bool {
        // Check if any whole word matches a tool keyword
        !words.isDisjoint(with: toolKeywords)
    }

    private static func isGreeting(_ text: String) -> Bool {
        // Check for exact greeting match or greeting at start
        for greeting in greetingPatterns {
            if text == greeting || text.hasPrefix(greeting + " ") || text.hasPrefix(greeting + ",") {
                return true
            }
        }
        return false
    }

    private static func containsComplexPatterns(_ text: String) -> Bool {
        for pattern in complexQuestionWords {
            if text.contains(pattern) {
                return true
            }
        }
        return false
    }
}
