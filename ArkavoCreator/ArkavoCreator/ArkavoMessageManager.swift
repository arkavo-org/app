import ArkavoKit
import Foundation
import SwiftUI

// First, let's modify the ArkavoMessageChainDelegate to properly handle type 0x05 messages
class ArkavoMessageChainDelegate: NSObject, ArkavoClientDelegate {
    private let messageManager: ArkavoMessageManager
    private weak var nextDelegate: ArkavoClientDelegate?

    init(client: ArkavoClient, existingDelegate: ArkavoClientDelegate?) {
        messageManager = ArkavoMessageManager(client: client)
        nextDelegate = existingDelegate
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

// Define potential errors for relay operations
enum RelayError: Error {
    case notInitialized
    case connectionFailed(Error)
    case relayFailed(Error)
}

@MainActor
class ArkavoMessageManager: ObservableObject {
    @Published var messages: [ArkavoMessage] = []
    @Published var replayToProduction = true // Controls where messages are replayed to

    private var relayManager: WebSocketRelayManager?
    private let arkavoClient: ArkavoClient
    private let fileManager = FileManager.default
    private let messageDirectory: URL
    private var replayTask: Task<Void, Never>?
    private var currentReplayIndex = 0
    private var isReplaying = false

    init(client: ArkavoClient) {
        arkavoClient = client
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

        // Start message replay
        startMessageReplay()
    }

    private func initializeRelay() {
        // Run the initialization and connection in a background Task
        Task {
            do {
                // Initialize the actor instance (synchronous)
                let localRelayManager = WebSocketRelayManager()

                // Perform the asynchronous connection attempt in the background.
                try await localRelayManager.connect()

                // Once connected, switch back to the main actor to update the
                // @MainActor isolated 'relayManager' property safely.
                await MainActor.run {
                    self.relayManager = localRelayManager
                    print("Local WebSocket relay initialized and connected.")
                }
            } catch {
                // Handle errors, potentially updating UI or state on the main actor.
                print("Failed to initialize or connect relay: \(error)")
                // Optionally update state on the main actor:
                // await MainActor.run { self.lastError = "Relay init failed: \(error)" }
            }
        }
    }

    private func startMessageReplay() {
        // Cancel any existing replay task
        replayTask?.cancel()
        currentReplayIndex = 0
        isReplaying = true

        // Sort messages by timestamp to maintain chronological order
        messages.sort { $0.timestamp < $1.timestamp }

        // Create a new async task for message replay
        // This Task inherits the @MainActor context from startMessageReplay
        replayTask = Task { [weak self] in
            while !Task.isCancelled, let self, isReplaying {
                // replayNextMessage is @MainActor isolated, call directly
                await replayNextMessage()
                // Check for cancellation before sleeping
                if Task.isCancelled {
                    break
                }
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
                } catch {
                    // Handle cancellation error during sleep
                    if error is CancellationError {
                        print("Replay task cancelled during sleep.")
                        break
                    } else {
                        print("Error during sleep: \(error)")
                    }
                }
            }
            // Ensure isReplaying is set to false when the loop finishes or is cancelled
            await MainActor.run { [weak self] in
                self?.isReplaying = false
                print("Replay task finished or cancelled.")
            }
        }
    }

    // This method runs on the MainActor because the class is @MainActor isolated
    private func replayNextMessage() async {
        guard !messages.isEmpty else {
            // Resetting index here might not be needed if we just wait
            currentReplayIndex = 0
            return
        }

        // Ensure index is within bounds, loop if necessary
        if currentReplayIndex >= messages.count {
            currentReplayIndex = 0
        }

        let message = messages[currentReplayIndex]

        do {
            if replayToProduction {
                // Send to production server (assuming arkavoClient.sendMessage is safe to call from MainActor)
                try await arkavoClient.sendMessage(message.data)
                print("Replayed message \(message.id) to production server")
            } else {
                // Send to local relay via the async relayMessage method
                try await relayMessage(message) // This call is safe from @MainActor
                print("Replayed message \(message.id) to localhost")
            }

            // Update message status (must be done on MainActor)
            var updatedMessage = message
            updatedMessage.status = .replayed
            updatedMessage.lastRetryDate = Date()
            updatedMessage.retryCount += 1

            // Update in array and save
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }
            saveMessage(updatedMessage) // saveMessage is synchronous, runs on MainActor

        } catch {
            // Update message status on failure (must be done on MainActor)
            var updatedMessage = message
            updatedMessage.status = .failed
            updatedMessage.lastRetryDate = Date()
            updatedMessage.retryCount += 1

            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = updatedMessage
            }
            saveMessage(updatedMessage) // saveMessage is synchronous, runs on MainActor

            print("Failed to replay message \(message.id): \(error)")
        }

        currentReplayIndex += 1
    }

    // This method runs on the MainActor
    func handleMessage(_ data: Data) {
        guard data.first == 0x05 else { return }

        // Create message (on MainActor)
        let message = ArkavoMessage(
            id: UUID(),
            timestamp: Date(),
            data: data,
            status: .pending,
            retryCount: 0,
            lastRetryDate: nil,
        )

        // Store to filesystem (synchronous, on MainActor)
        messages.append(message)
        saveMessage(message)

        // Forward to local WebSocket server if not in production mode
        if !replayToProduction {
            // Create a Task inheriting MainActor context to call the async relayMessage
            Task {
                do {
                    try await relayMessage(message)
                } catch {
                    // Handle error from relaying if necessary
                    print("Error relaying newly handled message \(message.id): \(error)")
                    // Maybe update message status to failed here as well?
                }
            }
        }
    }

    // This method is async but runs on the MainActor because the class is @MainActor
    private func relayMessage(_ message: ArkavoMessage) async throws {
        // Accessing relayManager here is safe because we are on the MainActor
        guard let relayManager else {
            print("Relay manager not initialized")
            throw RelayError.notInitialized // Throw a specific error
        }

        do {
            // This correctly awaits the call to the actor's method.
            // Swift handles hopping to the actor's executor and back.
            try await relayManager.relayMessage(message.data)
            print("Message \(message.id) relayed to localhost")
        } catch {
            print("Failed to relay message \(message.id): \(error)")
            // Re-throw the error caught from the actor call
            throw RelayError.relayFailed(error)
        }
    }

    // This method runs on the MainActor
    private func saveMessage(_ message: ArkavoMessage) {
        let encoder = JSONEncoder()
        let fileURL = messageDirectory.appendingPathComponent("\(message.id.uuidString).json")

        do {
            let data = try encoder.encode(message)
            // Consider making file writing asynchronous if it becomes a bottleneck
            try data.write(to: fileURL)
            print("Successfully saved message \(message.id) to \(fileURL.path)")
        } catch {
            print("Error saving message: \(error)")
        }
    }

    // This method runs on the MainActor
    private func loadMessages() {
        do {
            // Consider making file reading asynchronous if it becomes a bottleneck
            let files = try fileManager.contentsOfDirectory(
                at: messageDirectory,
                includingPropertiesForKeys: nil,
            )

            let decoder = JSONDecoder()
            // Decoding can be computationally intensive, consider background thread if needed
            let loadedMessages = try files.compactMap { fileURL -> ArkavoMessage? in
                guard fileURL.pathExtension == "tdf" else { return nil }
                let data = try Data(contentsOf: fileURL)
                return try decoder.decode(ArkavoMessage.self, from: data)
            }

            // Update the @Published property on the MainActor
            messages = loadedMessages.sorted { $0.timestamp < $1.timestamp } // Sort ascending for replay order

            print("Loaded \(messages.count) messages from filesystem")
        } catch {
            print("Error loading messages: \(error)")
        }
    }

    deinit {
        // Ensure replay task is cancelled
        isReplaying = false
        replayTask?.cancel()
        print("ArkavoMessageManager deinit: Replay task cancelled.")
        // Disconnect local relay if needed (consider if relayManager should be disconnected)
        // Task { await relayManager?.disconnect() } // Example if disconnect is needed
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
            case .pending: "clock"
            case .replayed: "checkmark.circle"
            case .failed: "exclamationmark.triangle"
            }
        }

        var color: Color {
            switch self {
            case .pending: .yellow
            case .replayed: .green
            case .failed: .red
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
        try container.encode(data.base64EncodedString(), forKey: .data) // Encode Data as Base64 String
        try container.encode(status, forKey: .status)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(lastRetryDate, forKey: .lastRetryDate) // Use encodeIfPresent for optional
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
        let base64String = try container.decode(String.self, forKey: .data) // Decode Base64 String
        guard let decodedData = Data(base64Encoded: base64String) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [CodingKeys.data],
                    debugDescription: "Could not decode base64 string to Data",
                ),
            )
        }
        data = decodedData
        status = try container.decode(MessageStatus.self, forKey: .status)
        retryCount = try container.decode(Int.self, forKey: .retryCount)
        lastRetryDate = try container.decodeIfPresent(Date.self, forKey: .lastRetryDate) // Use decodeIfPresent
    }
}
