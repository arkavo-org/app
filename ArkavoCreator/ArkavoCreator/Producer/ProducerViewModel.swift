import Foundation
import MuseCore
import Observation

/// A timestamped suggestion from the Producer
struct ProducerSuggestion: Identifiable {
    let id = UUID()
    let text: String
    let category: Category
    let timestamp = Date()

    enum Category: String {
        case alert = "Alert"
        case suggestion = "Suggestion"
        case info = "Info"
    }
}

/// View model for the Producer role — monitors stream and generates suggestions
@Observable
@MainActor
final class ProducerViewModel {
    private(set) var suggestions: [ProducerSuggestion] = []
    private(set) var isGenerating = false
    var streamState = StreamStateContext()

    let modelManager: ModelManager
    private var autoSuggestTask: Task<Void, Never>?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Generate a suggestion based on current stream state
    func generateSuggestion(prompt: String? = nil) {
        guard modelManager.isReady else { return }
        guard !isGenerating else { return }

        isGenerating = true

        Task {
            let userPrompt = prompt ?? "Analyze the current stream state and provide one actionable suggestion."
            let systemPrompt = RolePromptProvider.systemPrompt(for: .producer, locale: .english)
            let contextPrompt = streamState.formattedForPrompt()
            let fullSystemPrompt = systemPrompt + "\n\n# Current Context\n" + contextPrompt

            let stream = modelManager.streamingProvider.generate(
                prompt: userPrompt,
                systemPrompt: fullSystemPrompt,
                maxTokens: 256
            )

            var fullText = ""
            do {
                for try await token in stream {
                    fullText += token
                }
            } catch {
                fullText = "Error generating suggestion: \(error.localizedDescription)"
            }

            let category = categorize(fullText)
            let suggestion = ProducerSuggestion(text: fullText, category: category)
            suggestions.insert(suggestion, at: 0)

            // Keep last 20 suggestions
            if suggestions.count > 20 {
                suggestions = Array(suggestions.prefix(20))
            }

            isGenerating = false
        }
    }

    /// Start auto-generating suggestions on a timer when live
    func startAutoSuggestions(interval: TimeInterval = 60) {
        stopAutoSuggestions()
        autoSuggestTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, streamState.isLive, modelManager.isReady else { continue }
                generateSuggestion()
            }
        }
    }

    /// Stop auto-generating suggestions
    func stopAutoSuggestions() {
        autoSuggestTask?.cancel()
        autoSuggestTask = nil
    }

    /// Update stream state from Twitch client data
    func updateStreamState(
        isLive: Bool,
        viewerCount: Int,
        streamStartedAt: Date?,
        currentScene: String
    ) {
        streamState.isLive = isLive
        streamState.viewerCount = viewerCount
        streamState.currentScene = currentScene
        if let start = streamStartedAt {
            streamState.streamDuration = Date().timeIntervalSince(start)
        }
    }

    /// Add a stream event to the context
    func addEvent(type: String, displayName: String) {
        let event = StreamEventSummary(type: type, displayName: displayName, timestamp: Date())
        streamState.recentEvents.append(event)
        // Keep last 10
        if streamState.recentEvents.count > 10 {
            streamState.recentEvents = Array(streamState.recentEvents.suffix(10))
        }
    }

    /// Clear all suggestions
    func clearSuggestions() {
        suggestions.removeAll()
    }

    private func categorize(_ text: String) -> ProducerSuggestion.Category {
        let lowered = text.lowercased()
        if lowered.contains("[alert]") || lowered.contains("warning") || lowered.contains("drop") {
            return .alert
        } else if lowered.contains("[info]") || lowered.contains("note") {
            return .info
        }
        return .suggestion
    }
}
