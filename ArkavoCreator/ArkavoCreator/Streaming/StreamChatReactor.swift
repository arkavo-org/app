//
//  StreamChatReactor.swift
//  ArkavoCreator
//
//  Bridges streaming chat messages and events to the Muse avatar's
//  conversation system. Handles rate limiting, message filtering,
//  and priority-based message selection.
//

import Foundation
import MuseCore
import OSLog
import VRMMetalKit

/// Connects streaming chat sources to the Muse avatar's reaction system
@MainActor
final class StreamChatReactor {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.arkavo.creator", category: "ChatReactor")

    /// Connected chat providers
    private var providers: [StreamContextProvider] = []

    /// Active listener tasks
    private var listenerTasks: [Task<Void, Never>] = []

    /// Active role determines event handling behavior
    var activeRole: AvatarRole = .sidekick

    /// Rate limiting: minimum seconds between spoken responses
    var responseInterval: TimeInterval = 8.0

    /// Maximum chat queue depth (drop oldest when exceeded)
    var maxQueueDepth: Int = 5

    /// Whether the reactor is actively processing
    private(set) var isRunning = false

    /// Last time the avatar spoke (for rate limiting)
    private var lastResponseTime: Date = .distantPast

    /// Pending messages queue
    private var messageQueue: [ChatMessage] = []

    /// Processing task
    private var processingTask: Task<Void, Never>?

    // MARK: - Callbacks

    /// Called when the avatar should speak a response
    var onSpeechRequest: ((String) async -> Void)?

    /// Called when the avatar should play an emote
    var onEmoteRequest: ((EmoteAnimationLayer.Emote) -> Void)?

    /// Called when the avatar should change expression
    var onExpressionRequest: ((VRMExpressionPreset, Float) -> Void)?

    /// Called when Producer mode receives an event for analysis
    var onProducerEvent: ((StreamEvent) -> Void)?

    // MARK: - Public API

    /// Add a chat provider to listen to
    func addProvider(_ provider: StreamContextProvider) {
        providers.append(provider)

        if isRunning {
            startListening(to: provider)
        }
    }

    /// Start listening to all connected providers
    func start() {
        guard !isRunning else { return }
        isRunning = true

        for provider in providers {
            startListening(to: provider)
        }

        // Start the message processing loop
        processingTask = Task { [weak self] in
            await self?.processLoop()
        }

        logger.info("StreamChatReactor started with \(self.providers.count) providers")
    }

    /// Stop listening and clean up
    func stop() {
        isRunning = false
        for task in listenerTasks {
            task.cancel()
        }
        listenerTasks.removeAll()
        processingTask?.cancel()
        processingTask = nil
        messageQueue.removeAll()
        logger.info("StreamChatReactor stopped")
    }

    // MARK: - Private

    private func startListening(to provider: StreamContextProvider) {
        // Listen for chat messages
        let chatTask = Task { [weak self] in
            for await message in provider.chatMessages {
                await self?.enqueueMessage(message)
            }
        }
        listenerTasks.append(chatTask)

        // Listen for stream events
        let eventTask = Task { [weak self] in
            for await event in provider.streamEvents {
                await self?.handleEvent(event)
            }
        }
        listenerTasks.append(eventTask)
    }

    private func enqueueMessage(_ message: ChatMessage) {
        // Filter out very short messages and commands
        guard message.content.count > 2,
              !message.content.hasPrefix("!"),
              !message.content.hasPrefix("/")
        else { return }

        // Prioritize highlighted messages and subscriber messages
        if message.isHighlighted || message.badges.contains("subscriber") {
            messageQueue.insert(message, at: 0)
        } else {
            messageQueue.append(message)
        }

        // Trim queue to max depth
        while messageQueue.count > maxQueueDepth {
            messageQueue.removeLast()
        }
    }

    private func handleEvent(_ event: StreamEvent) {
        // In Producer mode, forward events for analysis instead of avatar reactions
        if activeRole == .producer {
            onProducerEvent?(event)
            return
        }

        // Events get immediate emote reactions
        switch event.type {
        case .subscribe, .newPatron:
            onEmoteRequest?(.excited)
            onExpressionRequest?(.happy, 0.8)

            // Speak a thank you for subs
            if let name = Optional(event.displayName) {
                Task {
                    await onSpeechRequest?("Thank you for subscribing, \(name)!")
                }
            }

        case .donation, .cheer:
            onEmoteRequest?(.excited)
            onExpressionRequest?(.surprised, 0.7)

            if let amount = event.amount {
                Task {
                    await onSpeechRequest?("Wow, thank you \(event.displayName) for the \(Int(amount))!")
                }
            }

        case .follow:
            onEmoteRequest?(.wave)
            onExpressionRequest?(.happy, 0.5)

        case .raid:
            onEmoteRequest?(.excited)
            onExpressionRequest?(.surprised, 0.9)
            Task {
                await onSpeechRequest?("Welcome raiders! Thanks for the raid, \(event.displayName)!")
            }

        case .giftSub:
            onEmoteRequest?(.excited)
            onExpressionRequest?(.happy, 0.8)

        case .socialMention:
            onEmoteRequest?(.nod)
            onExpressionRequest?(.happy, 0.4)
        }
    }

    /// Main processing loop — picks messages from the queue and responds
    private func processLoop() async {
        while isRunning {
            // Wait for rate limit
            let elapsed = Date().timeIntervalSince(lastResponseTime)
            if elapsed < responseInterval {
                let waitTime = responseInterval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }

            guard isRunning else { break }

            // Pick the next message to respond to
            guard let message = messageQueue.first else {
                // No messages — check again shortly
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                continue
            }

            messageQueue.removeFirst()
            lastResponseTime = Date()

            logger.debug("Responding to \(message.displayName): \(message.content.prefix(50))")

            // Acknowledge with expression while thinking
            onExpressionRequest?(.happy, 0.3)

            // Request speech response (handled by MuseAvatarViewModel)
            await onSpeechRequest?(message.content)
        }
    }
}
