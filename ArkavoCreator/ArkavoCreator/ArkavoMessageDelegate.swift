import Foundation
import ArkavoSocial
import Foundation

@MainActor
class ArkavoMessageDelegate: ObservableObject, ArkavoClientDelegate {
    // Make savedMessages published so views can observe changes
    @Published
    private var messageDirectory: URL
    private var pendingMessages: [URL: Timer] = [:]
    let client: ArkavoClient
    @Published var savedMessages: [SavedMessage] = []
    
    init(client: ArkavoClient) {
        self.client = client
        
        // Create directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        messageDirectory = appSupport.appendingPathComponent("ArkavoPendingMessages", isDirectory: true)
        
        do {
            try FileManager.default.createDirectory(at: messageDirectory, withIntermediateDirectories: true)
            print("Message directory created at: \(messageDirectory.path)")
            
            // Load existing messages
            try loadExistingMessages()
        } catch {
            print("Error setting up message directory: \(error)")
        }
    }
    
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        print("Client state changed to: \(state)")
        
        if case .connected = state {
            // When connected, check for pending messages to replay
            checkPendingMessages()
        }
    }
    
    func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        guard message.first == 0x06 else { return } // Only handle type 0x06
        
        let timestamp = Date()
        let messageData = message.dropFirst() // Remove type byte
        
        // Create unique filename with timestamp
        let filename = "message_\(Int(timestamp.timeIntervalSince1970))_\(UUID().uuidString).bin"
        let fileURL = messageDirectory.appendingPathComponent(filename)
        
        do {
            // Save message to disk
            try messageData.write(to: fileURL)
            print("Saved message to: \(fileURL.path)")
            
            // Create timer to read back after delay
            let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.replayMessage(at: fileURL)
                }
            }
            pendingMessages[fileURL] = timer
            
            // Add to saved messages list
            let savedMessage = SavedMessage(
                id: UUID(),
                timestamp: timestamp,
                fileURL: fileURL,
                size: messageData.count,
                status: .pending
            )
            savedMessages.append(savedMessage)
            
        } catch {
            print("Error saving message: \(error)")
        }
    }
    
    func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        print("Client error: \(error)")
    }
    
    private func loadExistingMessages() throws {
        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(
            at: messageDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )
        
        for file in files {
            let attributes = try file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            let timestamp = attributes.creationDate ?? Date()
            let size = attributes.fileSize ?? 0
            
            let savedMessage = SavedMessage(
                id: UUID(),
                timestamp: timestamp,
                fileURL: file,
                size: size,
                status: .pending
            )
            savedMessages.append(savedMessage)
            
            // Set up replay timer
            let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.replayMessage(at: file)
                }
            }
            pendingMessages[file] = timer
        }
        
        // Sort messages by timestamp
        savedMessages.sort { $0.timestamp > $1.timestamp }
    }
    
    private func checkPendingMessages() {
        for (fileURL, timer) in pendingMessages {
            if timer.isValid {
                // Message hasn't been replayed yet
                continue
            }
            
            // Attempt to replay expired messages
            Task {
                await replayMessage(at: fileURL)
            }
        }
    }
    
    private func replayMessage(at fileURL: URL) async {
        guard client.currentState == .connected else {
            print("Client not connected, deferring message replay")
            return
        }
        
        do {
            let messageData = try Data(contentsOf: fileURL)
            var replayData = Data([0x06]) // Add type byte back
            replayData.append(messageData)
            
            try await client.sendMessage(replayData)
            print("Replayed message from: \(fileURL.path)")
            
            // Update status in saved messages
            if let index = savedMessages.firstIndex(where: { $0.fileURL == fileURL }) {
                savedMessages[index].status = .replayed
            }
            
            // Clean up
            pendingMessages[fileURL]?.invalidate()
            pendingMessages.removeValue(forKey: fileURL)
            try FileManager.default.removeItem(at: fileURL)
            
        } catch {
            print("Error replaying message: \(error)")
            // Update status to failed
            if let index = savedMessages.firstIndex(where: { $0.fileURL == fileURL }) {
                savedMessages[index].status = .failed(error.localizedDescription)
            }
        }
    }
}

// Message status tracking
enum MessageStatus: Equatable {
    case pending
    case replayed
    case failed(String)
}

struct SavedMessage: Identifiable {
    let id: UUID
    let timestamp: Date
    let fileURL: URL
    let size: Int
    var status: MessageStatus
}
