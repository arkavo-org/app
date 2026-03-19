#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import MuseCore
import Observation

/// Supported content types for Publicist generation
enum PublicistContentType: String, CaseIterable, Sendable {
    case draftPost = "Draft Post"
    case title = "Title"
    case description = "Description"
    case thread = "Thread"
}

/// Target platform for content generation
enum PublicistPlatform: String, CaseIterable, Sendable {
    case bluesky = "Bluesky"
    case youtube = "YouTube"
    case twitch = "Twitch"
    case reddit = "Reddit"
    case microblog = "Micro.blog"
    case patreon = "Patreon"

    var characterLimit: Int? {
        switch self {
        case .bluesky: 300
        case .twitch: 140
        case .youtube: 5000
        case .reddit, .microblog, .patreon: nil
        }
    }

    var platformContext: any PlatformContext {
        switch self {
        case .bluesky: BlueskyContext()
        case .youtube: YouTubeContext()
        case .twitch: TwitchContext()
        case .reddit: RedditContext()
        case .microblog: MicropubContext()
        case .patreon: GenericContext()
        }
    }
}

/// View model for the Publicist role — platform-aware content generation
@Observable
@MainActor
final class PublicistViewModel {
    var selectedPlatform: PublicistPlatform = .bluesky
    var selectedContentType: PublicistContentType = .draftPost
    var sourceText: String = ""
    private(set) var generatedContent: String = ""
    private(set) var isGenerating = false
    private(set) var streamingText: String = ""

    let modelManager: ModelManager
    private var generationTask: Task<Void, Never>?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Character count of the generated content
    var characterCount: Int { generatedContent.count }

    /// Whether the generated content exceeds the platform limit
    var isOverLimit: Bool {
        guard let limit = selectedPlatform.characterLimit else { return false }
        return characterCount > limit
    }

    /// Generate content using the LLM
    func generate() {
        guard modelManager.isReady else { return }
        guard !isGenerating else { return }

        isGenerating = true
        streamingText = ""
        generatedContent = ""

        generationTask = Task {
            let context = selectedPlatform.platformContext
            let prompt = PublicistPromptBuilder.buildActionPrompt(
                action: mapContentTypeToAction(),
                inputText: sourceText.isEmpty ? nil : sourceText,
                context: context
            )
            let systemPrompt = PublicistPromptBuilder.buildSystemPrompt(for: context)

            let stream = modelManager.streamingProvider.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: 512
            )

            do {
                for try await token in stream {
                    streamingText += token
                }
                generatedContent = streamingText
            } catch is CancellationError {
                if !streamingText.isEmpty {
                    generatedContent = streamingText
                }
            } catch {
                generatedContent = "Error: \(error.localizedDescription)"
            }

            streamingText = ""
            isGenerating = false
        }
    }

    /// Stop generation
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    /// Clear generated content
    func clearContent() {
        stopGeneration()
        generatedContent = ""
        streamingText = ""
    }

    /// Copy generated content to clipboard
    func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedContent, forType: .string)
        #else
        UIPasteboard.general.string = generatedContent
        #endif
    }

    private func mapContentTypeToAction() -> PublicistAction {
        switch selectedContentType {
        case .draftPost: .draftPost
        case .title: .generateTitle
        case .description: .generateDescription
        case .thread: .draftPost // Thread uses draft post with thread-specific prompt
        }
    }
}
