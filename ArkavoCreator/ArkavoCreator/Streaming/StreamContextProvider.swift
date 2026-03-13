//
//  StreamContextProvider.swift
//  ArkavoCreator
//
//  Unified protocol for streaming chat and event sources.
//  Feeds context to Muse avatar for on-stream reactions.
//

import Foundation

/// A chat message from any streaming platform
struct ChatMessage: Sendable, Identifiable {
    let id: String
    let platform: String  // "twitch", "youtube", "bluesky", etc.
    let username: String
    let displayName: String
    let content: String
    let timestamp: Date
    let badges: [String]  // e.g., "subscriber", "moderator"
    let isHighlighted: Bool

    init(
        id: String = UUID().uuidString,
        platform: String,
        username: String,
        displayName: String,
        content: String,
        timestamp: Date = Date(),
        badges: [String] = [],
        isHighlighted: Bool = false
    ) {
        self.id = id
        self.platform = platform
        self.username = username
        self.displayName = displayName
        self.content = content
        self.timestamp = timestamp
        self.badges = badges
        self.isHighlighted = isHighlighted
    }
}

/// A stream event (subscriptions, donations, follows, etc.)
struct StreamEvent: Sendable, Identifiable {
    enum EventType: String, Sendable {
        case follow
        case subscribe
        case giftSub
        case donation
        case raid
        case cheer  // Twitch bits
        case newPatron
        case socialMention
    }

    let id: String
    let platform: String
    let type: EventType
    let username: String
    let displayName: String
    let message: String?
    let amount: Double?  // Dollar amount or bits
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        platform: String,
        type: EventType,
        username: String,
        displayName: String,
        message: String? = nil,
        amount: Double? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.platform = platform
        self.type = type
        self.username = username
        self.displayName = displayName
        self.message = message
        self.amount = amount
        self.timestamp = timestamp
    }
}

/// Protocol for any source that provides streaming context (chat, events)
@MainActor
protocol StreamContextProvider: AnyObject {
    /// Stream of chat messages
    var chatMessages: AsyncStream<ChatMessage> { get }

    /// Stream of stream events (subs, donations, etc.)
    var streamEvents: AsyncStream<StreamEvent> { get }

    /// Whether this provider is currently connected
    var isConnected: Bool { get }

    /// Connect and start receiving messages/events
    func connect() async throws

    /// Disconnect and stop receiving
    func disconnect() async
}
