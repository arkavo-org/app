import Foundation
import NaturalLanguage

/// Analyzes sentiment of text using Apple's built-in NaturalLanguage framework.
///
/// Returns sentiment scores in the range [-1.0, 1.0]:
/// - Negative values indicate negative sentiment
/// - Values near 0 indicate neutral sentiment
/// - Positive values indicate positive sentiment
public struct SentimentAnalyzer {

    /// Analyzes the sentiment of the given text.
    ///
    /// - Parameters:
    ///   - text: The text to analyze for sentiment
    ///   - language: The language of the text (defaults to English)
    /// - Returns: A sentiment score in the range [-1.0, 1.0], or nil if analysis fails
    public static func sentimentScore(for text: String, language: NLLanguage = .english) -> Double? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text

        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(language, range: range)

        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)

        return tag.flatMap { Double($0.rawValue) }
    }

    /// Classifies sentiment into a simple categorical representation.
    ///
    /// - Parameters:
    ///   - text: The text to analyze for sentiment
    ///   - language: The language of the text (defaults to English)
    /// - Returns: A `SentimentCategory` representing the overall sentiment
    public static func categorize(_ text: String, language: NLLanguage = .english) -> SentimentCategory {
        guard let score = sentimentScore(for: text, language: language) else {
            return .neutral
        }

        if score > 0.2 {
            return .positive
        } else if score < -0.2 {
            return .negative
        } else {
            return .neutral
        }
    }
}

/// Simple categorical representation of sentiment.
public enum SentimentCategory: String, Sendable {
    case positive
    case neutral
    case negative
}
