# Gemma 4 Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Gemma 4 MLX-based LLM provider to Arkavo Creator that downloads the model from HuggingFace on first use and serves as the primary provider for all prompts.

**Architecture:** `Gemma4Provider` conforms to the existing `LLMResponseProvider` protocol and adds a streaming text interface. It wraps `MLXLLM.LLMModelFactory` with `MLXHuggingFace` macros for model download and tokenization. It registers at priority 0 in the `LLMFallbackChain`, with Apple Intelligence as fallback.

**Tech Stack:** MLX Swift, mlx-swift-lm (MLXLLM, MLXLMCommon, MLXHuggingFace), swift-transformers (Tokenizers), HuggingFace Hub

---

### Task 1: Add dependencies to MuseCore Package.swift

**Files:**
- Modify: `MuseCore/Package.swift`

- [ ] **Step 1: Add MLXHuggingFace and Tokenizers to dependencies and target**

```swift
// In MuseCore/Package.swift, update the target dependencies array:
dependencies: [
    "VRMMetalKit",
    .product(name: "MLX", package: "mlx-swift"),
    .product(name: "MLXNN", package: "mlx-swift"),
    .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
    .product(name: "MLXLLM", package: "mlx-swift-lm"),
    .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
    .product(name: "Tokenizers", package: "swift-transformers"),
],
```

Also add swift-transformers to the package-level dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/arkavo-org/VRMMetalKit", exact: "0.9.2"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
    .package(url: "https://github.com/arkavo-ai/mlx-swift-lm", branch: "feature/gemma4-text"),
    .package(url: "https://github.com/huggingface/swift-transformers", from: "1.2.1"),
],
```

- [ ] **Step 2: Verify package resolution**

Run: `cd MuseCore && swift package resolve`
Expected: All packages resolve successfully including MLXHuggingFace and Tokenizers.

- [ ] **Step 3: Verify build**

Run: `cd MuseCore && swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add MuseCore/Package.swift MuseCore/Package.resolved
git commit -m "feat: add MLXHuggingFace and Tokenizers dependencies"
```

---

### Task 2: Create Gemma4Provider with model loading

**Files:**
- Create: `MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift`

- [ ] **Step 1: Create the provider with model lifecycle**

```swift
// MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers
import OSLog

/// Bridges swift-transformers Tokenizer to MLXLMCommon.Tokenizer
private struct TransformersTokenizerBridge: MLXLMCommon.Tokenizer {
    let upstream: Tokenizers.Tokenizer
    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try upstream.applyChatTemplate(messages: messages)
    }
}

/// HuggingFace tokenizer loader for local model directories
private struct HFTokenizerLoader: TokenizerLoader, @unchecked Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        TransformersTokenizerBridge(upstream: try await AutoTokenizer.from(modelFolder: directory))
    }
}

/// Gemma 4 on-device LLM provider using MLX Swift.
/// Downloads mlx-community/gemma-4-e4b-it-8bit (~9 GB) from HuggingFace on first use.
public final class Gemma4Provider: @unchecked Sendable {

    private let logger = Logger(subsystem: "com.arkavo.muse", category: "Gemma4Provider")

    private static let modelID = "mlx-community/gemma-4-e4b-it-8bit"

    /// The loaded model container (nil until loaded)
    private var container: ModelContainer?

    /// Loading state
    private var isLoading = false

    /// Download progress (0.0 to 1.0)
    public private(set) var downloadProgress: Double = 0.0

    public init() {}

    /// Load the model from HuggingFace (downloads on first use, cached after)
    public func loadModel() async throws {
        guard container == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        logger.info("Loading Gemma 4 model: \(Self.modelID)")

        let config = ModelConfiguration(
            id: Self.modelID,
            defaultPrompt: "Hello",
            extraEOSTokens: ["<end_of_turn>"]
        )

        let modelContainer = try await #huggingFaceLoadModelContainer(
            configuration: config,
            progressHandler: { [weak self] progress in
                self?.downloadProgress = progress.fractionCompleted
            }
        )

        self.container = modelContainer
        logger.info("Gemma 4 model loaded successfully")
    }

    /// Release model from memory
    public func unloadModel() {
        container = nil
        logger.info("Gemma 4 model unloaded")
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd MuseCore && swift build`
Expected: Build succeeds. (The model is not loaded at build time.)

- [ ] **Step 3: Commit**

```bash
git add MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift
git commit -m "feat: add Gemma4Provider with HuggingFace model loading"
```

---

### Task 3: Add LLMResponseProvider conformance (constrained generation)

**Files:**
- Modify: `MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift`

- [ ] **Step 1: Add LLMResponseProvider conformance**

Append to `Gemma4Provider.swift`:

```swift
// MARK: - LLMResponseProvider Conformance

extension Gemma4Provider: LLMResponseProvider {

    public var isAvailable: Bool {
        get async { container != nil }
    }

    public var providerName: String { "Gemma 4" }

    public var priority: Int { 0 }  // Highest priority — tried first

    public func generate(prompt: String) async throws -> ConstrainedResponse {
        if container == nil {
            try await loadModel()
        }

        guard let container else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        let systemPrompt = """
            You are a helpful assistant. Respond with a JSON object containing:
            - "message": your spoken response (friendly, concise)
            - "toolCall": optional object with "type" and parameters

            Available tool types: playAnimation, setExpression, getTime, getDate
            If no tool is needed, omit toolCall.
            Respond ONLY with valid JSON, no markdown.
            """

        let result: String = try await container.perform {
            (context: ModelContext) async throws -> String in
            let input = try await context.processor.prepare(
                input: .init(
                    messages: [
                        ["role": "system", "content": systemPrompt],
                        ["role": "user", "content": prompt],
                    ]))
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: .init(maxTokens: 256, temperature: 0.0, topP: 1.0),
                context: context)

            var output = ""
            for await generation in stream {
                if case .chunk(let text) = generation {
                    output += text
                }
            }
            return output
        }

        // Try to parse as JSON ConstrainedResponse
        if let data = result.data(using: .utf8),
           let response = try? JSONDecoder().decode(ConstrainedResponse.self, from: data)
        {
            return response
        }

        // Fallback: return raw text as message
        return ConstrainedResponse(message: result.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd MuseCore && swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift
git commit -m "feat: add LLMResponseProvider conformance to Gemma4Provider"
```

---

### Task 4: Add streaming generation

**Files:**
- Modify: `MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift`

- [ ] **Step 1: Add streaming generation method**

Append to `Gemma4Provider.swift`:

```swift
// MARK: - Streaming Generation

extension Gemma4Provider {

    /// Generate a streaming text response using Gemma 4 chat template.
    /// - Parameter prompt: User's input text
    /// - Returns: AsyncStream yielding text chunks as they're generated
    public func generateStreaming(prompt: String) async throws -> AsyncStream<String> {
        if container == nil {
            try await loadModel()
        }

        guard let container else {
            throw LLMProviderError.notAvailable(provider: providerName)
        }

        let (stream, continuation) = AsyncStream<String>.makeStream()

        Task {
            do {
                try await container.perform {
                    (context: ModelContext) async throws in
                    let input = try await context.processor.prepare(
                        input: .init(
                            messages: [
                                ["role": "user", "content": prompt],
                            ]))
                    let genStream = try MLXLMCommon.generate(
                        input: input,
                        parameters: .init(maxTokens: 512, temperature: 0.6, topP: 0.95),
                        context: context)

                    for await generation in genStream {
                        if case .chunk(let text) = generation {
                            continuation.yield(text)
                        }
                    }
                }
            } catch {
                self.logger.error("Streaming generation failed: \(error.localizedDescription)")
            }
            continuation.finish()
        }

        return stream
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd MuseCore && swift build`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift
git commit -m "feat: add streaming generation to Gemma4Provider"
```

---

### Task 5: Register provider in the app

**Files:**
- Modify: `ArkavoCreator/ArkavoCreator/Avatar/MuseAvatarViewModel.swift`

- [ ] **Step 1: Add Gemma 4 provider to the fallback chain**

In `MuseAvatarViewModel.swift`, modify `setupLLMProviders()` (around line 83):

```swift
/// Configure LLM providers (Gemma 4 + Edge + fallback)
private func setupLLMProviders() {
    var providers: [any LLMResponseProvider] = []

    // Gemma 4 on-device provider (highest priority)
    let gemma4 = Gemma4Provider()
    providers.append(gemma4)

    // Edge provider — if agent service is available
    if let agentService {
        let edge = EdgeLLMProvider(agentService: agentService)
        self.edgeLLMProvider = edge
        providers.append(edge)
    }

    // Create fallback chain
    let chain = LLMFallbackChain()
    for provider in providers {
        chain.addProvider(provider)
    }
    self.llmFallbackChain = chain
}
```

- [ ] **Step 2: Add import if needed**

At the top of `MuseAvatarViewModel.swift`, ensure `import MuseCore` is present (it likely already is since the file uses `LLMFallbackChain`).

- [ ] **Step 3: Build the full app**

Run: Open `Arkavo.xcworkspace` in Xcode, build for macOS (Cmd+B).
Expected: Build succeeds with Gemma4Provider registered.

- [ ] **Step 4: Commit**

```bash
git add ArkavoCreator/ArkavoCreator/Avatar/MuseAvatarViewModel.swift
git commit -m "feat: register Gemma4Provider as primary LLM in avatar view model"
```

---

### Task 6: Run the app and verify Gemma 4 inference

**Files:** None (manual verification)

- [ ] **Step 1: Launch the app**

Run the app from Xcode (Cmd+R) targeting macOS.

- [ ] **Step 2: Trigger a chat interaction**

Send a message through the avatar chat interface. On first use, the model will download (~9 GB). Watch the Xcode console for:
```
[Gemma4Provider] Loading Gemma 4 model: mlx-community/gemma-4-e4b-it-8bit
[Gemma4Provider] Gemma 4 model loaded successfully
[LLMFallbackChain] Attempting generation with Gemma 4
[LLMFallbackChain] Generation succeeded with Gemma 4
```

- [ ] **Step 3: Verify response quality**

The response should be coherent and fast (~74 tok/s on Apple Silicon). If the model fails to load, the fallback chain should gracefully fall back to the next available provider.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: any adjustments from integration testing"
```
