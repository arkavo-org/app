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
    
    init(client: ArkavoClient) {
        self.client = client
        
        // Set up message directory in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        messageDirectory = appSupport.appendingPathComponent("ArkavoMessages", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: messageDirectory, withIntermediateDirectories: true)
        
        // Load existing messages
        loadMessages()
    }
    
    // MARK: - Message Handling
    
    func handleMessage(_ data: Data) {
        guard data.first == 0x06 else { return }
        
        let message = ArkavoMessage(
            id: UUID(),
            timestamp: Date(),
            data: data,
            status: .pending,
            retryCount: 0
        )
        
        messages.append(message)
        saveMessage(message)
        // Reschedule pending messages
        if message.status == .pending || message.status == .replayed {  // Changed to include replayed
            scheduleReplay(for: message)
        }
    }
    
    private func scheduleReplay(for message: ArkavoMessage) {
        print("Scheduling replay for message \(message.id) in \(replayInterval) seconds")
        let timer = Timer.scheduledTimer(withTimeInterval: replayInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.replayMessage(message)
            }
        }
        timers[message.id] = timer
    }

    private func replayMessage(_ message: ArkavoMessage) async {
        guard var updatedMessage = messages.first(where: { $0.id == message.id }),
              updatedMessage.status == .pending || updatedMessage.status == .replayed,  // Changed to include replayed
              updatedMessage.retryCount < maxRetries else {
            return
        }
        
        print("Replaying message \(message.id), attempt \(updatedMessage.retryCount + 1)")
        
        do {
            // Send the message back through the client
            try await client.sendMessage(message.data)
            print("Successfully replayed message \(message.id)")
            
            // Update message status
            updatedMessage.status = .replayed
            updatedMessage.lastRetryDate = Date()
            updateMessage(updatedMessage)
            
            // Schedule next replay - This is key for continuous replay
            scheduleReplay(for: updatedMessage)
            
        } catch {
            print("Failed to replay message \(message.id): \(error)")
            updatedMessage.retryCount += 1
            updatedMessage.lastRetryDate = Date()
            
            if updatedMessage.retryCount >= maxRetries {
                updatedMessage.status = .failed
            } else {
                // Schedule another retry
                scheduleReplay(for: updatedMessage)
            }
            
            updateMessage(updatedMessage)
        }
    }

    // Added new retry functions
    func retryMessage(_ messageId: UUID) async {
        guard let message = messages.first(where: { $0.id == messageId }) else { return }
        await replayMessage(message)
    }

    func retryFailedMessages() async {
        for message in messages where message.status == .failed {
            await replayMessage(message)
        }
    }
      
    // MARK: - Persistence
    
    private func saveMessage(_ message: ArkavoMessage) {
        let encoder = JSONEncoder()
        let fileURL = messageDirectory.appendingPathComponent("\(message.id.uuidString).json")
        
        do {
            let data = try encoder.encode(message)
            try data.write(to: fileURL)
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
                let message = try decoder.decode(ArkavoMessage.self, from: data)
                
                // Reschedule pending messages
                if message.status == .pending {
                    scheduleReplay(for: message)
                }
                
                return message
            }
            .sorted { $0.timestamp > $1.timestamp }
            
        } catch {
            print("Error loading messages: \(error)")
        }
    }
    
    private func updateMessage(_ message: ArkavoMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
            saveMessage(message)
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
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
