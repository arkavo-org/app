import Foundation
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

/// Integration with Apple Writing Tools (iOS 26+, macOS 26+)
/// Provides text refinement, proofreading, summarization where UI supports it
@MainActor
public final class WritingToolsIntegration: ObservableObject {
    @Published public private(set) var isAvailable: Bool = false
    @Published public private(set) var lastError: String?

    public init() {
        checkAvailability()
    }

    /// Check if Writing Tools are available on this device
    private func checkAvailability() {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                isAvailable = true
            } else {
                isAvailable = false
            }
        #elseif os(macOS)
            if #available(macOS 26.0, *) {
                isAvailable = true
            } else {
                isAvailable = false
            }
        #else
            isAvailable = false
        #endif
    }

    /// Execute a tool call using Writing Tools
    public func executeToolCall(_ toolCall: ToolCall) async throws -> ToolCallResult {
        guard isAvailable else {
            throw WritingToolsError.notAvailable
        }

        switch toolCall.name {
        case "writing_tools_proofread":
            return try await proofread(toolCall)
        case "writing_tools_rewrite":
            return try await rewrite(toolCall)
        case "writing_tools_summarize":
            return try await summarize(toolCall)
        default:
            throw WritingToolsError.unknownTool(toolCall.name)
        }
    }

    /// Proofread text using Writing Tools
    private func proofread(_ toolCall: ToolCall) async throws -> ToolCallResult {
        guard let args = toolCall.args.value as? [String: Any],
              let text = args["text"] as? String else {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: "Invalid arguments: 'text' is required"
            )
        }

        do {
            let proofreadText = try await performProofread(text: text)

            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: true,
                result: AnyCodable([
                    "text": proofreadText.correctedText,
                    "corrections": proofreadText.corrections,
                ])
            )
        } catch {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: error.localizedDescription
            )
        }
    }

    /// Rewrite text using Writing Tools
    private func rewrite(_ toolCall: ToolCall) async throws -> ToolCallResult {
        guard let args = toolCall.args.value as? [String: Any],
              let text = args["text"] as? String else {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: "Invalid arguments: 'text' is required"
            )
        }

        let tone = args["tone"] as? String ?? "professional"

        do {
            let rewrittenText = try await performRewrite(text: text, tone: tone)

            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: true,
                result: AnyCodable(["text": rewrittenText])
            )
        } catch {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: error.localizedDescription
            )
        }
    }

    /// Summarize text using Writing Tools
    private func summarize(_ toolCall: ToolCall) async throws -> ToolCallResult {
        guard let args = toolCall.args.value as? [String: Any],
              let text = args["text"] as? String else {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: "Invalid arguments: 'text' is required"
            )
        }

        let length = args["length"] as? String ?? "medium"

        do {
            let summary = try await performSummarize(text: text, length: length)

            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: true,
                result: AnyCodable(["summary": summary])
            )
        } catch {
            return ToolCallResult(
                toolCallId: toolCall.toolCallId,
                success: false,
                error: error.localizedDescription
            )
        }
    }

    /// Perform proofreading with Writing Tools
    /// NOTE: This is a placeholder for the actual iOS 26 Writing Tools API
    private func performProofread(text: String) async throws -> ProofreadResult {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #elseif os(macOS)
            if #available(macOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #endif

        throw WritingToolsError.notAvailable
    }

    /// Perform text rewriting with Writing Tools
    /// NOTE: This is a placeholder for the actual iOS 26 Writing Tools API
    private func performRewrite(text: String, tone: String) async throws -> String {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #elseif os(macOS)
            if #available(macOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #endif

        throw WritingToolsError.notAvailable
    }

    /// Perform text summarization with Writing Tools
    /// NOTE: This is a placeholder for the actual iOS 26 Writing Tools API
    private func performSummarize(text: String, length: String) async throws -> String {
        #if os(iOS)
            if #available(iOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #elseif os(macOS)
            if #available(macOS 26.0, *) {
                throw WritingToolsError.notImplemented("Writing Tools API integration pending")
            }
        #endif

        throw WritingToolsError.notAvailable
    }
}

/// Result of proofreading operation
public struct ProofreadResult {
    public let correctedText: String
    public let corrections: [[String: Any]]

    public init(correctedText: String, corrections: [[String: Any]]) {
        self.correctedText = correctedText
        self.corrections = corrections
    }
}

public enum WritingToolsError: Error, LocalizedError {
    case notAvailable
    case notImplemented(String)
    case unknownTool(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Writing Tools not available on this device (requires iOS 26+ or macOS 26+)"
        case .notImplemented(let detail):
            return "Feature not yet implemented: \(detail)"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        }
    }
}

/// Available Writing Tools
public enum WritingTool {
    /// Proofread text for grammar and spelling
    case proofread(text: String)

    /// Rewrite text with a specific tone
    case rewrite(text: String, tone: String)

    /// Summarize text to a specific length
    case summarize(text: String, length: String)

    public var name: String {
        switch self {
        case .proofread:
            return "writing_tools_proofread"
        case .rewrite:
            return "writing_tools_rewrite"
        case .summarize:
            return "writing_tools_summarize"
        }
    }

    public var args: [String: Any] {
        switch self {
        case .proofread(let text):
            return ["text": text]
        case .rewrite(let text, let tone):
            return ["text": text, "tone": tone]
        case .summarize(let text, let length):
            return ["text": text, "length": length]
        }
    }
}
