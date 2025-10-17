import Foundation
import Combine

/// WebSocket transport for A2A agent communication using JSON-RPC 2.0
@available(iOS 13.0, macOS 10.15, *)
public actor AgentWebSocketTransport {
    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var endpoint: AgentEndpoint?
    private var isConnected: Bool = false

    // Request/response correlation
    private var pendingRequests: [String: CheckedContinuation<AgentResponse, Error>] = [:]

    // Configuration
    private let timeoutMs: UInt64
    private let requireTLS: Bool

    // Reader task
    private var readerTask: Task<Void, Never>?

    // MARK: - Initialization

    public init(timeoutMs: UInt64 = 30000, requireTLS: Bool = false) {
        self.timeoutMs = timeoutMs
        self.requireTLS = requireTLS
    }

    // MARK: - Connection Management

    /// Connect to an agent endpoint
    public func connect(to endpoint: AgentEndpoint) async throws {
        guard endpoint.url.hasPrefix("ws://") || endpoint.url.hasPrefix("wss://") else {
            throw AgentError.invalidEndpoint("WebSocket URL must start with ws:// or wss://")
        }

        if requireTLS && endpoint.url.hasPrefix("ws://") {
            throw AgentError.tlsError("TLS is required but URL uses ws:// instead of wss://")
        }

        guard let url = URL(string: endpoint.url) else {
            throw AgentError.invalidEndpoint("Invalid URL: \(endpoint.url)")
        }

        // Create URL session configuration
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = TimeInterval(timeoutMs / 1000)
        configuration.timeoutIntervalForResource = TimeInterval(timeoutMs / 1000)

        let session = URLSession(configuration: configuration)
        self.session = session

        // Create WebSocket task
        let task = session.webSocketTask(with: url)
        self.webSocketTask = task
        self.endpoint = endpoint

        // Start receiving messages
        startReceiving(task: task)

        // Resume the task
        task.resume()

        self.isConnected = true
    }

    /// Close the connection
    public func close() async {
        readerTask?.cancel()
        readerTask = nil

        if let task = webSocketTask {
            task.cancel(with: .goingAway, reason: nil)
        }

        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        endpoint = nil
        isConnected = false

        // Cancel all pending requests
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: AgentError.connectionFailed("Connection closed"))
        }
        pendingRequests.removeAll()
    }

    /// Check if connected
    public func getIsConnected() -> Bool {
        isConnected
    }

    // MARK: - Request/Response

    /// Send a JSON-RPC request and await the response
    public func sendRequest(_ request: AgentRequest) async throws -> AgentResponse {
        guard isConnected, let task = webSocketTask else {
            throw AgentError.notConnected
        }

        // Encode request to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw AgentError.webSocketError("Failed to encode request as UTF-8")
        }

        // Send the message
        let message = URLSessionWebSocketTask.Message.string(jsonString)
        try await task.send(message)

        // Wait for response with timeout
        return try await withTimeout(ms: timeoutMs) {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await self.registerPendingRequest(id: request.id, continuation: continuation)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func startReceiving(task: URLSessionWebSocketTask) {
        readerTask = Task {
            while !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    await handleMessage(message)
                } catch {
                    // Connection closed or error
                    await handleError(error)
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message else {
            return
        }

        do {
            let data = Data(text.utf8)
            let decoder = JSONDecoder()
            let response = try decoder.decode(AgentResponse.self, from: data)

            // Find and resume the pending request
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                continuation.resume(returning: response)
            }
        } catch {
            print("Failed to decode response: \(error)")
        }
    }

    private func handleError(_ error: Error) async {
        isConnected = false

        // Cancel all pending requests with error
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: AgentError.webSocketError(error.localizedDescription))
        }
        pendingRequests.removeAll()
    }

    private func registerPendingRequest(id: String, continuation: CheckedContinuation<AgentResponse, Error>) {
        pendingRequests[id] = continuation
    }

    private func withTimeout<T: Sendable>(ms: UInt64, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: ms * 1_000_000)
                throw AgentError.timeout(ms)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
