import Foundation

// WebSocket Relay Manager - Now an Actor
actor WebSocketRelayManager {
    // webSocket is now isolated by the actor
    private var webSocket: URLSessionWebSocketTask?
    #if DEBUG
        private let localWebSocketURL = URL(string: "ws://localhost:8080")!
    #endif
    // URLSession is Sendable and immutable after initialization
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
    }

    func connect() async throws {
        #if DEBUG
            // Create WebSocket connection to localhost
            let request = URLRequest(url: localWebSocketURL)
            webSocket = session.webSocketTask(with: request)
            webSocket?.resume()

            try await ping()
            debugLog("Local WebSocket relay connected successfully")

            receiveMessages()
        #endif
    }

    // This method accesses actor state (webSocket)
    private func ping() async throws {
        guard let socket = webSocket else {
            throw URLError(.badServerResponse) // Or a more specific error
        }
        // Explicitly specify Void return type for the continuation
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    // This method accesses actor state (webSocket) and calls itself recursively
    private func receiveMessages() {
        // Ensure webSocket is accessed safely within the actor
        guard let socket = webSocket else { return }

        // The completion handler of receive runs on a background thread/queue.
        // We need to hop back to the actor's executor to safely access actor state.
        socket.receive { result in
            // Use Task to bridge back to the actor's context
            Task {
                await self.handleReceivedMessage(result)
            }
        }
    }

    // Helper function to process the message result on the actor's executor
    private func handleReceivedMessage(_ result: Result<URLSessionWebSocketTask.Message, Error>) async {
        switch result {
        case let .success(message):
            debugLog("Local WebSocket received: \(message)")
            // Handle the message (e.g., relay it)

            // Continue listening for the next message by calling receiveMessages again
            // This call is now safely within the actor's context
            receiveMessages()
        case let .failure(error):
            // Handle disconnection or errors
            debugLog("Local WebSocket error: \(error)")
            // Consider implementing reconnection logic or error handling
            // Call disconnect safely within the actor's context
            disconnect() // Example: disconnect on error
        }
    }

    // This method accesses actor state (webSocket)
    func relayMessage(_ data: Data) async throws {
        #if DEBUG
            debugLog("Relaying message to localhost:8080")
            guard let socket = webSocket else {
                throw URLError(.networkConnectionLost)
            }
            try await socket.send(.data(data))
        #endif
    }

    // This method accesses actor state (webSocket)
    func disconnect() {
        // Access webSocket safely within the actor
        let socketToCancel = webSocket
        webSocket = nil // Set to nil before cancelling to prevent race conditions on access
        socketToCancel?.cancel(with: .goingAway, reason: nil)
        debugLog("Local WebSocket relay disconnected.")
    }

    // Deinit runs on the actor's executor
    deinit {
        // Access webSocket safely within the actor
        let socketToCancel = webSocket
        webSocket = nil
        socketToCancel?.cancel(with: .goingAway, reason: nil)
        debugLog("Local WebSocket relay deinitialized and disconnected.")
    }
}
