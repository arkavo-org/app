import Foundation

@MainActor
@Observable
final class ChatPanelViewModel {
    var messages: [ChatMessage] = []
    var recentEvents: [StreamEvent] = []
    var isConnected: Bool = false
    var error: String?

    private var chatClient: TwitchChatClient?
    private var eventSubClient: TwitchEventSubClient?
    private var listenerTask: Task<Void, Never>?
    private var eventListenerTask: Task<Void, Never>?

    private static let maxMessages = 200
    private static let maxEvents = 50

    func connect(twitchClient: TwitchAuthClient) {
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
        chatClient = client

        listenerTask = Task {
            do {
                try await client.connect()
                isConnected = true
                error = nil

                for await message in client.chatMessages {
                    messages.append(message)
                    if messages.count > Self.maxMessages {
                        messages.removeFirst(messages.count - Self.maxMessages)
                    }
                }
                // Stream ended
                isConnected = false
            } catch {
                self.error = error.localizedDescription
                isConnected = false
            }
        }

        // Connect EventSub for follows, subs, raids, cheers
        let eventSub = TwitchEventSubClient(
            clientId: twitchClient.clientId,
            accessToken: { [weak twitchClient] in twitchClient?.accessToken },
            userId: { [weak twitchClient] in twitchClient?.userId }
        )
        eventSubClient = eventSub

        eventListenerTask = Task {
            await eventSub.connect()

            for await event in eventSub.events {
                recentEvents.append(event)
                if recentEvents.count > Self.maxEvents {
                    recentEvents.removeFirst(recentEvents.count - Self.maxEvents)
                }
            }
        }
    }

    func disconnect() {
        listenerTask?.cancel()
        listenerTask = nil
        eventListenerTask?.cancel()
        eventListenerTask = nil
        Task {
            await chatClient?.disconnect()
        }
        chatClient = nil
        eventSubClient?.disconnect()
        eventSubClient = nil
        isConnected = false
    }
}
