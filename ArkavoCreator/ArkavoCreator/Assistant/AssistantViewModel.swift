import Foundation
import MuseCore
import Observation

/// Message in the assistant conversation
struct AssistantMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()

    enum Role: Sendable {
        case user
        case assistant
        case system
    }
}

/// View model for the AI assistant
@Observable
@MainActor
final class AssistantViewModel {
    private(set) var messages: [AssistantMessage] = []
    private(set) var streamingText = ""
    private(set) var isGenerating = false

    let modelManager: ModelManager

    private var platformContext: any PlatformContext = GenericContext()
    private var generationTask: Task<Void, Never>?

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    /// Update the platform context when navigation changes
    func updateContext(_ section: NavigationSection) {
        platformContext = section.platformContext

        // Auto-unload large models when entering Studio
        if section == .studio,
           modelManager.selectedModel.estimatedMemoryMB > 2000,
           modelManager.isReady
        {
            Task {
                await modelManager.unloadModel(reason: "Unloaded for recording performance")
            }
        }
    }

    /// Send a user message and generate a response
    func send(message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        messages.append(AssistantMessage(role: .user, content: message))

        guard modelManager.isReady else {
            messages.append(AssistantMessage(
                role: .system,
                content: "Model not loaded. Tap the model indicator to load."
            ))
            return
        }

        isGenerating = true
        streamingText = ""

        generationTask = Task {
            let systemPrompt = AssistantPromptBuilder.buildSystemPrompt(for: platformContext)
            let history = messages.suffix(10).compactMap { msg -> (role: String, content: String)? in
                switch msg.role {
                case .user: ("User", msg.content)
                case .assistant: ("Assistant", msg.content)
                case .system: nil
                }
            }
            let prompt = AssistantPromptBuilder.buildPrompt(
                userMessage: message,
                context: platformContext,
                conversationHistory: history
            )

            let stream = modelManager.streamingProvider.generate(
                prompt: prompt,
                systemPrompt: systemPrompt,
                maxTokens: 512
            )

            do {
                for try await token in stream {
                    streamingText += token
                }
                // Finalize
                let finalText = streamingText
                messages.append(AssistantMessage(role: .assistant, content: finalText))
            } catch is CancellationError {
                if !streamingText.isEmpty {
                    messages.append(AssistantMessage(role: .assistant, content: streamingText))
                }
            } catch {
                if !streamingText.isEmpty {
                    messages.append(AssistantMessage(role: .assistant, content: streamingText))
                } else {
                    messages.append(AssistantMessage(role: .system, content: "Error: \(error.localizedDescription)"))
                }
            }

            streamingText = ""
            isGenerating = false
        }
    }

    /// Perform a quick action
    func performAction(_ action: AssistantAction, inputText: String? = nil) {
        let prompt = AssistantPromptBuilder.buildActionPrompt(
            action: action,
            inputText: inputText,
            context: platformContext
        )
        send(message: prompt)
    }

    /// Regenerate the last assistant response
    func regenerate() {
        // Find the last user message
        guard let lastUserMessage = messages.last(where: { $0.role == .user }) else { return }

        // Remove last assistant message if present
        if let lastIndex = messages.indices.last, messages[lastIndex].role == .assistant {
            messages.removeLast()
        }

        send(message: lastUserMessage.content)
    }

    /// Stop generation
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    /// Clear conversation
    func clearConversation() {
        stopGeneration()
        messages.removeAll()
        streamingText = ""
    }
}
