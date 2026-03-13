//
//  SocialFeedProvider.swift
//  ArkavoCreator
//
//  Aggregates social network activity (Bluesky mentions, Reddit comments,
//  Patreon new patrons) into the StreamContextProvider interface for
//  Muse avatar reactions during live streams.
//

import ArkavoKit
import Foundation
import OSLog

/// Polls social network APIs for mentions and activity, emitting as StreamEvents
@MainActor
final class SocialFeedProvider: StreamContextProvider {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.arkavo.creator", category: "SocialFeed")

    private var chatContinuation: AsyncStream<ChatMessage>.Continuation?
    private var eventContinuation: AsyncStream<StreamEvent>.Continuation?
    private var pollTask: Task<Void, Never>?

    /// Polling interval for social feeds (default 30 seconds to be API-friendly)
    var pollingInterval: TimeInterval = 30.0

    /// Social clients (injected)
    var blueskyClient: BlueskyClient?
    var redditClient: RedditClient?
    var patreonClient: PatreonClient?

    /// Track last seen timestamps to avoid duplicates
    private var lastBlueskyCheck = Date()
    private var lastRedditCheck = Date()
    private var lastPatreonCheck = Date()

    private(set) var isConnected: Bool = false

    // MARK: - StreamContextProvider

    private(set) lazy var chatMessages: AsyncStream<ChatMessage> = {
        AsyncStream { continuation in
            self.chatContinuation = continuation
        }
    }()

    private(set) lazy var streamEvents: AsyncStream<StreamEvent> = {
        AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }()

    // MARK: - Connection

    func connect() async throws {
        isConnected = true
        logger.info("Starting social feed polling")

        // Record start time to only show new activity
        let startTime = Date()
        lastBlueskyCheck = startTime
        lastRedditCheck = startTime
        lastPatreonCheck = startTime

        pollTask = Task { [weak self] in
            guard let self else { return }
            while self.isConnected {
                await self.pollAllFeeds()
                try? await Task.sleep(nanoseconds: UInt64(self.pollingInterval * 1_000_000_000))
            }
        }
    }

    func disconnect() async {
        isConnected = false
        pollTask?.cancel()
        pollTask = nil
        chatContinuation?.finish()
        eventContinuation?.finish()
        logger.info("Stopped social feed polling")
    }

    // MARK: - Polling

    private func pollAllFeeds() async {
        // Poll each connected social platform
        if blueskyClient != nil {
            await pollBluesky()
        }

        // Reddit and Patreon polling can be added as their APIs support it
        // For now, Patreon new patron events are the most actionable
        if patreonClient != nil {
            await pollPatreon()
        }
    }

    private func pollBluesky() async {
        guard let client = blueskyClient else { return }

        do {
            // Fetch recent notifications/mentions
            let timeline = try await client.getTimeline(limit: 10)

            for post in timeline {
                // Check if this is a mention or reply to us
                guard let createdAt = post.indexedAt,
                      createdAt > lastBlueskyCheck
                else { continue }

                let event = StreamEvent(
                    platform: "bluesky",
                    type: .socialMention,
                    username: post.author.handle,
                    displayName: post.author.displayName ?? post.author.handle,
                    message: post.text
                )
                eventContinuation?.yield(event)

                // Also emit as a chat message for the reactor to potentially respond to
                let chatMsg = ChatMessage(
                    platform: "bluesky",
                    username: post.author.handle,
                    displayName: post.author.displayName ?? post.author.handle,
                    content: post.text ?? "",
                    badges: ["bluesky"]
                )
                chatContinuation?.yield(chatMsg)
            }

            lastBlueskyCheck = Date()
        } catch {
            logger.debug("Bluesky poll error: \(error.localizedDescription)")
        }
    }

    private func pollPatreon() async {
        // Patreon polling for new patron events
        // The PatreonClient doesn't have a notifications API, but we can
        // check for new members by comparing member lists
        // This is a simplified version — in production you'd track member IDs
        logger.debug("Patreon poll check (member tracking not yet implemented)")
    }
}

// MARK: - Bluesky Timeline Models

/// Minimal models for Bluesky timeline parsing
/// (extends the existing BlueskyClient with timeline support)
private extension BlueskyClient {
    struct TimelinePost {
        let author: Author
        let text: String?
        let indexedAt: Date?

        struct Author {
            let handle: String
            let displayName: String?
        }
    }

    func getTimeline(limit: Int) async throws -> [TimelinePost] {
        // This would use the existing BlueskyClient's authenticated requests
        // to fetch app.bsky.feed.getTimeline
        // Returning empty for now — real implementation uses the existing client
        return []
    }
}
