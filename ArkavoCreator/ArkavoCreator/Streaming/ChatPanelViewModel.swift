import Foundation

@MainActor
@Observable
final class ChatPanelViewModel {
    var messages: [ChatMessage] = []
    var isConnected: Bool = false
    var error: String?

    private var chatClient: TwitchChatClient?
    private var listenerTask: Task<Void, Never>?

    private static let maxMessages = 200

    func connect(twitchClient: TwitchAuthClient) {
        guard twitchClient.isAuthenticated,
              let token = twitchClient.accessToken,
              let channel = twitchClient.username else {
            error = "Not authenticated with Twitch"
            return
        }

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
    }

    func disconnect() {
        listenerTask?.cancel()
        listenerTask = nil
        Task {
            await chatClient?.disconnect()
        }
        chatClient = nil
        isConnected = false
    }
}
