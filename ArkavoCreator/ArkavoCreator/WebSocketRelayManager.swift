import Foundation

// WebSocket Relay Manager - Now an Actor
actor WebSocketRelayManager {
    // webSocket is now isolated by the actor
    private var webSocket: URLSessionWebSocketTask?
    private let localWebSocketURL = URL(string: "ws://localhost:8080")!
    // URLSession is Sendable and immutable after initialization
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        // URLSession delegate queue can be used for more control, but default is fine here.
        // The delegate methods will run on the specified queue, not the actor's executor.
        // However, we are not using a delegate here.
        session = URLSession(configuration: config)
    }

    func connect() async throws {
        // Create WebSocket connection to localhost
        let request = URLRequest(url: localWebSocketURL)
        // Accessing actor state (webSocket)
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()

        // Send initial ping to verify connection
        // Calls to actor methods are implicitly on the actor's executor
        try await ping()
        print("Local WebSocket relay connected successfully")

        // Start listening for messages
        // Calls to actor methods are implicitly on the actor's executor
        receiveMessages()
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
            print("Local WebSocket received: \(message)")
            // Handle the message (e.g., relay it)

            // Continue listening for the next message by calling receiveMessages again
            // This call is now safely within the actor's context
            receiveMessages()
        case let .failure(error):
            // Handle disconnection or errors
            print("Local WebSocket error: \(error)")
            // Consider implementing reconnection logic or error handling
            // Call disconnect safely within the actor's context
            disconnect() // Example: disconnect on error
        }
    }

    // This method accesses actor state (webSocket)
    func relayMessage(_ data: Data) async throws {
        print("Relaying message to localhost:8080")
        // Access webSocket safely within the actor
        guard let socket = webSocket else {
            // Handle error: not connected or already disconnected
            throw URLError(.networkConnectionLost) // Or a custom error
        }
        try await socket.send(.data(data))
    }

    // This method accesses actor state (webSocket)
    func disconnect() {
        // Access webSocket safely within the actor
        let socketToCancel = webSocket
        webSocket = nil // Set to nil before cancelling to prevent race conditions on access
        socketToCancel?.cancel(with: .goingAway, reason: nil)
        print("Local WebSocket relay disconnected.")
    }

    // Deinit runs on the actor's executor
    deinit {
        // Access webSocket safely within the actor
        let socketToCancel = webSocket
        webSocket = nil
        socketToCancel?.cancel(with: .goingAway, reason: nil)
        print("Local WebSocket relay deinitialized and disconnected.")
    }
}
