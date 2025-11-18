# How to Use Apple On-Device LLM in Your iOS App

A comprehensive guide for developers to integrate Apple's on-device Language Model (Foundation Models) for chat functionality in iOS 26+, iPadOS 26+, and macOS 26+ applications.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Implementation Guide](#implementation-guide)
  - [1. Setting Up the Apple Intelligence Client](#1-setting-up-the-apple-intelligence-client)
  - [2. Creating a Chat Interface](#2-creating-a-chat-interface)
  - [3. Managing Chat Sessions](#3-managing-chat-sessions)
  - [4. Handling Responses](#4-handling-responses)
- [Advanced Features](#advanced-features)
  - [Writing Tools Integration](#writing-tools-integration)
  - [Structured Output Generation](#structured-output-generation)
  - [Streaming Responses](#streaming-responses)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Example Implementation](#example-implementation)

---

## Overview

Apple's Foundation Models framework provides on-device language model capabilities for iOS 26+, iPadOS 26+, and macOS 26+. This allows you to:

- Generate text responses from prompts locally (no internet required)
- Create chat interfaces powered by on-device AI
- Perform text refinement, proofreading, and summarization
- Generate structured JSON output conforming to schemas
- Ensure user privacy with all processing happening on-device

**Key Benefits:**
- ✅ No API keys required
- ✅ Complete privacy - data never leaves the device
- ✅ No network dependency
- ✅ Low latency responses
- ✅ No usage costs

---

## Prerequisites

**Required:**
- Xcode 16+ with iOS 26 SDK
- Target devices running iOS 26+, iPadOS 26+, or macOS 26+
- Swift 6.2+

**Framework Imports:**
```swift
import FoundationModels  // Apple's on-device LLM framework
import Foundation
import SwiftUI  // For UI integration
```

**Info.plist Configuration:**
No special entitlements required for basic text generation. The system automatically handles model availability and loading.

---

## Quick Start

Here's the minimal code to get started with Apple's on-device LLM:

```swift
import FoundationModels

class SimpleLLMChat {
    private var session: LanguageModelSession?
    private var isAvailable = false

    init() {
        checkAvailability()
    }

    func checkAvailability() {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                isAvailable = true
                session = LanguageModelSession()
                print("✅ Apple Intelligence is available")
            } else {
                print("❌ Apple Intelligence not available on this device")
            }
        }
        #endif
        #endif
    }

    func chat(prompt: String) async throws -> String {
        guard isAvailable, let session = session else {
            return "Apple Intelligence is not available on this device."
        }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            let response = try await session.respond(to: prompt)
            return response
        }
        #endif
        #endif

        return "Unable to generate response"
    }
}

// Usage
let llm = SimpleLLMChat()
let response = try await llm.chat(prompt: "What is Swift?")
print(response)
```

---

## Implementation Guide

### 1. Setting Up the Apple Intelligence Client

Create a dedicated client class to manage the on-device LLM:

```swift
import FoundationModels

final class AppleIntelligenceClient {
    private var session: Any?  // Type-erased to avoid @available everywhere
    var isAvailable = false

    init() {
        checkAvailability()
    }

    func checkAvailability() {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                isAvailable = true
                session = LanguageModelSession()
            }
        }
        #endif
        #endif
    }

    func generateText(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Double = 0.7
    ) async throws -> String {
        guard isAvailable else {
            throw LLMError.notAvailable
        }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                throw LLMError.sessionNotInitialized
            }

            // Note: Foundation Models handles max tokens and temperature internally
            // The API is simpler than external LLM APIs
            let response = try await session.respond(to: prompt)
            return response
        }
        #endif
        #endif

        throw LLMError.platformNotSupported
    }
}

enum LLMError: Error {
    case notAvailable
    case sessionNotInitialized
    case platformNotSupported
}
```

**Key Points:**
- Use `SystemLanguageModel.default.availability` to check if the model is available
- Store session as `Any` to avoid `@available` propagation throughout your codebase
- Foundation Models handles token limits and temperature internally
- All operations are async/await based

---

### 2. Creating a Chat Interface

Build a SwiftUI view for chat interaction:

```swift
import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var messageText = ""

    var body: some View {
        VStack {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            // Input field
            HStack {
                TextField("Message", text: $messageText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Apple Intelligence Chat")
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        messageText = ""
        Task {
            await viewModel.sendMessage(text)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }

            Text(message.content)
                .padding(12)
                .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)

            if !message.isUser {
                Spacer()
            }
        }
    }
}
```

---

### 3. Managing Chat Sessions

Create a view model to manage chat state and LLM interactions:

```swift
import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false

    private let llmClient = AppleIntelligenceClient()

    init() {
        // Add welcome message
        if llmClient.isAvailable {
            messages.append(ChatMessage(
                content: "Hello! I'm running on Apple Intelligence. How can I help you?",
                isUser: false
            ))
        } else {
            messages.append(ChatMessage(
                content: "Apple Intelligence is not available on this device.",
                isUser: false
            ))
        }
    }

    func sendMessage(_ text: String) async {
        // Add user message
        let userMessage = ChatMessage(content: text, isUser: true)
        messages.append(userMessage)

        isGenerating = true
        defer { isGenerating = false }

        do {
            // Generate response
            let response = try await llmClient.generateText(prompt: text)

            // Add assistant message
            let assistantMessage = ChatMessage(content: response, isUser: false)
            messages.append(assistantMessage)

        } catch {
            // Handle errors
            let errorMessage = ChatMessage(
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                isUser: false
            )
            messages.append(errorMessage)
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let isUser: Bool
    let timestamp = Date()
}
```

**Key Features:**
- `@MainActor` ensures UI updates happen on the main thread
- Published properties automatically update the UI
- Async message handling with proper error management
- Clean separation of concerns (View ↔ ViewModel ↔ LLM Client)

---

### 4. Handling Responses

**Basic Response:**
```swift
let response = try await llmClient.generateText(prompt: "Explain SwiftUI")
```

**With Context (Conversation History):**
```swift
func generateWithContext(userMessage: String, history: [ChatMessage]) async throws -> String {
    // Build conversation context
    var contextPrompt = "Previous conversation:\n"
    for message in history.suffix(10) {  // Last 10 messages
        let role = message.isUser ? "User" : "Assistant"
        contextPrompt += "\(role): \(message.content)\n"
    }
    contextPrompt += "\nUser: \(userMessage)\nAssistant:"

    return try await llmClient.generateText(prompt: contextPrompt)
}
```

**Error Handling:**
```swift
do {
    let response = try await llmClient.generateText(prompt: prompt)
    // Process response
} catch LLMError.notAvailable {
    // Handle unavailable LLM (show message to user)
    print("Apple Intelligence is not available")
} catch LLMError.sessionNotInitialized {
    // Reinitialize session
    llmClient.checkAvailability()
} catch {
    // Handle other errors
    print("Error generating response: \(error)")
}
```

---

## Advanced Features

### Writing Tools Integration

Apple's Writing Tools provide specialized text processing capabilities:

```swift
import FoundationModels

final class WritingToolsIntegration {
    private var session: Any?
    var isAvailable = false

    init() {
        checkAvailability()
    }

    func checkAvailability() {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                isAvailable = true
                session = LanguageModelSession()
            }
        }
        #endif
        #endif
    }

    // Proofread text for grammar and spelling
    func proofread(text: String) async throws -> ProofreadResult {
        guard isAvailable else { throw LLMError.notAvailable }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                throw LLMError.sessionNotInitialized
            }

            let prompt = """
            Proofread the following text and correct any grammar or spelling errors.
            Return only the corrected text.

            Text: \(text)
            """

            let correctedText = try await session.respond(to: prompt)
            return ProofreadResult(originalText: text, correctedText: correctedText)
        }
        #endif
        #endif

        throw LLMError.platformNotSupported
    }

    // Rewrite text with different tone
    func rewrite(text: String, tone: WritingTone) async throws -> String {
        guard isAvailable else { throw LLMError.notAvailable }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                throw LLMError.sessionNotInitialized
            }

            let prompt = """
            Rewrite the following text in a \(tone.rawValue) tone.
            Preserve the meaning but adjust the style.

            Text: \(text)
            """

            return try await session.respond(to: prompt)
        }
        #endif
        #endif

        throw LLMError.platformNotSupported
    }

    // Summarize text
    func summarize(text: String, length: SummaryLength) async throws -> String {
        guard isAvailable else { throw LLMError.notAvailable }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                throw LLMError.sessionNotInitialized
            }

            let lengthInstruction: String
            switch length {
            case .short: lengthInstruction = "in 1-2 sentences"
            case .medium: lengthInstruction = "in a brief paragraph"
            case .long: lengthInstruction = "in 2-3 paragraphs"
            }

            let prompt = """
            Summarize the following text \(lengthInstruction):

            \(text)
            """

            return try await session.respond(to: prompt)
        }
        #endif
        #endif

        throw LLMError.platformNotSupported
    }
}

struct ProofreadResult {
    let originalText: String
    let correctedText: String

    var hasChanges: Bool {
        originalText != correctedText
    }
}

enum WritingTone: String {
    case professional = "professional"
    case casual = "casual"
    case friendly = "friendly"
    case formal = "formal"
}

enum SummaryLength {
    case short
    case medium
    case long
}
```

**Usage:**
```swift
let tools = WritingToolsIntegration()

// Proofread
let result = try await tools.proofread(text: "I has a dreams")
print(result.correctedText)  // "I have a dream"

// Rewrite
let rewritten = try await tools.rewrite(
    text: "Hey! Check this out!",
    tone: .professional
)
print(rewritten)  // "Please review this information."

// Summarize
let summary = try await tools.summarize(
    text: longArticle,
    length: .short
)
```

---

### Structured Output Generation

Generate JSON output conforming to specific schemas:

```swift
func generateStructuredOutput<T: Codable>(
    prompt: String,
    schema: T.Type
) async throws -> T {
    guard isAvailable else { throw LLMError.notAvailable }

    #if canImport(FoundationModels)
    #if os(iOS) || os(macOS)
    if #available(iOS 26.0, macOS 26.0, *) {
        guard let session = session as? LanguageModelSession else {
            throw LLMError.sessionNotInitialized
        }

        // Request JSON output matching the schema
        let jsonPrompt = """
        \(prompt)

        Return the response as valid JSON matching this structure:
        \(schemaDescription(for: T.self))

        Return only the JSON, no additional text.
        """

        let jsonResponse = try await session.respond(to: jsonPrompt)

        // Parse JSON response
        guard let data = jsonResponse.data(using: .utf8) else {
            throw LLMError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
    #endif
    #endif

    throw LLMError.platformNotSupported
}

// Helper to describe schema
private func schemaDescription<T>(for type: T.Type) -> String {
    // Return JSON schema description
    // This is simplified - you may want a more robust schema generator
    return String(describing: type)
}

// Example usage
struct SentimentAnalysis: Codable {
    let sentiment: String  // positive, negative, neutral
    let confidence: Double
    let reasoning: String
}

let analysis: SentimentAnalysis = try await llmClient.generateStructuredOutput(
    prompt: "Analyze the sentiment of: 'I love this product!'",
    schema: SentimentAnalysis.self
)

print("Sentiment: \(analysis.sentiment)")
print("Confidence: \(analysis.confidence)")
```

---

### Streaming Responses

Simulate streaming for better UX (Foundation Models doesn't provide native streaming in iOS 26):

```swift
func streamGeneration(
    prompt: String,
    onDelta: @escaping (String) -> Void
) async throws {
    guard isAvailable else { throw LLMError.notAvailable }

    #if canImport(FoundationModels)
    #if os(iOS) || os(macOS)
    if #available(iOS 26.0, macOS 26.0, *) {
        guard let session = session as? LanguageModelSession else {
            throw LLMError.sessionNotInitialized
        }

        // Generate full response
        let fullResponse = try await session.respond(to: prompt)

        // Simulate streaming by chunking the response
        let chunkSize = 10  // characters per chunk
        for i in stride(from: 0, to: fullResponse.count, by: chunkSize) {
            let start = fullResponse.index(fullResponse.startIndex, offsetBy: i)
            let end = fullResponse.index(
                start,
                offsetBy: min(chunkSize, fullResponse.count - i)
            )
            let chunk = String(fullResponse[start..<end])

            // Call delta handler
            onDelta(chunk)

            // Small delay to simulate streaming
            try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        }
    }
    #endif
    #endif
}

// Usage in ViewModel
func sendMessageWithStreaming(_ text: String) async {
    messages.append(ChatMessage(content: text, isUser: true))

    // Add empty assistant message
    let assistantMessage = ChatMessage(content: "", isUser: false)
    messages.append(assistantMessage)

    var streamedText = ""

    do {
        try await llmClient.streamGeneration(prompt: text) { delta in
            streamedText += delta
            // Update the last message
            if let index = messages.lastIndex(where: { !$0.isUser }) {
                messages[index] = ChatMessage(content: streamedText, isUser: false)
            }
        }
    } catch {
        messages.append(ChatMessage(
            content: "Error: \(error.localizedDescription)",
            isUser: false
        ))
    }
}
```

---

## Best Practices

### 1. **Always Check Availability**

```swift
// ✅ Good: Check before using
if llmClient.isAvailable {
    let response = try await llmClient.generateText(prompt: prompt)
} else {
    // Show fallback UI or message
    showUnavailableMessage()
}

// ❌ Bad: Assume it's available
let response = try await llmClient.generateText(prompt: prompt)
```

### 2. **Use Proper Concurrency**

```swift
// ✅ Good: Use @MainActor for UI updates
@MainActor
class ChatViewModel: ObservableObject {
    func sendMessage(_ text: String) async {
        // Automatically on main thread
        messages.append(userMessage)
    }
}

// ❌ Bad: Manual thread switching
class ChatViewModel: ObservableObject {
    func sendMessage(_ text: String) {
        Task {
            DispatchQueue.main.async {
                // Unnecessary complexity
            }
        }
    }
}
```

### 3. **Handle Errors Gracefully**

```swift
// ✅ Good: Specific error handling
do {
    let response = try await llmClient.generateText(prompt: prompt)
} catch LLMError.notAvailable {
    showMessage("AI features require iOS 26 or later")
} catch LLMError.sessionNotInitialized {
    llmClient.checkAvailability()
    retry()
} catch {
    showMessage("An error occurred: \(error.localizedDescription)")
}

// ❌ Bad: Generic catch-all
do {
    let response = try await llmClient.generateText(prompt: prompt)
} catch {
    print("Error")  // No user feedback
}
```

### 4. **Manage Context Window**

```swift
// ✅ Good: Limit conversation history
let recentMessages = messages.suffix(10)  // Last 10 messages
let context = buildContext(from: recentMessages)

// ❌ Bad: Send entire history
let context = buildContext(from: messages)  // Could be hundreds of messages
```

### 5. **Provide User Feedback**

```swift
// ✅ Good: Show loading state
@Published var isGenerating = false

func sendMessage(_ text: String) async {
    isGenerating = true
    defer { isGenerating = false }

    // Generate response...
}

// In view
if viewModel.isGenerating {
    ProgressView()
        .progressViewStyle(.circular)
}
```

### 6. **Use Type Erasure for Session**

```swift
// ✅ Good: Type-erased session
private var session: Any?

func generateText(...) async throws -> String {
    if #available(iOS 26.0, *) {
        guard let session = session as? LanguageModelSession else {
            throw LLMError.sessionNotInitialized
        }
        // Use session
    }
}

// ❌ Bad: Direct session (requires @available everywhere)
@available(iOS 26.0, *)
private var session: LanguageModelSession?
// Now all methods need @available
```

### 7. **Privacy-First Design**

```swift
// ✅ Good: Keep data local
// Foundation Models processes everything on-device
// No need to send data to external servers

// ❌ Bad: Sending sensitive data to cloud
// Don't mix on-device LLM with cloud APIs for sensitive data
```

---

## Troubleshooting

### Issue: "Apple Intelligence is not available"

**Causes:**
- Device doesn't support Apple Intelligence (requires A17 Pro or M-series chip)
- OS version is below iOS 26 / macOS 26
- Model not downloaded yet (system downloads on first use)

**Solutions:**
```swift
// Check specific availability reasons
#if canImport(FoundationModels)
if #available(iOS 26.0, *) {
    switch SystemLanguageModel.default.availability {
    case .available:
        print("✅ Available")
    case .unavailable:
        print("❌ Not available on this device")
    @unknown default:
        print("⚠️ Unknown availability status")
    }
}
#endif
```

### Issue: Slow Response Times

**Solutions:**
- First response may be slow (model loading)
- Subsequent responses should be faster
- Keep prompts concise
- Use streaming for better perceived performance

```swift
// Cache the session
private let session = LanguageModelSession()  // Reuse

// Keep prompts focused
let prompt = "Summarize in one sentence: \(text)"
// Not: "Please provide a comprehensive analysis..."
```

### Issue: Unexpected or Low-Quality Responses

**Solutions:**
- Be more specific in prompts
- Provide examples
- Use structured output for consistent formatting

```swift
// ❌ Vague prompt
"What is this?"

// ✅ Specific prompt
"Analyze the sentiment of this customer review and classify it as positive, negative, or neutral: '\(review)'"

// ✅ With examples
"""
Classify the sentiment. Examples:
"Great product!" → positive
"Terrible experience" → negative
"It's okay" → neutral

Review: "\(review)"
Sentiment:
"""
```

### Issue: App Crashes on Older iOS Versions

**Solution:**
```swift
// Ensure all Foundation Models code is properly guarded
#if canImport(FoundationModels)
#if os(iOS) || os(macOS)
if #available(iOS 26.0, macOS 26.0, *) {
    // Foundation Models code here
} else {
    // Fallback for older versions
}
#endif
#endif
```

### Issue: Memory Issues with Large Conversations

**Solution:**
```swift
// Limit context size
private let maxHistoryMessages = 20

func pruneHistory() {
    if messages.count > maxHistoryMessages {
        // Keep system message + recent messages
        let systemMessages = messages.filter { $0.isSystem }
        let recentMessages = messages.suffix(maxHistoryMessages - systemMessages.count)
        messages = systemMessages + recentMessages
    }
}
```

---

## Example Implementation

Here's a complete, production-ready example combining all the concepts:

**AppleIntelligenceClient.swift:**
```swift
import Foundation
import FoundationModels

final class AppleIntelligenceClient {
    static let shared = AppleIntelligenceClient()

    private var session: Any?
    private(set) var isAvailable = false

    private init() {
        checkAvailability()
    }

    func checkAvailability() {
        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                isAvailable = true
                session = LanguageModelSession()
            }
        }
        #endif
        #endif
    }

    func generateText(prompt: String) async throws -> String {
        guard isAvailable else {
            throw LLMError.notAvailable
        }

        #if canImport(FoundationModels)
        #if os(iOS) || os(macOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let session = session as? LanguageModelSession else {
                throw LLMError.sessionNotInitialized
            }

            return try await session.respond(to: prompt)
        }
        #endif
        #endif

        throw LLMError.platformNotSupported
    }
}

enum LLMError: LocalizedError {
    case notAvailable
    case sessionNotInitialized
    case platformNotSupported
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device. Requires iOS 26+ with compatible hardware."
        case .sessionNotInitialized:
            return "Language model session not initialized."
        case .platformNotSupported:
            return "This platform is not supported."
        case .invalidResponse:
            return "Received invalid response from language model."
        }
    }
}
```

**ChatViewModel.swift:**
```swift
import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?

    private let llmClient = AppleIntelligenceClient.shared
    private let maxHistoryMessages = 20

    init() {
        setupWelcomeMessage()
    }

    private func setupWelcomeMessage() {
        if llmClient.isAvailable {
            messages.append(ChatMessage(
                content: "Hello! I'm powered by Apple Intelligence running locally on your device. Your privacy is protected - all processing happens on-device. How can I help you today?",
                role: .assistant
            ))
        } else {
            messages.append(ChatMessage(
                content: "Apple Intelligence is not available on this device. This feature requires iOS 26 or later with compatible hardware (A17 Pro or M-series chip).",
                role: .system
            ))
        }
    }

    func sendMessage(_ text: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(content: trimmedText, role: .user))

        // Prune history if needed
        pruneHistoryIfNeeded()

        // Generate response
        isGenerating = true
        errorMessage = nil

        do {
            let context = buildContext()
            let response = try await llmClient.generateText(prompt: context)

            messages.append(ChatMessage(content: response, role: .assistant))

        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                content: "I encountered an error: \(error.localizedDescription)",
                role: .system
            ))
        }

        isGenerating = false
    }

    private func buildContext() -> String {
        var context = ""

        // Include recent conversation history
        let recentMessages = messages.suffix(10)
        for message in recentMessages {
            switch message.role {
            case .user:
                context += "User: \(message.content)\n"
            case .assistant:
                context += "Assistant: \(message.content)\n"
            case .system:
                break  // Skip system messages in context
            }
        }

        context += "Assistant:"
        return context
    }

    private func pruneHistoryIfNeeded() {
        guard messages.count > maxHistoryMessages else { return }

        // Keep welcome message + recent messages
        let welcomeMessage = messages.first
        let recentMessages = messages.suffix(maxHistoryMessages - 1)

        if let welcome = welcomeMessage {
            messages = [welcome] + recentMessages
        } else {
            messages = Array(recentMessages)
        }
    }

    func clearChat() {
        messages.removeAll()
        setupWelcomeMessage()
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let content: String
    let role: Role
    let timestamp = Date()

    enum Role {
        case user
        case assistant
        case system
    }
}
```

**ChatView.swift:**
```swift
import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }

                        if viewModel.isGenerating {
                            TypingIndicator()
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: viewModel.isGenerating) { _ in
                    scrollToBottom(proxy: proxy)
                }
            }

            Divider()

            // Input area
            HStack(spacing: 12) {
                TextField("Message", text: $messageText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isTextFieldFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Color.blue : Color.gray)
                }
                .disabled(!canSend)
            }
            .padding()
        }
        .navigationTitle("Apple Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive, action: viewModel.clearChat) {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !viewModel.isGenerating
    }

    private func sendMessage() {
        guard canSend else { return }

        let text = messageText
        messageText = ""
        isTextFieldFocused = false

        Task {
            await viewModel.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let lastMessage = viewModel.messages.last else { return }
        withAnimation {
            proxy.scrollTo(lastMessage.id, anchor: .bottom)
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role != .user {
                Spacer(minLength: 60)
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return Color(.systemGray5)
        case .system:
            return Color(.systemOrange).opacity(0.2)
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}

struct TypingIndicator: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                    .opacity(animationPhase == index ? 1.0 : 0.3)
            }
        }
        .padding(12)
        .background(Color(.systemGray5))
        .cornerRadius(16)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                animationPhase = 0
            }
        }
    }
}

#Preview {
    NavigationStack {
        ChatView()
    }
}
```

---

## Conclusion

You now have everything you need to integrate Apple's on-device LLM into your iOS app! Key takeaways:

✅ **Privacy-first**: All processing happens on-device
✅ **Simple API**: Just `LanguageModelSession.respond(to:)`
✅ **No costs**: Free to use, no API keys required
✅ **iOS 26+ only**: Requires latest OS and compatible hardware
✅ **Fallback handling**: Always check availability and handle errors

For more advanced use cases, check out the Arkavo app implementation at:
- `ArkavoKit/Sources/ArkavoAgent/AppleIntelligenceClient.swift`
- `ArkavoKit/Sources/ArkavoAgent/LocalAIAgent.swift`
- `Arkavo/Arkavo/AgentService.swift`

Happy coding! 🚀
