//
//  MuseAvatarViewModel.swift
//  ArkavoCreator
//
//  Manages the Muse AI avatar lifecycle: model loading, animation,
//  frame capture, and conversation integration with streaming chat.
//

import ArkavoKit
import Foundation
import Metal
import MuseCore
import SwiftUI
import VRMMetalKit

/// ViewModel for the Muse AI-driven avatar in streaming mode
@MainActor
class MuseAvatarViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isModelLoaded = false
    @Published var isLoading = false
    @Published var error: String?
    @Published var conversationState: AvatarConversationState = .idle
    @Published var lastChatMessage: String?

    // MARK: - Dependencies

    private(set) var renderer: MuseAvatarRenderer?
    private var captureManager: VRMFrameCaptureManager?
    private var ttsAudioSource: MuseTTSAudioSource?
    private var edgeLLMProvider: EdgeLLMProvider?
    private var llmFallbackChain: LLMFallbackChain?
    private var mlxResponseProvider: MLXResponseProvider?
    private var conversationManager: ConversationManager?

    /// Stream chat reactor for processing chat messages
    private(set) var chatReactor: StreamChatReactor?

    /// Agent service for Edge LLM backend
    weak var agentService: CreatorAgentService?

    /// Shared model manager — provides the MLX backend for Sidekick inference
    weak var modelManager: ModelManager?

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Initialize the renderer and audio source
    func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            error = "Failed to create Metal device"
            return
        }

        guard let museRenderer = MuseAvatarRenderer(device: device) else {
            error = "Failed to create Muse avatar renderer"
            return
        }

        self.renderer = museRenderer

        // Create TTS audio source
        let audioSource = MuseTTSAudioSource()
        self.ttsAudioSource = audioSource

        // Setup LLM provider chain
        setupLLMProviders()

        // Setup chat reactor
        let reactor = StreamChatReactor()
        reactor.onSpeechRequest = { [weak self] text in
            await self?.speak(text)
        }
        reactor.onEmoteRequest = { [weak self] emote in
            self?.renderer?.triggerEmote(emote)
        }
        reactor.onExpressionRequest = { [weak self] preset, intensity in
            self?.renderer?.setSentiment(preset, intensity: intensity)
        }
        self.chatReactor = reactor
    }

    /// Configure LLM providers (Edge + MLX Local fallback)
    private func setupLLMProviders() {
        var providers: [any LLMResponseProvider] = []

        // Edge provider (priority 0) — if agent service is available
        if let agentService {
            let edge = EdgeLLMProvider(agentService: agentService)
            self.edgeLLMProvider = edge
            providers.append(edge)
        }

        // MLX Local provider (priority 2) — on-device via shared ModelManager
        if let modelManager {
            let mlx = MLXResponseProvider(backend: modelManager.streamingProvider)
            mlx.activeRole = .sidekick
            mlx.voiceLocale = .english
            self.mlxResponseProvider = mlx
            providers.append(mlx)
        }

        // Create fallback chain
        let chain = LLMFallbackChain()
        for provider in providers {
            chain.addProvider(provider)
        }
        self.llmFallbackChain = chain

        // Setup conversation manager for multi-turn context
        let cm = ConversationManager(maxHistoryMessages: 20)
        cm.activeRole = .sidekick
        cm.voiceLocale = .english
        self.conversationManager = cm
    }

    // MARK: - Model Loading

    func loadModel(from url: URL) async {
        guard let renderer else {
            error = "Renderer not initialized. Call setup() first."
            return
        }

        isLoading = true
        error = nil

        do {
            try await renderer.loadModel(from: url)
            isModelLoaded = true
        } catch {
            self.error = error.localizedDescription
            isModelLoaded = false
        }

        isLoading = false
    }

    // MARK: - Conversation

    /// Speak text with lip sync and TTS
    func speak(_ text: String) async {
        guard let renderer, let tts = ttsAudioSource else { return }

        // Update conversation state
        conversationState = .speaking
        renderer.setConversationState(.speaking)

        // Prepare lip sync
        renderer.prepareLipSync(text: text)

        // Start TTS and lip sync together
        tts.speak(text)
        renderer.startLipSync()

        // Wait for TTS to finish
        tts.onUtteranceFinished = { [weak self] in
            Task { @MainActor in
                self?.renderer?.stopLipSync()
                self?.renderer?.setConversationState(.idle)
                self?.conversationState = .idle
            }
        }
    }

    /// Process a chat message through the LLM and respond
    func respondToChat(_ message: ChatMessage) async {
        guard let chain = llmFallbackChain else { return }

        conversationState = .thinking
        renderer?.setConversationState(.thinking)
        lastChatMessage = "\(message.displayName): \(message.content)"

        do {
            // Build prompt with conversation history and viewer context
            let userMessage = "\(message.displayName) says: \(message.content)"
            conversationManager?.addUserMessage(userMessage)
            let prompt = conversationManager?.buildPromptForMessage(userMessage) ?? userMessage

            let (response, _) = try await chain.generate(prompt: prompt)
            conversationManager?.addAssistantMessage(response.message)
            await speak(response.message)

            // Handle tool calls (emotes, expressions)
            if let toolCall = response.toolCall {
                handleToolCall(toolCall)
            }
        } catch {
            // Fallback: acknowledge the message with an emote
            renderer?.triggerEmote(.nod)
            renderer?.setSentiment(.happy, intensity: 0.4)
        }

        conversationState = .idle
    }

    /// Handle stream events (subs, donations, etc.)
    func reactToEvent(_ event: StreamEvent) {
        switch event.type {
        case .subscribe, .newPatron:
            renderer?.triggerEmote(.excited)
            renderer?.setSentiment(.happy, intensity: 0.8)
        case .donation, .cheer:
            renderer?.triggerEmote(.excited)
            renderer?.setSentiment(.surprised, intensity: 0.7)
        case .follow:
            renderer?.triggerEmote(.wave)
            renderer?.setSentiment(.happy, intensity: 0.5)
        case .raid:
            renderer?.triggerEmote(.excited)
            renderer?.setSentiment(.surprised, intensity: 0.9)
        case .giftSub:
            renderer?.triggerEmote(.excited)
            renderer?.setSentiment(.happy, intensity: 0.8)
        case .socialMention:
            renderer?.triggerEmote(.nod)
            renderer?.setSentiment(.happy, intensity: 0.4)
        }
    }

    // MARK: - Tool Calls

    private func handleToolCall(_ toolCall: ConstrainedToolCall) {
        switch toolCall {
        case .playAnimation(let animation, _):
            if let emote = EmoteAnimationLayer.Emote(rawValue: animation) {
                renderer?.triggerEmote(emote)
            }
        case .setExpression(let expression, let intensity):
            if let preset = VRMExpressionPreset(rawValue: expression) {
                renderer?.setSentiment(preset, intensity: Float(intensity))
            }
        case .getTime, .getDate:
            break // Handled by tool executor
        }
    }

    // MARK: - Frame Capture

    /// Returns a texture provider for RecordingSession
    func getTextureProvider() -> (@Sendable () -> CVPixelBuffer?)? {
        guard let renderer else { return nil }

        if captureManager == nil {
            guard let device = MTLCreateSystemDefaultDevice() else { return nil }
            do {
                captureManager = try VRMFrameCaptureManager(device: device)
                captureManager?.museRenderer = renderer
            } catch {
                return nil
            }
        }

        guard let manager = captureManager else { return nil }
        manager.startCapture()

        return { [weak manager] in
            manager?.latestFrame
        }
    }

    /// Get the TTS audio source for registration with AudioRouter
    func getAudioSource() -> MuseTTSAudioSource? {
        ttsAudioSource
    }

    // MARK: - Lifecycle

    func pause() {
        renderer?.pause()
        captureManager?.stopCapture()
    }

    func resume() {
        renderer?.resume()
        captureManager?.startCapture()
    }

    func cleanup() async {
        captureManager?.stopCapture()
        try? await ttsAudioSource?.stop()
        chatReactor?.stop()
    }
}
