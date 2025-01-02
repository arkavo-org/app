import Foundation
import Network

@MainActor
class WebSocketRelayManager {
    private var webSocket: URLSessionWebSocketTask?
    private let session: URLSession
    private let queue = OperationQueue()
    private var isConnected = false
    
    init() {
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config)
    }
    
    func connect() async throws {
        guard !isConnected else { return }
        
        let url = URL(string: "ws://localhost:8080")!
        var request = URLRequest(url: url)
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        
        webSocket = session.webSocketTask(with: request)
        webSocket?.resume()
        isConnected = true
    }
    
    func disconnect() {
        webSocket?.cancel()
        webSocket = nil
        isConnected = false
    }
    
    // Forward a message to the local WebSocket server
    func relayMessage(_ data: Data) async throws {
        guard isConnected, let webSocket = webSocket else {
            throw RelayError.notConnected
        }
        
        try await webSocket.send(.data(data))
    }
}

enum RelayError: Error {
    case notConnected
}
