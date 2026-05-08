import Foundation
import ArkavoKit

@MainActor
@Observable
final class ChatPanelViewModel {
    var messages: [ChatMessage] = []
    var recentEvents: [StreamEvent] = []
    var connectedPlatforms: Set<String> = []
    var error: String?

    var isConnected: Bool { !connectedPlatforms.isEmpty }

    // Twitch state
    private var twitchChatClient: TwitchChatClient?
    private var twitchEventSubClient: TwitchEventSubClient?
    private var twitchListenerTask: Task<Void, Never>?
    private var twitchEventListenerTask: Task<Void, Never>?

    // YouTube state
    private var youtubePollingTask: Task<Void, Never>?

    private static let maxMessages = 200
    private static let maxEvents = 50

    // MARK: - Twitch

    func connectTwitch(twitchClient: TwitchAuthClient) {
        guard twitchClient.isAuthenticated,
              let token = twitchClient.accessToken,
              let channel = twitchClient.username else {
            error = "Not authenticated with Twitch"
            return
        }

        // Connect IRC chat
        let client = TwitchChatClient()
        client.oauthToken = token
        client.channel = channel
        client.username = twitchClient.username
        twitchChatClient = client

        twitchListenerTask = Task {
            do {
                try await client.connect()
                connectedPlatforms.insert("twitch")
                debugLog("[ChatPanel] Twitch chat connected")

                for await message in client.chatMessages {
                    messages.append(message)
                    if messages.count > Self.maxMessages {
                        messages.removeFirst(messages.count - Self.maxMessages)
                    }
                }
                connectedPlatforms.remove("twitch")
            } catch {
                self.error = "Twitch chat: \(error.localizedDescription)"
                connectedPlatforms.remove("twitch")
            }
        }

        // Connect EventSub
        let eventSub = TwitchEventSubClient(
            clientId: twitchClient.clientId,
            accessToken: { [weak twitchClient] in twitchClient?.accessToken },
            userId: { [weak twitchClient] in twitchClient?.userId },
            ensureValidToken: { [weak twitchClient] in
                await twitchClient?.ensureValidToken() ?? false
            }
        )
        twitchEventSubClient = eventSub

        twitchEventListenerTask = Task {
            await eventSub.connect()

            for await event in eventSub.events {
                recentEvents.append(event)
                if recentEvents.count > Self.maxEvents {
                    recentEvents.removeFirst(recentEvents.count - Self.maxEvents)
                }
            }
        }
    }

    // MARK: - YouTube

    func connectYouTube(youtubeClient: YouTubeClient, broadcastId: String) {
        youtubePollingTask = Task {
            do {
                guard let liveChatId = try await youtubeClient.getLiveChatId(broadcastId: broadcastId) else {
                    error = "No live chat available for this broadcast"
                    return
                }

                connectedPlatforms.insert("youtube")
                debugLog("[ChatPanel] YouTube chat connected (chatId: \(liveChatId))")

                var nextPageToken: String? = nil
                var pollingInterval: TimeInterval = 6.0

                while !Task.isCancelled {
                    do {
                        let result = try await youtubeClient.fetchLiveChatMessages(
                            liveChatId: liveChatId,
                            pageToken: nextPageToken
                        )
                        nextPageToken = result.nextPageToken

                        if let ms = result.pollingIntervalMs {
                            pollingInterval = max(Double(ms) / 1000.0, 5.0)
                        }

                        for item in result.messages {
                            let author = item.authorDetails
                            var badges: [String] = []
                            if author.isChatOwner { badges.append("owner") }
                            if author.isChatModerator { badges.append("moderator") }
                            if author.isChatSponsor { badges.append("member") }

                            let chatMsg = ChatMessage(
                                id: item.id,
                                platform: "youtube",
                                username: author.channelId,
                                displayName: author.displayName,
                                content: item.snippet.displayMessage,
                                badges: badges,
                                isHighlighted: item.snippet.type == "superChatEvent"
                            )
                            messages.append(chatMsg)
                            if messages.count > Self.maxMessages {
                                messages.removeFirst(messages.count - Self.maxMessages)
                            }

                            // Super Chat → donation event
                            if item.snippet.type == "superChatEvent",
                               let details = item.snippet.superChatDetails {
                                let amount = (Double(details.amountMicros) ?? 0) / 1_000_000.0
                                let event = StreamEvent(
                                    platform: "youtube",
                                    type: .donation,
                                    username: author.channelId,
                                    displayName: author.displayName,
                                    message: details.userComment,
                                    amount: amount
                                )
                                recentEvents.append(event)
                                if recentEvents.count > Self.maxEvents {
                                    recentEvents.removeFirst(recentEvents.count - Self.maxEvents)
                                }
                            }

                            if item.snippet.type == "newSponsorEvent" {
                                let event = StreamEvent(
                                    platform: "youtube",
                                    type: .subscribe,
                                    username: author.channelId,
                                    displayName: author.displayName
                                )
                                recentEvents.append(event)
                                if recentEvents.count > Self.maxEvents {
                                    recentEvents.removeFirst(recentEvents.count - Self.maxEvents)
                                }
                            }
                        }
                    } catch {
                        debugLog("[ChatPanel] YouTube chat poll error: \(error.localizedDescription)")
                    }

                    try? await Task.sleep(for: .seconds(pollingInterval))
                }
            } catch {
                self.error = "YouTube chat: \(error.localizedDescription)"
            }
            connectedPlatforms.remove("youtube")
        }
    }

    // MARK: - Backward Compat

    func connect(twitchClient: TwitchAuthClient) {
        connectTwitch(twitchClient: twitchClient)
    }

    func connect(youtubeClient: YouTubeClient, broadcastId: String) {
        connectYouTube(youtubeClient: youtubeClient, broadcastId: broadcastId)
    }

    // MARK: - Disconnect

    func disconnect(platform: String? = nil) {
        if platform == nil || platform == "twitch" {
            twitchListenerTask?.cancel()
            twitchListenerTask = nil
            twitchEventListenerTask?.cancel()
            twitchEventListenerTask = nil
            Task { await twitchChatClient?.disconnect() }
            twitchChatClient = nil
            twitchEventSubClient?.disconnect()
            twitchEventSubClient = nil
            connectedPlatforms.remove("twitch")
        }

        if platform == nil || platform == "youtube" {
            youtubePollingTask?.cancel()
            youtubePollingTask = nil
            connectedPlatforms.remove("youtube")
        }
    }
}
