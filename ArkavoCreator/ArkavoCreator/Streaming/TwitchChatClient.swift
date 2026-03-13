//
//  TwitchChatClient.swift
//  ArkavoCreator
//
//  Connects to Twitch IRC over WebSocket for real-time chat messages.
//  Uses existing TwitchAuthClient OAuth token for authentication.
//

import Foundation
import OSLog

/// Twitch chat client using WebSocket IRC protocol
@MainActor
final class TwitchChatClient: StreamContextProvider {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.arkavo.creator", category: "TwitchChat")
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    private var chatContinuation: AsyncStream<ChatMessage>.Continuation?
    private var eventContinuation: AsyncStream<StreamEvent>.Continuation?

    /// OAuth token for authentication (from TwitchAuthClient)
    var oauthToken: String?

    /// Channel to join (username, without #)
    var channel: String?

    /// Our bot/user username
    var username: String?

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
        guard let token = oauthToken, let channel = channel else {
            logger.error("Missing OAuth token or channel")
            return
        }

        let nick = username ?? "justinfan12345"  // Anonymous if no username

        let url = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()

        // Authenticate
        try await send("PASS oauth:\(token)")
        try await send("NICK \(nick)")

        // Request tags for badges, emotes, etc.
        try await send("CAP REQ :twitch.tv/tags twitch.tv/commands")

        // Join channel
        try await send("JOIN #\(channel.lowercased())")

        isConnected = true
        logger.info("Connected to Twitch chat: #\(channel)")

        // Start receive loop
        Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() async {
        isConnected = false
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        chatContinuation?.finish()
        eventContinuation?.finish()
        logger.info("Disconnected from Twitch chat")
    }

    // MARK: - IRC Parsing

    private func receiveLoop() async {
        guard let ws = webSocket else { return }

        while isConnected {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    for line in text.components(separatedBy: "\r\n") where !line.isEmpty {
                        handleIRCLine(line)
                    }
                case .data:
                    break // IRC is text-based
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    logger.error("WebSocket receive error: \(error.localizedDescription)")
                    isConnected = false
                }
                break
            }
        }
    }

    private func handleIRCLine(_ line: String) {
        // Handle PING/PONG keepalive
        if line.hasPrefix("PING") {
            Task { try? await send("PONG :tmi.twitch.tv") }
            return
        }

        // Parse PRIVMSG (chat messages)
        // Format: @tags :user!user@user.tmi.twitch.tv PRIVMSG #channel :message
        guard line.contains("PRIVMSG") else { return }

        let parsed = parseIRCMessage(line)
        guard let displayName = parsed.tags["display-name"],
              let msgBody = parsed.trailing
        else { return }

        let username = parsed.prefix?.components(separatedBy: "!").first ?? displayName

        // Extract badges
        var badges: [String] = []
        if let badgeStr = parsed.tags["badges"] {
            badges = badgeStr.components(separatedBy: ",").map {
                $0.components(separatedBy: "/").first ?? $0
            }
        }

        let isHighlighted = parsed.tags["msg-id"] == "highlighted-message"

        let chatMsg = ChatMessage(
            id: parsed.tags["id"] ?? UUID().uuidString,
            platform: "twitch",
            username: username,
            displayName: displayName,
            content: msgBody,
            badges: badges,
            isHighlighted: isHighlighted
        )

        chatContinuation?.yield(chatMsg)

        // Check for bits (cheer events)
        if let bitsStr = parsed.tags["bits"], let bits = Int(bitsStr) {
            let event = StreamEvent(
                platform: "twitch",
                type: .cheer,
                username: username,
                displayName: displayName,
                message: msgBody,
                amount: Double(bits)
            )
            eventContinuation?.yield(event)
        }
    }

    // MARK: - IRC Message Parser

    private struct IRCMessage {
        var tags: [String: String] = [:]
        var prefix: String?
        var command: String = ""
        var params: [String] = []
        var trailing: String?
    }

    private func parseIRCMessage(_ raw: String) -> IRCMessage {
        var msg = IRCMessage()
        var remaining = raw

        // Parse tags (@key=value;key=value)
        if remaining.hasPrefix("@") {
            remaining.removeFirst()
            if let spaceIndex = remaining.firstIndex(of: " ") {
                let tagString = String(remaining[..<spaceIndex])
                remaining = String(remaining[remaining.index(after: spaceIndex)...])

                for pair in tagString.components(separatedBy: ";") {
                    let parts = pair.components(separatedBy: "=")
                    if parts.count >= 2 {
                        msg.tags[parts[0]] = parts[1]
                    } else if parts.count == 1 {
                        msg.tags[parts[0]] = ""
                    }
                }
            }
        }

        // Parse prefix (:nick!user@host)
        if remaining.hasPrefix(":") {
            remaining.removeFirst()
            if let spaceIndex = remaining.firstIndex(of: " ") {
                msg.prefix = String(remaining[..<spaceIndex])
                remaining = String(remaining[remaining.index(after: spaceIndex)...])
            }
        }

        // Parse command and params
        if let colonIndex = remaining.firstIndex(of: ":") {
            let beforeTrailing = String(remaining[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            msg.trailing = String(remaining[remaining.index(after: colonIndex)...])

            let parts = beforeTrailing.components(separatedBy: " ").filter { !$0.isEmpty }
            if let first = parts.first {
                msg.command = first
                msg.params = Array(parts.dropFirst())
            }
        } else {
            let parts = remaining.components(separatedBy: " ").filter { !$0.isEmpty }
            if let first = parts.first {
                msg.command = first
                msg.params = Array(parts.dropFirst())
            }
        }

        return msg
    }

    // MARK: - Send

    private func send(_ text: String) async throws {
        try await webSocket?.send(.string(text))
    }
}
