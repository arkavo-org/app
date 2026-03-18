import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import Synchronization

/// MLX-based streaming LLM provider for on-device inference.
/// Wraps mlx-swift-examples v2 model loading and generation.
public final class MLXBackend: StreamingLLMProvider, @unchecked Sendable {
    private let state = Mutex(BackendState())

    public let providerName = "MLX Local"

    public init() {}

    public var isAvailable: Bool {
        get async {
            state.withLock { $0.modelContainer != nil }
        }
    }

    /// Load a model by HuggingFace ID
    public func loadModel(_ huggingFaceID: String) async throws {
        let container = try await MLXLMCommon.loadModelContainer(
            id: huggingFaceID
        ) { progress in
            debugPrint("Loading \(huggingFaceID): \(Int(progress.fractionCompleted * 100))%")
        }

        // Set memory limit to 75% of system RAM for safety
        let systemMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let limitBytes = Int(Double(systemMemoryGB) * 0.75) * 1024 * 1024 * 1024
        MLX.GPU.set(memoryLimit: limitBytes)

        state.withLock { $0.modelContainer = container }
    }

    /// Unload the current model to free GPU memory
    public func unloadModel() {
        state.withLock { $0.modelContainer = nil }
        MLX.GPU.clearCache()
    }

    public func generate(
        prompt: String,
        systemPrompt: String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: StreamingLLMError.modelNotLoaded)
                    return
                }

                guard let container = self.state.withLock({ $0.modelContainer }) else {
                    continuation.finish(throwing: StreamingLLMError.modelNotLoaded)
                    return
                }

                do {
                    let userInput = UserInput(chat: [
                        .system(systemPrompt),
                        .user(prompt),
                    ])

                    let parameters = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: 0.7,
                        topP: 0.9,
                        repetitionPenalty: 1.1
                    )

                    try await container.perform { context in
                        let lmInput = try await context.processor.prepare(input: userInput)
                        let stream = try MLXLMCommon.generate(
                            input: lmInput,
                            parameters: parameters,
                            context: context
                        )

                        for await generation in stream {
                            if Task.isCancelled { break }
                            if let chunk = generation.chunk {
                                continuation.yield(chunk)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: StreamingLLMError.generationCancelled)
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            state.withLock { $0.generationTask = task }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func cancelGeneration() async {
        let task = state.withLock { s -> Task<Void, Never>? in
            let t = s.generationTask
            s.generationTask = nil
            return t
        }
        task?.cancel()
    }
}

// MARK: - Internal State

private struct BackendState: ~Copyable {
    var modelContainer: ModelContainer?
    var generationTask: Task<Void, Never>?

    init() {}
}
