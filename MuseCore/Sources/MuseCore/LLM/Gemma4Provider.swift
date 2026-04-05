//
//  Gemma4Provider.swift
//  MuseCore
//
//  LLMResponseProvider implementation backed by the Gemma 4 model via MLX.
//

import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import OSLog
import Tokenizers

// MARK: - Model Configuration

private let gemma4Configuration = ModelConfiguration(
    id: "mlx-community/gemma-4-e4b-it-8bit",
    defaultPrompt: "Hello",
    extraEOSTokens: ["<end_of_turn>"]
)

// MARK: - Internal State Actor

/// Actor that serializes access to the model container.
private actor Gemma4State {
    var container: ModelContainer?
    var downloadProgress: Double = 0

    func setContainer(_ c: ModelContainer) {
        container = c
        downloadProgress = 1.0
    }

    func setProgress(_ p: Double) {
        downloadProgress = p
    }

    func clear() {
        container = nil
        downloadProgress = 0
    }
}

// MARK: - Gemma4Provider

/// LLM provider backed by the Gemma 4 model running locally via MLX.
///
/// The model is downloaded from HuggingFace on first use and cached locally.
/// This provider has `priority = 0` (highest priority) in the fallback chain.
public final class Gemma4Provider: LLMResponseProvider, Sendable {

    private let state = Gemma4State()

    // MARK: - LLMResponseProvider

    public let providerName: String = "Gemma 4"
    public let priority: Int = 0

    public init() {}

    /// True once the model container has been loaded into memory.
    public var isAvailable: Bool {
        get async {
            await state.container != nil
        }
    }

    /// Current download progress in the range [0, 1].
    public var downloadProgress: Double {
        get async {
            await state.downloadProgress
        }
    }

    // MARK: - Model Lifecycle

    /// Download and load the Gemma 4 model into memory.
    ///
    /// Safe to call multiple times — subsequent calls are no-ops if the
    /// container is already loaded.
    public func loadModel() async throws {
        if await state.container != nil { return }

        let container = try await #huggingFaceLoadModelContainer(
            configuration: gemma4Configuration
        )

        await state.setContainer(container)
    }

    /// Release the model container and free GPU/CPU memory.
    public func unloadModel() async {
        await state.clear()
    }

    // MARK: - LLMResponseProvider: generate

    public func generate(prompt: String) async throws -> ConstrainedResponse {
        guard let container = await state.container else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        let systemPrompt = """
            You are a helpful assistant. Respond ONLY with valid JSON matching this schema:
            {"message": "<your reply>", "toolCall": null}
            Do not include any text outside the JSON object.
            """

        let messages: [[String: any Sendable]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": prompt],
        ]

        let userInput = UserInput(messages: messages)
        let input = try await container.prepare(input: userInput)

        let parameters = GenerateParameters(temperature: 0)
        let stream = try await container.generate(input: input, parameters: parameters)

        var fullText = ""
        for await generation in stream {
            if let chunk = generation.chunk {
                fullText += chunk
            }
        }

        return parseResponse(fullText)
    }

    // MARK: - Streaming

    /// Generate a streaming response for the given prompt.
    ///
    /// Yields decoded text chunks through the returned `AsyncStream`.
    public func generateStreaming(prompt: String) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                guard let container = await self.state.container else {
                    continuation.finish()
                    return
                }

                let messages: [[String: any Sendable]] = [
                    ["role": "user", "content": prompt]
                ]

                do {
                    let userInput = UserInput(messages: messages)
                    let input = try await container.prepare(input: userInput)

                    let parameters = GenerateParameters(temperature: 0.6, topP: 0.95)
                    let stream = try await container.generate(input: input, parameters: parameters)

                    for await generation in stream {
                        if let chunk = generation.chunk {
                            continuation.yield(chunk)
                        }
                    }
                } catch {
                    // Finish stream on error
                }

                continuation.finish()
            }
        }
    }

    // MARK: - Private Helpers

    private func parseResponse(_ text: String) -> ConstrainedResponse {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Attempt to extract a JSON object from the response
        if let jsonStart = trimmed.firstIndex(of: "{"),
           let jsonEnd = trimmed.lastIndex(of: "}"),
           jsonStart <= jsonEnd
        {
            let jsonSubstring = trimmed[jsonStart...jsonEnd]
            let jsonData = Data(jsonSubstring.utf8)
            if let decoded = try? JSONDecoder().decode(ConstrainedResponse.self, from: jsonData) {
                return decoded
            }
        }

        // Fallback: wrap raw text in a ConstrainedResponse
        return ConstrainedResponse(message: trimmed)
    }
}
