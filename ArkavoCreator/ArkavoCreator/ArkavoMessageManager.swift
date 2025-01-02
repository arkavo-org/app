import Foundation
import SwiftUICore
import ArkavoSocial

// First, let's modify the ArkavoMessageChainDelegate to properly handle type 0x05 messages
class ArkavoMessageChainDelegate: NSObject, ArkavoClientDelegate {
    private let messageManager: ArkavoMessageManager
    private weak var nextDelegate: ArkavoClientDelegate?
    
    init(client: ArkavoClient, existingDelegate: ArkavoClientDelegate?) {
        self.messageManager = ArkavoMessageManager(client: client)
        self.nextDelegate = existingDelegate
        super.init()
    }
    
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        nextDelegate?.clientDidChangeState(client, state: state)
    }
    
    func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        // Handle type 0x05 messages
        Task { @MainActor in
            if message.first == 0x05 {
                messageManager.handleMessage(message)
            }
            // Forward all messages to next delegate
            nextDelegate?.clientDidReceiveMessage(client, message: message)
        }
    }
    
    func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        nextDelegate?.clientDidReceiveError(client, error: error)
    }
    
    func getMessageManager() -> ArkavoMessageManager {
        messageManager
    }
    
    func updateNextDelegate(_ delegate: ArkavoClientDelegate?) {
        nextDelegate = delegate
    }
}

@MainActor
class ArkavoMessageManager: ObservableObject {
    @Published var messages: [ArkavoMessage] = []
    private var relayManager: WebSocketRelayManager?
    private let fileManager = FileManager.default
    private let messageDirectory: URL
    
    init(client: ArkavoClient) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        messageDirectory = appSupport.appendingPathComponent("ArkavoMessages", isDirectory: true)
        
        // Create directory if it doesn't exist
        do {
            try fileManager.createDirectory(at: messageDirectory,
                                         withIntermediateDirectories: true)
            print("Message directory created/verified at: \(messageDirectory.path)")
        } catch {
            print("Error creating message directory: \(error)")
        }
        
        // Initialize relay manager and connect
        initializeRelay()
        
        // Load existing messages
        loadMessages()
    }
    
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
    
    func handleMessage(_ data: Data) {
        guard data.first == 0x05 else { return }
        
        // Create message
        let message = ArkavoMessage(
            id: UUID(),
            timestamp: Date(),
            data: data,
            status: .pending,
            retryCount: 0,
            lastRetryDate: nil
        )
        
        // Store to filesystem
        messages.append(message)
        saveMessage(message)
        
        // Forward to local WebSocket server
        Task {
            try await relayMessage(message)
        }
    }
    
    private func relayMessage(_ message: ArkavoMessage) async throws {
        guard let relayManager = relayManager else {
            print("Relay manager not initialized")
            return
        }
        
        do {
            try await relayManager.relayMessage(message.data)
            print("Message \(message.id) relayed to localhost")
        } catch {
            print("Failed to relay message \(message.id): \(error)")
        }
    }
    
    private func saveMessage(_ message: ArkavoMessage) {
        let encoder = JSONEncoder()
        let fileURL = messageDirectory.appendingPathComponent("\(message.id.uuidString).json")
        
        do {
            let data = try encoder.encode(message)
            try data.write(to: fileURL)
            print("Successfully saved message \(message.id) to \(fileURL.path)")
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
                guard fileURL.pathExtension == "json" else { return nil }
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(ArkavoMessage.self, from: data)
            }
            .sorted { $0.timestamp > $1.timestamp }
            
            print("Loaded \(messages.count) messages from filesystem")
        } catch {
            print("Error loading messages: \(error)")
        }
    }
}

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
            case .pending: return "clock"
            case .replayed: return "checkmark.circle"
            case .failed: return "exclamationmark.triangle"
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
    
    // Custom coding keys to ensure proper encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, timestamp, data, status, retryCount, lastRetryDate
    }
    
    // Custom encoding to handle Data type
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(data.base64EncodedString(), forKey: .data)
        try container.encode(status, forKey: .status)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encode(lastRetryDate, forKey: .lastRetryDate)
    }
    
    // Standard initializer
    init(id: UUID, timestamp: Date, data: Data, status: MessageStatus, retryCount: Int, lastRetryDate: Date?) {
        self.id = id
        self.timestamp = timestamp
        self.data = data
        self.status = status
        self.retryCount = retryCount
        self.lastRetryDate = lastRetryDate
    }

    // Custom decoding to handle Data type
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        let base64String = try container.decode(String.self, forKey: .data)
        guard let decodedData = Data(base64Encoded: base64String) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.data],
                    debugDescription: "Could not decode base64 string to Data"
                )
            )
        }
        data = decodedData
        status = try container.decode(MessageStatus.self, forKey: .status)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        lastRetryDate = try container.decodeIfPresent(Date.self, forKey: .lastRetryDate)
    }
}
