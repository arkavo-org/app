//
//  TwitchEventSubClient.swift
//  ArkavoCreator
//
//  Twitch EventSub WebSocket client for real-time channel events.
//  Receives follows, subscriptions, cheers, raids, and gift subs
//  via wss://eventsub.wss.twitch.tv/ws and yields them as StreamEvents.
//

import Foundation
import OSLog

/// Twitch EventSub WebSocket client
@MainActor
final class TwitchEventSubClient {
    private let logger = Logger(subsystem: "com.arkavo.creator", category: "TwitchEventSub")

    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var sessionId: String?
    private var keepaliveTimeoutSeconds: Int = 30
    private var keepaliveTimer: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    private var eventContinuation: AsyncStream<StreamEvent>.Continuation?
    private(set) var events: AsyncStream<StreamEvent>!

    /// OAuth token and client ID for Helix API subscription calls
    private let accessToken: () -> String?
    private let clientId: String
    private let userId: () -> String?
    /// Called before subscription creation to ensure the token is valid
    private let ensureValidToken: () async -> Bool

    private(set) var isConnected = false

    /// Event types to subscribe to once the session is established
    private let subscriptionTypes: [(type: String, version: String, scope: String?)] = [
        ("channel.follow", "2", "moderator:read:followers"),
        ("channel.subscribe", "1", "channel:read:subscriptions"),
        ("channel.subscription.gift", "1", "channel:read:subscriptions"),
        ("channel.cheer", "1", "bits:read"),
        ("channel.raid", "1", nil),
    ]

    init(clientId: String, accessToken: @escaping () -> String?, userId: @escaping () -> String?, ensureValidToken: @escaping () async -> Bool = { true }) {
        self.clientId = clientId
        self.accessToken = accessToken
        self.userId = userId
        self.ensureValidToken = ensureValidToken

        self.events = AsyncStream { continuation in
            self.eventContinuation = continuation
        }
    }

    // MARK: - Connection

    func connect() async {
        guard !isConnected else { return }

        let url = URL(string: "wss://eventsub.wss.twitch.tv/ws")!
        let session = URLSession(configuration: .default)
        self.urlSession = session
        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()

        isConnected = true
        logger.info("Connecting to Twitch EventSub WebSocket")

        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        isConnected = false
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        sessionId = nil
        eventContinuation?.finish()
        logger.info("Disconnected from Twitch EventSub")
    }

    // MARK: - Receive Loop

    private func receiveLoop() async {
        guard let ws = webSocket else { return }

        while isConnected, !Task.isCancelled {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if isConnected {
                    logger.error("EventSub receive error: \(error.localizedDescription)")
                    isConnected = false
                    // Attempt reconnect after a delay
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(5))
                        await self?.reconnect()
                    }
                }
                break
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any],
              let messageType = metadata["message_type"] as? String
        else {
            logger.warning("Failed to parse EventSub message")
            return
        }

        switch messageType {
        case "session_welcome":
            handleWelcome(json)
        case "session_keepalive":
            resetKeepaliveTimer()
        case "notification":
            handleNotification(json)
        case "session_reconnect":
            handleReconnect(json)
        case "revocation":
            if let payload = json["payload"] as? [String: Any],
               let subscription = payload["subscription"] as? [String: Any],
               let type = subscription["type"] as? String {
                logger.warning("Subscription revoked: \(type)")
            }
        default:
            logger.debug("Unknown EventSub message type: \(messageType)")
        }
    }

    // MARK: - Message Handlers

    private func handleWelcome(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let id = session["id"] as? String
        else { return }

        sessionId = id
        if let timeout = session["keepalive_timeout_seconds"] as? Int {
            keepaliveTimeoutSeconds = timeout
        }

        logger.info("EventSub session established: \(id)")
        resetKeepaliveTimer()

        // Subscribe to all event types
        Task { [weak self] in
            await self?.createSubscriptions()
        }
    }

    private func handleNotification(_ json: [String: Any]) {
        guard let metadata = json["metadata"] as? [String: Any],
              let subscriptionType = metadata["subscription_type"] as? String,
              let payload = json["payload"] as? [String: Any],
              let eventData = payload["event"] as? [String: Any]
        else { return }

        guard let event = parseEvent(type: subscriptionType, data: eventData) else { return }
        eventContinuation?.yield(event)
    }

    private func handleReconnect(_ json: [String: Any]) {
        guard let payload = json["payload"] as? [String: Any],
              let session = payload["session"] as? [String: Any],
              let reconnectURL = session["reconnect_url"] as? String
        else { return }

        logger.info("EventSub reconnect requested")
        Task { [weak self] in
            await self?.reconnectTo(urlString: reconnectURL)
        }
    }

    // MARK: - Event Parsing

    private func parseEvent(type: String, data: [String: Any]) -> StreamEvent? {
        switch type {
        case "channel.follow":
            guard let userName = data["user_login"] as? String,
                  let displayName = data["user_name"] as? String
            else { return nil }
            return StreamEvent(
                platform: "twitch",
                type: .follow,
                username: userName,
                displayName: displayName
            )

        case "channel.subscribe":
            let userName = data["user_login"] as? String ?? ""
            let displayName = data["user_name"] as? String ?? userName
            let tier = data["tier"] as? String
            let tierAmount: Double? = switch tier {
            case "1000": 4.99
            case "2000": 9.99
            case "3000": 24.99
            default: nil
            }
            return StreamEvent(
                platform: "twitch",
                type: .subscribe,
                username: userName,
                displayName: displayName,
                amount: tierAmount
            )

        case "channel.subscription.gift":
            let userName = data["user_login"] as? String ?? ""
            let displayName = data["user_name"] as? String ?? userName
            let total = data["total"] as? Int ?? 1
            let tier = data["tier"] as? String
            let perSub: Double = switch tier {
            case "2000": 9.99
            case "3000": 24.99
            default: 4.99
            }
            return StreamEvent(
                platform: "twitch",
                type: .giftSub,
                username: userName,
                displayName: displayName,
                message: "\(total) gift sub(s)",
                amount: perSub * Double(total)
            )

        case "channel.cheer":
            let userName = data["user_login"] as? String ?? "Anonymous"
            let displayName = data["user_name"] as? String ?? userName
            let bits = data["bits"] as? Int ?? 0
            let message = data["message"] as? String
            return StreamEvent(
                platform: "twitch",
                type: .cheer,
                username: userName,
                displayName: displayName,
                message: message,
                amount: Double(bits)
            )

        case "channel.raid":
            let userName = data["from_broadcaster_user_login"] as? String ?? ""
            let displayName = data["from_broadcaster_user_name"] as? String ?? userName
            let viewers = data["viewers"] as? Int ?? 0
            return StreamEvent(
                platform: "twitch",
                type: .raid,
                username: userName,
                displayName: displayName,
                message: "\(viewers) viewers",
                amount: Double(viewers)
            )

        default:
            return nil
        }
    }

    // MARK: - Subscriptions

    private func createSubscriptions() async {
        // Validate / refresh the token before attempting subscriptions
        let tokenValid = await ensureValidToken()
        guard tokenValid,
              let token = accessToken(),
              let broadcasterId = userId(),
              let sessionId
        else {
            logger.error("Cannot create subscriptions: missing or invalid token, userId, or sessionId")
            return
        }

        for sub in subscriptionTypes {
            do {
                try await createSubscription(
                    type: sub.type,
                    version: sub.version,
                    broadcasterId: broadcasterId,
                    token: token,
                    sessionId: sessionId
                )
            } catch {
                logger.error("Failed to subscribe to \(sub.type): \(error.localizedDescription)")
            }
        }
    }

    private func createSubscription(
        type: String,
        version: String,
        broadcasterId: String,
        token: String,
        sessionId: String
    ) async throws {
        var request = URLRequest(url: URL(string: "https://api.twitch.tv/helix/eventsub/subscriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build condition — most events use broadcaster_user_id,
        // channel.follow v2 also needs moderator_user_id,
        // channel.raid uses to_broadcaster_user_id for incoming raids
        var condition: [String: String] = [:]
        if type == "channel.raid" {
            condition["to_broadcaster_user_id"] = broadcasterId
        } else {
            condition["broadcaster_user_id"] = broadcasterId
        }
        if type == "channel.follow" {
            condition["moderator_user_id"] = broadcasterId
        }

        let body: [String: Any] = [
            "type": type,
            "version": version,
            "condition": condition,
            "transport": [
                "method": "websocket",
                "session_id": sessionId,
            ],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TwitchError.apiFailed
        }

        if httpResponse.statusCode == 202 {
            logger.info("Subscribed to \(type)")
        } else {
            let responseBody = String(data: data, encoding: .utf8) ?? "no body"
            logger.error("Subscribe to \(type) failed (\(httpResponse.statusCode)): \(responseBody)")
        }
    }

    // MARK: - Keepalive & Reconnect

    private func resetKeepaliveTimer() {
        keepaliveTimer?.cancel()
        keepaliveTimer = Task { [weak self, keepaliveTimeoutSeconds] in
            // Twitch says connection is dead if no message within keepalive_timeout + 10s
            let timeout = keepaliveTimeoutSeconds + 10
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            await self?.handleKeepaliveTimeout()
        }
    }

    private func handleKeepaliveTimeout() {
        logger.warning("EventSub keepalive timeout — reconnecting")
        Task { [weak self] in
            await self?.reconnect()
        }
    }

    private func reconnect() async {
        disconnect()

        // Re-create the event stream for new consumers
        self.events = AsyncStream { continuation in
            self.eventContinuation = continuation
        }

        try? await Task.sleep(for: .seconds(1))
        await connect()
    }

    private func reconnectTo(urlString: String) async {
        guard let url = URL(string: urlString) else {
            await reconnect()
            return
        }

        // Keep old connection alive until new one sends welcome
        let oldWs = webSocket
        let oldSession = urlSession

        let session = URLSession(configuration: .default)
        self.urlSession = session
        let ws = session.webSocketTask(with: url)
        self.webSocket = ws
        ws.resume()

        // The new connection will send a session_welcome with the same session ID
        // Old connection can be closed after welcome
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }

        // Clean up old connection
        oldWs?.cancel(with: .normalClosure, reason: nil)
        oldSession?.invalidateAndCancel()
    }
}
