import Foundation
import OpenTDFKit

@MainActor
final class MessageQueueManager {
    // MARK: - Types

    struct QueuedMessage: Codable {
        let data: Data
        let timestamp: Date
        let messageType: UInt8
        let streamPublicID: Data? // Optional since not all messages have a stream ID
        let headerData: Data? // Store raw header data
        let payloadData: Data? // Store raw payload data

        // Computed properties to get Header and Payload when needed
        var header: Header? {
            guard let headerData else { return nil }
            do {
                let parser = BinaryParser(data: headerData)
                return try parser.parseHeader()
            } catch {
                print("Failed to parse header: \(error)")
                return nil
            }
        }

        var payload: Payload? {
            guard let payloadData,
                  let header else { return nil }
            do {
                let parser = BinaryParser(data: payloadData)
                return try parser.parsePayload(config: header.payloadSignatureConfig)
            } catch {
                print("Failed to parse payload: \(error)")
                return nil
            }
        }
    }

    private enum Constants {
        static let maxQueueSize = 50 * 1024 * 1024 // 50MB total queue limit
        static let messageExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
    }

    // MARK: - Properties

    private var queuedMessages: [UUID: QueuedMessage] = [:]
    private var messageOrder: [UUID] = [] // Maintain FIFO order
    private var currentQueueSize: Int = 0
    private let fileManager: FileManager = .default
    private let queueDirectory: URL

    // MARK: - Initialization

    init() throws {
        let baseURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        queueDirectory = baseURL.appendingPathComponent("ArkavoMessageQueue", isDirectory: true)
        try createQueueDirectoryIfNeeded()
        loadQueuedMessages()
    }

    // MARK: - Public Methods

    /// Queue a new message
    func queueMessage(data: Data, messageType: UInt8, streamPublicID: Data?) throws {
        // Check queue size
        if currentQueueSize + data.count > Constants.maxQueueSize {
            cleanQueue()
        }

        guard currentQueueSize + data.count <= Constants.maxQueueSize else {
            throw ArkavoError.messageError("Message too large for queue")
        }

        // Try to parse header and payload
        var header: Header?
        var payload: Payload?
        do {
            let parser = BinaryParser(data: data)
            header = try parser.parseHeader()
            payload = try parser.parsePayload(config: header!.payloadSignatureConfig)
        } catch {
            print("Could not parse header/payload for queueing: \(error)")
        }

        let messageId = UUID()
        let queuedMessage = QueuedMessage(
            data: data,
            timestamp: Date(),
            messageType: messageType,
            streamPublicID: streamPublicID,
            headerData: header?.toData(),
            payloadData: payload?.toData(),
        )

        // Store in memory
        queuedMessages[messageId] = queuedMessage
        messageOrder.append(messageId)
        currentQueueSize += data.count

        // Persist to disk
        try persistMessage(messageId: messageId, message: queuedMessage)

        NotificationCenter.default.post(
            name: .messageQueued,
            object: nil,
            userInfo: [
                "messageId": messageId,
                "messageType": messageType,
                "streamPublicID": streamPublicID as Any,
            ],
        )
    }

    /// Get next message of specified type and optional stream ID
    func getNextMessage(ofType messageType: UInt8, forStream streamPublicID: Data? = nil) -> (UUID, QueuedMessage)? {
        for messageId in messageOrder {
            guard let message = queuedMessages[messageId] else { continue }

            // Skip expired messages
            if isMessageExpired(message) {
                removeMessage(messageId)
                continue
            }

            // Check if message matches criteria
            if message.messageType == messageType {
                if let streamPublicID {
                    // If stream ID specified, must match
                    if message.streamPublicID == streamPublicID {
                        return (messageId, message)
                    }
                } else {
                    // If no stream ID specified, return any message of matching type
                    return (messageId, message)
                }
            }
        }
        return nil
    }

    /// Remove a message from the queue
    func removeMessage(_ messageId: UUID) {
        guard let message = queuedMessages[messageId] else { return }

        // Remove from memory
        queuedMessages.removeValue(forKey: messageId)
        messageOrder.removeAll { $0 == messageId }
        currentQueueSize -= message.data.count

        // Remove from disk
        let messageURL = queueDirectory.appendingPathComponent(messageId.uuidString)
        try? fileManager.removeItem(at: messageURL)

        NotificationCenter.default.post(
            name: .messageRemovedFromQueue,
            object: nil,
            userInfo: ["messageId": messageId],
        )
    }

    // MARK: - Private Methods

    private func createQueueDirectoryIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: queueDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(
                at: queueDirectory,
                withIntermediateDirectories: true,
            )
        }
    }

    private func loadQueuedMessages() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: queueDirectory,
            includingPropertiesForKeys: nil,
        ) else { return }

        for fileURL in fileURLs {
            guard let messageId = UUID(uuidString: fileURL.lastPathComponent),
                  let data = try? Data(contentsOf: fileURL),
                  let message = try? JSONDecoder().decode(QueuedMessage.self, from: data)
            else { continue }

            if isMessageExpired(message) {
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            queuedMessages[messageId] = message
            messageOrder.append(messageId)
            currentQueueSize += message.data.count
        }
    }

    private func persistMessage(messageId: UUID, message: QueuedMessage) throws {
        let messageURL = queueDirectory.appendingPathComponent(messageId.uuidString)
        let encodedData = try JSONEncoder().encode(message)
        try encodedData.write(to: messageURL)
    }

    private func isMessageExpired(_ message: QueuedMessage) -> Bool {
        Date().timeIntervalSince(message.timestamp) > Constants.messageExpirationInterval
    }

    private func cleanQueue() {
        // Remove expired messages
        var expiredIds: [UUID] = []
        for (id, message) in queuedMessages where isMessageExpired(message) {
            expiredIds.append(id)
        }

        for id in expiredIds {
            removeMessage(id)
        }

        // If still need space, remove oldest messages
        if currentQueueSize > Constants.maxQueueSize {
            while currentQueueSize > Constants.maxQueueSize,
                  let oldestId = messageOrder.first
            {
                removeMessage(oldestId)
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let messageQueued = Notification.Name("messageQueued")
    static let messageRemovedFromQueue = Notification.Name("messageRemovedFromQueue")
}
