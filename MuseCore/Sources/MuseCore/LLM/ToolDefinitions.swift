import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Avatar Control Tools

/// Tool to trigger avatar animations
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct PlayAnimationTool: Sendable {
    @Guide(description: "Emote: wave, nod, jump, hop, thinking, bow, surprised, laugh, shrug, clap, sad, angry, pout, excited, scared, flex, heart, point, bashful, victory, exhausted, dance, yawn, curious, nervous, proud, relieved, disgust, goodbye, love, confused, grateful, danceGangnam, danceDab, idle")
    public var animation: String

    @Guide(description: "Reserved for future use")
    public var loop: Bool

    public init(animation: String = "none", loop: Bool = false) {
        self.animation = animation
        self.loop = loop
    }
}

/// Tool to set the avatar's facial expression
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct SetExpressionTool: Sendable {
    @Guide(description: "Expression: happy, sad, angry, surprised, relaxed, or neutral")
    public var expression: String

    @Guide(description: "Intensity from 0.0 to 1.0")
    public var intensity: Double

    public init(expression: String = "neutral", intensity: Double = 0.8) {
        self.expression = expression
        self.intensity = max(0.0, min(1.0, intensity))
    }
}

// MARK: - Utility Tools

/// Tool to get the current time
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct GetTimeTool: Sendable {
    @Guide(description: "IANA timezone like America/New_York, or empty for local")
    public var timezone: String

    public init(timezone: String = "") {
        self.timezone = timezone
    }
}

/// Tool to get the current date
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct GetDateTool: Sendable {
    @Guide(description: "Format: short (MM/DD/YY) or long (full date)")
    public var format: String

    public init(format: String = "long") {
        self.format = format
    }
}

// MARK: - Tool Call Enum

/// Represents a tool call that can be executed
@available(iOS 26.0, macOS 26.0, *)
@Generable
public enum ToolCall: Sendable {
    case playAnimation(PlayAnimationTool)
    case setExpression(SetExpressionTool)
    case getTime(GetTimeTool)
    case getDate(GetDateTool)
}

// MARK: - Assistant Response with Optional Tool

/// Structured response from the assistant with optional tool call
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct AssistantResponse: Sendable {
    @Guide(description: "Friendly spoken response")
    public var message: String

    @Guide(description: "Only set if user explicitly asks for animation, expression, time, or date. Leave nil for conversation.")
    public var toolCall: ToolCall?

    public init(message: String = "", toolCall: ToolCall? = nil) {
        self.message = message
        self.toolCall = toolCall
    }
}

// MARK: - Memory Extraction Types

/// A single extracted fact from conversation analysis, for @Generable structured output
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct MemoryFactOutput: Sendable {
    @Guide(description: "Category: personalInfo, preferences, relationships, events, or emotionalState")
    public var category: String

    @Guide(description: "Concise fact about the user, one sentence max")
    public var content: String

    @Guide(description: "2-4 search keywords for this fact")
    public var keywords: [String]

    @Guide(description: "Confidence from 0.0 to 1.0. Higher for direct statements, lower for inferences.")
    public var confidence: Double

    public init(category: String = "personalInfo", content: String = "", keywords: [String] = [], confidence: Double = 0.8) {
        self.category = category
        self.content = content
        self.keywords = keywords
        self.confidence = confidence
    }
}

/// Wrapper for array of extracted facts — required because @Generable cannot be a bare array
@available(iOS 26.0, macOS 26.0, *)
@Generable
public struct MemoryExtractionOutput: Sendable {
    @Guide(description: "Array of extracted facts about the user")
    public var facts: [MemoryFactOutput]

    public init(facts: [MemoryFactOutput] = []) {
        self.facts = facts
    }
}
#endif

// MARK: - Tool Result

/// Result from executing a tool
public struct ToolResult: Sendable {
    public let success: Bool
    public let message: String
    public let speakableText: String?

    public static func success(_ message: String, speakable: String? = nil) -> ToolResult {
        ToolResult(success: true, message: message, speakableText: speakable)
    }

    public static func failure(_ message: String) -> ToolResult {
        ToolResult(success: false, message: message, speakableText: nil)
    }
}

// MARK: - Tool Context Protocol

/// Protocol for providing context to tool execution
@MainActor
public protocol ToolContext: AnyObject {
    func playAnimation(named: String)
    func playAnimation(named: String, loop: Bool)
    func setExpression(_ expression: String, intensity: Float)
    var availableAnimations: [String] { get }
}

// Default implementation for backwards compatibility
extension ToolContext {
    public func playAnimation(named name: String, loop: Bool) {
        // Default: ignore loop parameter
        playAnimation(named: name)
    }
}

// MARK: - Available Tools List

/// List of available animation names for reference
public enum AvailableAnimations {
    /// Motion capture emote animations (VRMA clips)
    public static let emotes = [
        "wave",           // Friendly wave gesture
        "nod",            // Simple acknowledgment nod
        "jump",           // Excited jump with bounce
        "hop",            // Light playful bounce
        "thinking",       // Contemplative pose
        "bow",            // Respectful bow (gratitude)
        "surprised",      // Surprised reaction
        "laugh",          // Body shake with joy
        "shrug",          // Shoulders up "I don't know"
        "clap",           // Applause gesture
        "sad",            // Slumped sad pose
        "angry",          // Tense angry pose
        "pout",           // Disappointed pose
        "excited",        // Excitement animation
        "scared",         // Fear reaction
        "flex",           // Strong flex pose
        "heart",          // Love gesture
        "point",          // Pointing gesture
        "bashful",        // Embarrassed fidgeting
        "victory",        // Victory celebration
        "exhausted",      // Sleepy/exhausted pose
        "dance",          // Dance animation
        "yawn",           // Relaxed yawn/stretch
        "curious",        // Curious looking around
        "nervous",        // Nervous fidgeting
        "proud",          // Proud pose
        "relieved",       // Relief gesture
        "disgust",        // Disgust reaction
        "goodbye",        // Farewell wave
        "love",           // Love expression
        "confused",       // Confused gesture
        "grateful",       // Admiration/gratitude
        "danceGangnam",   // Gangnam Style dance
        "danceDab",       // Dab dance move
        "idle",           // Return to neutral
    ]

    /// All available animations
    public static let all = emotes
}

/// List of available expression names for reference
public enum AvailableExpressions {
    public static let all = [
        "happy",
        "sad",
        "angry",
        "surprised",
        "relaxed",
        "neutral"
    ]
}
