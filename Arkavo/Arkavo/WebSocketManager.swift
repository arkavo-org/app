import Combine
import CryptoKit
import Foundation
import OpenTDFKit

@MainActor
final class WebSocketManager: ObservableObject {
    // MARK: - Singleton Instance

    static let shared = WebSocketManager()

    // MARK: - Published Properties

    @Published private(set) var webSocket: KASWebSocket?
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published var lastError: String?

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var kasPublicKeyCallback: ((P256.KeyAgreement.PublicKey) -> Void)?
    private var rewrapCallback: ((Data, SymmetricKey?) -> Void)?
    private var customMessageCallback: ((Data) -> Void)?
    private var reconnectTimer: DispatchSourceTimer?
    private let maxReconnectAttempts = 5
    private var reconnectAttempts = 0
    private let reconnectInterval: TimeInterval = 5.0

    // MARK: - Initializer

    private init() {
        // Private initializer to enforce singleton usage
    }

    // MARK: - Public Methods

    /// Sets up the WebSocket with the provided token.
    func setupWebSocket(token: String) {
        guard let url = URL(string: "wss://kas.arkavo.net") else {
            lastError = "Invalid WebSocket URL."
            return
        }

        print("Connecting to: \(url)")
        print("Token: \(token)")

        webSocket = KASWebSocket(kasUrl: url, token: token)

        // Assign existing callbacks to the new WebSocket instance
        if let kasCallback = kasPublicKeyCallback {
            webSocket?.setKASPublicKeyCallback(kasCallback)
        }
        if let rewrapCB = rewrapCallback {
            webSocket?.setRewrapCallback(rewrapCB)
        }
        if customMessageCallback != nil {
            webSocket?.setCustomMessageCallback { [weak self] data in
                self?.customMessageCallback?(data)
            }
        }

        // Observe connection state changes
        webSocket?.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)
    }

    /// Initiates the WebSocket connection.
    func connect() {
        DispatchQueue.main.async {
            self.lastError = nil
        }
        webSocket?.connect()
        startReconnectTimer()
    }

    /// Disconnects the WebSocket and cleans up resources.
    func disconnect() {
        stopReconnectTimer()
        webSocket?.disconnect()
        cancellables.removeAll()
        webSocket = nil
        connectionState = .disconnected
    }

    /// Closes the WebSocket connection gracefully.
    func close() {
        disconnect()
    }

    /// Sets the callback for KAS Public Key.
    func setKASPublicKeyCallback(_ callback: @escaping (P256.KeyAgreement.PublicKey) -> Void) {
        kasPublicKeyCallback = callback
        webSocket?.setKASPublicKeyCallback(callback)
    }

    /// Sets the callback for rewrapping.
    func setRewrapCallback(_ callback: @escaping (Data, SymmetricKey?) -> Void) {
        rewrapCallback = callback
        webSocket?.setRewrapCallback(callback)
    }

    /// Sets the callback for custom messages.
    func setCustomMessageCallback(_ callback: @escaping (Data) -> Void) {
        customMessageCallback = callback
        webSocket?.setCustomMessageCallback { [weak self] data in
            self?.customMessageCallback?(data)
        }
    }

    /// Sends the public key over the WebSocket.
    @discardableResult
    func sendPublicKey() -> Bool {
        guard connectionState == .connected else {
            lastError = "Cannot send public key: WebSocket not connected."
            return false
        }
        webSocket?.sendPublicKey()
        return true
    }

    /// Sends a KAS key message over the WebSocket.
    @discardableResult
    func sendKASKeyMessage() -> Bool {
        guard connectionState == .connected else {
            lastError = "Cannot send KAS key message: WebSocket not connected."
            return false
        }
        webSocket?.sendKASKeyMessage()
        return true
    }

    /// Sends a rewrap message with the provided header.
    func sendRewrapMessage(header: Header) {
        guard connectionState == .connected else {
            lastError = "Cannot send rewrap message: WebSocket not connected."
            return
        }
        webSocket?.sendRewrapMessage(header: header)
    }

    /// Sends a custom message over the WebSocket.
    func sendCustomMessage(_ message: Data, completion: @escaping @Sendable (Error?) -> Void) {
        guard connectionState == .connected else {
            lastError = "Cannot send custom message: WebSocket not connected."
            completion(NSError(domain: "WebSocketManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]))
            return
        }
//        print("sending custom message")
        webSocket?.sendCustomMessage(message, completion: completion)
    }

    // MARK: - Private Methods

    /// Handles changes in the connection state.
    private func handleConnectionStateChange(_ state: WebSocketConnectionState) {
        connectionState = state
        switch state {
        case .connected:
            stopReconnectTimer()
            reconnectAttempts = 0
        case .disconnected:
            lastError = "WebSocket disconnected."
            startReconnectTimer()
        default:
            break
        }
    }

    /// Starts the reconnect timer using DispatchSourceTimer.
    private func startReconnectTimer() {
        stopReconnectTimer()

        reconnectTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        reconnectTimer?.schedule(deadline: .now() + reconnectInterval, repeating: reconnectInterval)
        reconnectTimer?.setEventHandler { [weak self] in
            self?.attemptReconnect()
        }
        reconnectTimer?.resume()
    }

    /// Stops and cancels the reconnect timer.
    private func stopReconnectTimer() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
        reconnectAttempts = 0
    }

    /// Attempts to reconnect to the WebSocket.
    private func attemptReconnect() {
        guard connectionState == .disconnected else { return }

        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            print("Attempting to reconnect... (Attempt \(reconnectAttempts))")
            connect()
        } else {
            print("Max reconnection attempts reached. Please try again later.")
            stopReconnectTimer()
        }
    }
}
