import Foundation

/// Captures stream state for prompt injection into the Producer role
struct StreamStateContext {
    var isLive: Bool = false
    var viewerCount: Int = 0
    var streamDuration: TimeInterval = 0
    var currentScene: String = "Live"
    var recentEvents: [StreamEventSummary] = []
    var chatSentiment: Double = 0.5 // 0.0 = negative, 1.0 = positive

    /// Serializes to text for LLM context injection
    func formattedForPrompt() -> String {
        var lines: [String] = []

        lines.append("Stream Status: \(isLive ? "LIVE" : "OFFLINE")")
        if isLive {
            lines.append("Viewers: \(viewerCount)")
            lines.append("Duration: \(formattedDuration)")
            lines.append("Scene: \(currentScene)")
            lines.append("Chat Sentiment: \(sentimentLabel)")
        }

        if !recentEvents.isEmpty {
            lines.append("Recent Events:")
            for event in recentEvents.suffix(5) {
                lines.append("  - \(event.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private var formattedDuration: String {
        let hours = Int(streamDuration) / 3600
        let minutes = (Int(streamDuration) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var sentimentLabel: String {
        switch chatSentiment {
        case 0..<0.3: "Negative"
        case 0.3..<0.7: "Neutral"
        default: "Positive"
        }
    }
}

/// Lightweight summary of a stream event for prompt context
struct StreamEventSummary: Sendable {
    let type: String
    let displayName: String
    let timestamp: Date

    var summary: String {
        "\(type) from \(displayName)"
    }
}
