//
//  YouTubeLiveChatClient.swift
//  ArkavoCreator
//
//  Polls YouTube Data API v3 for live chat messages.
//  Uses liveChatMessages.list endpoint with quota-friendly polling.
//

import Foundation
import OSLog

/// YouTube live chat client using Data API v3 polling
@MainActor
final class YouTubeLiveChatClient: StreamContextProvider {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.arkavo.creator", category: "YouTubeChat")

    private var chatContinuation: AsyncStream<ChatMessage>.Continuation?
    private var eventContinuation: AsyncStream<StreamEvent>.Continuation?
    private var pollTask: Task<Void, Never>?

    /// YouTube API key or OAuth access token
    var apiKey: String?

    /// Live chat ID (obtained from broadcast details)
    var liveChatId: String?

    /// Polling interval in seconds (YouTube recommends respecting pollingIntervalMillis)
    var pollingInterval: TimeInterval = 6.0

    /// Next page token for pagination
    private var nextPageToken: String?

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
        guard let apiKey = apiKey, let chatId = liveChatId else {
            logger.error("Missing API key or live chat ID")
            return
        }

        isConnected = true
        logger.info("Starting YouTube live chat polling for chatId: \(chatId)")

        // Start polling loop
        pollTask = Task { [weak self] in
            guard let self else { return }
            while self.isConnected {
                await self.pollMessages(apiKey: apiKey, chatId: chatId)
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
        logger.info("Stopped YouTube live chat polling")
    }

    // MARK: - Polling

    private func pollMessages(apiKey: String, chatId: String) async {
        var urlComponents = URLComponents(string: "https://www.googleapis.com/youtube/v3/liveChat/messages")!
        urlComponents.queryItems = [
            URLQueryItem(name: "liveChatId", value: chatId),
            URLQueryItem(name: "part", value: "snippet,authorDetails"),
            URLQueryItem(name: "key", value: apiKey),
        ]

        if let pageToken = nextPageToken {
            urlComponents.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
        }

        guard let url = urlComponents.url else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                logger.error("YouTube API error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }

            let result = try JSONDecoder().decode(YouTubeChatResponse.self, from: data)
            nextPageToken = result.nextPageToken

            // Respect YouTube's recommended polling interval
            if let pollingMs = result.pollingIntervalMillis {
                pollingInterval = max(Double(pollingMs) / 1000.0, 5.0)
            }

            for item in result.items {
                let snippet = item.snippet
                let author = item.authorDetails

                let chatMsg = ChatMessage(
                    id: item.id,
                    platform: "youtube",
                    username: author.channelId,
                    displayName: author.displayName,
                    content: snippet.displayMessage,
                    badges: author.badges,
                    isHighlighted: snippet.type == "superChatEvent"
                )

                chatContinuation?.yield(chatMsg)

                // Handle super chats as donation events
                if snippet.type == "superChatEvent",
                   let details = snippet.superChatDetails
                {
                    let event = StreamEvent(
                        platform: "youtube",
                        type: .donation,
                        username: author.channelId,
                        displayName: author.displayName,
                        message: details.userComment,
                        amount: Double(details.amountMicros) / 1_000_000.0
                    )
                    eventContinuation?.yield(event)
                }

                // Handle new member events
                if snippet.type == "newSponsorEvent" {
                    let event = StreamEvent(
                        platform: "youtube",
                        type: .subscribe,
                        username: author.channelId,
                        displayName: author.displayName
                    )
                    eventContinuation?.yield(event)
                }
            }
        } catch {
            logger.error("YouTube chat poll error: \(error.localizedDescription)")
        }
    }
}

// MARK: - YouTube API Response Models

private struct YouTubeChatResponse: Decodable {
    let nextPageToken: String?
    let pollingIntervalMillis: Int?
    let items: [YouTubeChatItem]
}

private struct YouTubeChatItem: Decodable {
    let id: String
    let snippet: YouTubeChatSnippet
    let authorDetails: YouTubeChatAuthor
}

private struct YouTubeChatSnippet: Decodable {
    let type: String
    let displayMessage: String
    let publishedAt: String
    let superChatDetails: SuperChatDetails?

    struct SuperChatDetails: Decodable {
        let amountMicros: Int64
        let currency: String
        let userComment: String?
    }
}

private struct YouTubeChatAuthor: Decodable {
    let channelId: String
    let displayName: String
    let isChatOwner: Bool
    let isChatModerator: Bool
    let isChatSponsor: Bool

    var badges: [String] {
        var result: [String] = []
        if isChatOwner { result.append("owner") }
        if isChatModerator { result.append("moderator") }
        if isChatSponsor { result.append("member") }
        return result
    }
}
