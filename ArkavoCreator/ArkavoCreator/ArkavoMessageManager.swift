import Foundation
import SwiftUI
import ArkavoSocial
import Combine

// MARK: - Message Models

struct ArkavoMessage: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let data: Data
    var status: MessageStatus
    var retryCount: Int
    var lastRetryDate: Date?
    
    enum MessageStatus: String, Codable {
        case pending
        case replayed
        case failed
        
        var icon: String {
            switch self {
            case .pending: "clock"
            case .replayed: "checkmark.circle"
            case .failed: "exclamationmark.triangle"
            }
        }
        
        var color: Color {
            switch self {
            case .pending: return .yellow
            case .replayed: return .green
            case .failed: return .red
            }
        }
    }
}

// MARK: - Message Manager

@MainActor
class ArkavoMessageManager: ObservableObject {
    @Published var messages: [ArkavoMessage] = []
    private var timers: [UUID: Timer] = [:]
    private let fileManager = FileManager.default
    private let client: ArkavoClient
    private let messageDirectory: URL
    private let replayInterval: TimeInterval = 2.2
    private let maxRetries = 3
    private var relayManager: WebSocketRelayManager?
    
    init(client: ArkavoClient) {
        self.client = client
        
        // Set up message directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        messageDirectory = appSupport.appendingPathComponent("ArkavoMessages", isDirectory: true)
        print(messageDirectory)
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: messageDirectory, withIntermediateDirectories: true)
        
        // Load existing messages and initialize relay
        loadMessages()
        initializeRelay()
    }
    
    // MARK: - Message Handling
    
    func handleMessage(_ data: Data) {
        // Only cache and manage type 0x05 messages
        guard data.first == 0x05 else { return }
        
        // 1. Record message from main WebSocket
        let message = ArkavoMessage(
            id: UUID(),
            timestamp: Date(),
            data: data,
            status: .pending,
            retryCount: 0
        )
        
        // 2. Store to filesystem
        messages.append(message)
        saveMessage(message)
        
        // 3. Forward to local WebSocket server
        Task {
            try await relayMessage(message)
        }
    }
    
    // MARK: - Filesystem Operations
    
    private func saveMessage(_ message: ArkavoMessage) {
        let encoder = JSONEncoder()
        let fileURL = messageDirectory.appendingPathComponent("\(message.id.uuidString).json")
        print(fileURL)
        
        do {
            let data = try encoder.encode(message)
            try data.write(to: fileURL)
            print("Message saved to filesystem: \(message.id)")
        } catch {
            print("Error saving message: \(error)")
        }
    }
    
    private func loadMessages() {
        do {
            let files = try fileManager.contentsOfDirectory(
                at: messageDirectory,
                includingPropertiesForKeys: nil
            )
            
            let decoder = JSONDecoder()
            messages = try files.compactMap { fileURL in
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(ArkavoMessage.self, from: data)
            }
            .sorted { $0.timestamp > $1.timestamp }
            
            print("Loaded \(messages.count) messages from filesystem")
        } catch {
            print("Error loading messages: \(error)")
        }
    }
    
    // MARK: - Relay Operations
    
    private func initializeRelay() {
        Task {
            do {
                relayManager = WebSocketRelayManager()
                try await relayManager?.connect()
                print("Local WebSocket relay initialized")
                
                // Relay existing messages
                for message in messages {
                    try await relayMessage(message)
                }
            } catch {
                print("Failed to initialize relay: \(error)")
            }
        }
    }
    
    private func relayMessage(_ message: ArkavoMessage) async throws {
        guard let relayManager = relayManager else {
            throw RelayError.notConnected
        }
        
        try await relayManager.relayMessage(message.data)
        print("Message relayed to local WebSocket: \(message.id)")
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        // Stop all timers
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}

// MARK: - Delegate Chain

protocol ArkavoMessageHandler: AnyObject {
    func handleClientMessage(_ client: ArkavoClient, message: Data)
    func handleClientState(_ client: ArkavoClient, state: ArkavoClientState)
    func handleClientError(_ client: ArkavoClient, error: Error)
}

class ArkavoMessageChainDelegate: NSObject, ArkavoClientDelegate {
    private let messageManager: ArkavoMessageManager
    private weak var nextDelegate: ArkavoClientDelegate?
    
    init(client: ArkavoClient, existingDelegate: ArkavoClientDelegate?) {
        self.messageManager = ArkavoMessageManager(client: client)
        self.nextDelegate = existingDelegate
        super.init()
    }
    
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        // Forward to next delegate
        nextDelegate?.clientDidChangeState(client, state: state)
    }
    
    func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        // Handle type 0x06 messages
        Task { @MainActor in
            if message.first == 0x06 {
                messageManager.handleMessage(message)
            }
            // Forward all messages to next delegate
            nextDelegate?.clientDidReceiveMessage(client, message: message)
        }
    }
    
    func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        // Forward to next delegate
        nextDelegate?.clientDidReceiveError(client, error: error)
    }
    
    func getMessageManager() -> ArkavoMessageManager {
        messageManager
    }
    
    func updateNextDelegate(_ delegate: ArkavoClientDelegate?) {
        nextDelegate = delegate
    }
}
