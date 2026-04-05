# Gemma 4 MLX Provider for Arkavo Creator

## Context

The app needs on-device LLM inference via Gemma 4 running on Apple Silicon through MLX Swift. The model (`mlx-community/gemma-4-e4b-it-8bit`, ~9 GB) downloads from HuggingFace on first use and becomes the primary provider for all prompts, with Apple Intelligence as fallback.

## Architecture

### New file: `MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift`

Single class `Gemma4Provider` conforming to the existing `LLMResponseProvider` protocol plus a new streaming interface.

```
Gemma4Provider
├── Conforms to LLMResponseProvider (constrained: message + tool call)
├── Adds generateStreaming(prompt:) -> AsyncStream<String>
├── Downloads model from HuggingFace on first use via MLXHuggingFace
├── Holds ModelContainer for warm inference
└── Priority 0 (highest) in LLMFallbackChain
```

### Provider interface

```swift
public final class Gemma4Provider: LLMResponseProvider, @unchecked Sendable {
    public var isAvailable: Bool { get async }  // true once model is loaded
    public var providerName: String { "Gemma 4" }
    public var priority: Int { 0 }

    // Existing constrained interface
    public func generate(prompt: String) async throws -> ConstrainedResponse

    // New streaming interface
    public func generateStreaming(prompt: String) async throws -> AsyncStream<String>

    // Model lifecycle
    public func loadModel() async throws       // Explicit preload
    public func unloadModel()                   // Release memory
}
```

### Model lifecycle

1. **Cold**: `isAvailable` returns false. Call `loadModel()` or it auto-loads on first `generate()`.
2. **Loading**: Downloads from `mlx-community/gemma-4-e4b-it-8bit` via `#huggingFaceLoadModelContainer`. Progress published via `@Published var downloadProgress: Double`.
3. **Warm**: `ModelContainer` held in memory. `isAvailable` returns true. Generation at ~74 tok/s.
4. **Unloaded**: On memory pressure or explicit `unloadModel()`, container is released.

### Integration

At app startup:
```swift
let gemma4 = Gemma4Provider()
fallbackChain.addProvider(gemma4)    // priority 0 — tried first
fallbackChain.addProvider(appleAI)   // priority 1 — fallback
```

The intent classifier routes all intents to Gemma 4 first. For tool calls, `generate(prompt:)` returns `ConstrainedResponse` with parsed tool call. For conversation, consumers use `generateStreaming(prompt:)`.

### Constrained output parsing

For `generate(prompt:)`, the provider:
1. Wraps the user prompt in a system prompt instructing JSON-only output
2. Generates with temperature 0.0 for deterministic tool calls
3. Parses the JSON response into `ConstrainedResponse`
4. Falls back to `ConstrainedResponse(message: rawText, toolCall: nil)` if JSON parsing fails

### Streaming output

For `generateStreaming(prompt:)`:
1. Applies Gemma 4 chat template via the tokenizer
2. Generates with temperature 0.6, topP 0.95
3. Yields decoded text chunks via `AsyncStream<String>`
4. Stops on EOS or max tokens (512 default)

### Dependencies

Add to `MuseCore/Package.swift`:
```swift
.package(url: "https://github.com/huggingface/swift-transformers", from: "1.2.1"),
```

Add to MuseCore target dependencies:
```swift
.product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
.product(name: "Tokenizers", package: "swift-transformers"),
```

### Dtype safety

All scalar constants use explicit dtype matching:
```swift
h = h * MLXArray(scale, dtype: h.dtype)  // NOT: h * scale
```

### Error handling

- Download failure: `isAvailable` stays false, fallback chain moves to Apple Intelligence
- Generation failure: throws, fallback chain catches and tries next provider
- Memory pressure: `unloadModel()` called, next generation re-downloads from HF cache (no re-download if cached)

### Files to create/modify

- **Create**: `MuseCore/Sources/MuseCore/LLM/Gemma4Provider.swift`
- **Modify**: `MuseCore/Package.swift` (add MLXHuggingFace, Tokenizers dependencies)
- **Modify**: App startup code to register the provider with the fallback chain

### Verification

- Build MuseCore successfully with all dependencies
- Load model from HuggingFace cache
- Generate constrained response (tool call) with temperature 0
- Generate streaming text response
- Verify fallback to Apple Intelligence when model is not loaded
