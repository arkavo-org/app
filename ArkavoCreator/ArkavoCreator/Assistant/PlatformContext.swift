import Foundation

/// Describes platform-specific constraints and actions for the AI assistant
protocol PlatformContext {
    var platformName: String { get }
    var systemPromptFragment: String { get }
    var characterLimit: Int? { get }
    var suggestedActions: [AssistantAction] { get }
}

/// Actions the assistant can perform based on the current platform
enum AssistantAction: String, CaseIterable, Sendable {
    case draftPost = "Draft Post"
    case rewrite = "Rewrite"
    case adjustTone = "Adjust Tone"
    case adaptCrossPlatform = "Adapt to Platform"
    case generateTitle = "Generate Title"
    case generateDescription = "Generate Description"
}

// MARK: - Platform Contexts

struct BlueskyContext: PlatformContext {
    let platformName = "Bluesky"
    let characterLimit: Int? = 300
    let suggestedActions: [AssistantAction] = [.draftPost, .rewrite, .adjustTone, .adaptCrossPlatform]
    var systemPromptFragment: String {
        """
        Currently helping with: Bluesky
        Post constraints: Maximum 300 characters. Supports mentions (@handle) and links.
        Style: Casual, engaging, concise. Hashtags are not commonly used on Bluesky.
        """
    }
}

struct YouTubeContext: PlatformContext {
    let platformName = "YouTube"
    let characterLimit: Int? = 5000
    let suggestedActions: [AssistantAction] = [.generateTitle, .generateDescription, .adjustTone, .adaptCrossPlatform]
    var systemPromptFragment: String {
        """
        Currently helping with: YouTube
        Title: Max 100 characters, SEO-friendly, attention-grabbing.
        Description: Up to 5000 characters. First 2-3 lines most important (shown before "Show more").
        Include relevant keywords, timestamps, links, and calls-to-action.
        Tags: Relevant keywords for discoverability.
        """
    }
}

struct TwitchContext: PlatformContext {
    let platformName = "Twitch"
    let characterLimit: Int? = 140
    let suggestedActions: [AssistantAction] = [.generateTitle, .draftPost, .adjustTone]
    var systemPromptFragment: String {
        """
        Currently helping with: Twitch
        Stream title: Maximum 140 characters. Should be engaging and descriptive.
        Tags: Up to 10 tags for discoverability.
        Style: Energetic, community-focused, often uses emotes and casual language.
        """
    }
}

struct RedditContext: PlatformContext {
    let platformName = "Reddit"
    let characterLimit: Int? = nil
    let suggestedActions: [AssistantAction] = [.draftPost, .generateTitle, .rewrite, .adjustTone]
    var systemPromptFragment: String {
        """
        Currently helping with: Reddit
        Title: Concise, descriptive, follows subreddit conventions.
        Body: Supports Markdown. Length varies by subreddit norms.
        Style: Authentic, community-aware. Avoid overly promotional language.
        """
    }
}

struct MicropubContext: PlatformContext {
    let platformName = "Micro.blog"
    let characterLimit: Int? = nil
    let suggestedActions: [AssistantAction] = [.draftPost, .rewrite, .adjustTone, .generateTitle]
    var systemPromptFragment: String {
        """
        Currently helping with: Micro.blog / Micropub
        Supports HTML and Markdown. Blog-style content.
        Style: Thoughtful, personal voice. Can be long-form or microblog (< 280 chars for timeline).
        """
    }
}

struct LibraryContext: PlatformContext {
    let platformName = "Library"
    let characterLimit: Int? = nil
    let suggestedActions: [AssistantAction] = [.generateTitle, .generateDescription]
    var systemPromptFragment: String {
        """
        Currently helping with: Recording Library
        Generate titles and descriptions for recorded videos.
        Style: Clear, descriptive, professional.
        """
    }
}

struct GenericContext: PlatformContext {
    let platformName = "General"
    let characterLimit: Int? = nil
    let suggestedActions: [AssistantAction] = [.draftPost, .rewrite, .adjustTone, .adaptCrossPlatform]
    var systemPromptFragment: String {
        """
        Currently in general mode. Help with any content creation task.
        Available platforms: Bluesky, YouTube, Twitch, Reddit, Micro.blog.
        """
    }
}

// MARK: - Navigation Section Extension

extension NavigationSection {
    /// Get the appropriate platform context for this section
    var platformContext: any PlatformContext {
        switch self {
        case .dashboard: GenericContext()
        case .profile: GenericContext()
        case .studio: GenericContext()
        case .library: LibraryContext()
        case .workflow: GenericContext()
        case .assistant: GenericContext()
        case .patrons: GenericContext()
        case .protection: GenericContext()
        case .social: GenericContext()
        case .settings: GenericContext()
        }
    }
}
