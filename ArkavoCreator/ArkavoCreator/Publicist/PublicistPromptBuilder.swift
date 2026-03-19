import Foundation

/// Composes system prompts for the Publicist role's content creation tasks
enum PublicistPromptBuilder {
    /// Build a system prompt incorporating platform context
    static func buildSystemPrompt(for context: any PlatformContext) -> String {
        """
        You are Muse in Publicist mode — a content creation specialist for a social media creator. \
        You help draft, rewrite, and adapt content across platforms. \
        Be concise, creative, and match the tone appropriate for each platform.

        \(context.systemPromptFragment)

        Guidelines:
        - Be direct and helpful. Skip preamble.
        - When drafting, provide ready-to-use content.
        - When rewriting, preserve the core message while improving clarity and engagement.
        - Respect character limits strictly when specified.
        - Suggest hashtags, keywords, or formatting only when relevant to the platform.
        """
    }

    /// Build a prompt with conversation history
    static func buildPrompt(
        userMessage: String,
        context: any PlatformContext,
        conversationHistory: [(role: String, content: String)] = []
    ) -> String {
        var prompt = ""

        if !conversationHistory.isEmpty {
            for entry in conversationHistory.suffix(10) {
                prompt += "\(entry.role): \(entry.content)\n"
            }
            prompt += "\n"
        }

        prompt += userMessage
        return prompt
    }

    /// Build a prompt for a specific action
    static func buildActionPrompt(
        action: PublicistAction,
        inputText: String?,
        context: any PlatformContext
    ) -> String {
        let platformInfo = context.characterLimit.map { "Maximum \($0) characters. " } ?? ""

        switch action {
        case .draftPost:
            if let input = inputText, !input.isEmpty {
                return "Draft a \(context.platformName) post about: \(input). \(platformInfo)"
            }
            return "Draft an engaging \(context.platformName) post. \(platformInfo)"

        case .rewrite:
            guard let input = inputText, !input.isEmpty else {
                return "Please provide text to rewrite."
            }
            return "Rewrite this for \(context.platformName): \(input). \(platformInfo)"

        case .adjustTone:
            guard let input = inputText, !input.isEmpty else {
                return "Please provide text to adjust."
            }
            return "Adjust the tone of this text to be more engaging for \(context.platformName): \(input). \(platformInfo)"

        case .adaptCrossPlatform:
            guard let input = inputText, !input.isEmpty else {
                return "Please provide content to adapt."
            }
            return "Adapt this content for \(context.platformName): \(input). \(platformInfo)"

        case .generateTitle:
            if let input = inputText, !input.isEmpty {
                return "Generate a compelling title for \(context.platformName) about: \(input)"
            }
            return "Generate a compelling title for \(context.platformName) content."

        case .generateDescription:
            if let input = inputText, !input.isEmpty {
                return "Generate a description for \(context.platformName) about: \(input)"
            }
            return "Generate a description for \(context.platformName) content."
        }
    }
}
