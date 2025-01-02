import Foundation

// WebSocket Relay Manager
class WebSocketRelayManager {
    private var webSocket: URLSessionWebSocketTask?
    private let localWebSocketURL = URL(string: "ws://localhost:8080")!
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
    }
    
    func connect() async throws {
        // Create WebSocket connection to localhost
        let request = URLRequest(url: localWebSocketURL)
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        
        // Send initial ping to verify connection
        try await ping()
        print("Local WebSocket relay connected successfully")
        
        // Start listening for messages
        receiveMessages()
    }
    
    private func ping() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            webSocket?.sendPing { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                print("Local WebSocket received: \(message)")
                // Continue listening
                self?.receiveMessages()
            case .failure(let error):
                print("Local WebSocket error: \(error)")
            }
        }
    }
    
    func relayMessage(_ data: Data) async throws {
        print("Relaying message to localhost:8080")
        try await webSocket?.send(.data(data))
    }
    
    func disconnect() {
        webSocket?.cancel()
        webSocket = nil
    }
}
