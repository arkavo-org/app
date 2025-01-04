import Foundation
import OpenTDFKit

@MainActor
final class MessageCacheManager {
    // MARK: - Types

    struct CachedMessage: Codable {
        let data: Data
        let timestamp: Date
        let messageType: UInt8
        let retryCount: Int
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

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > Constants.messageExpirationInterval
        }
    }

    private enum Constants {
        static let maxCacheSize = 50 * 1024 * 1024 // 50MB total cache limit
        static let messageExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
        static let maxRetryAttempts = 3
        static let retryInterval: TimeInterval = 60 // 1 minute between retries
    }

    // MARK: - Properties

    private var cachedMessages: [UUID: CachedMessage] = [:]
    private var currentCacheSize: Int = 0
    private var retryTimer: Timer?
    private let fileManager: FileManager = .default
    private let cacheDirectory: URL

    // MARK: - Initialization

    init() throws {
        let baseURL = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        cacheDirectory = baseURL.appendingPathComponent("ArkavoRouterCache", isDirectory: true)
        try createCacheDirectoryIfNeeded()
        loadCachedMessages()
        setupRetryTimer()
    }

    deinit {
        retryTimer?.invalidate()
    }

    // MARK: - Public Methods

    func cacheMessage(data: Data, messageType: UInt8) throws {
        // Check cache size
        if currentCacheSize + data.count > Constants.maxCacheSize {
            cleanCache()
        }

        guard currentCacheSize + data.count <= Constants.maxCacheSize else {
            throw ArkavoError.messageError("Message too large for cache")
        }

        // Try to parse header and payload
        var header: Header?
        var payload: Payload?
        do {
            let parser = BinaryParser(data: data)
            header = try parser.parseHeader()
            payload = try parser.parsePayload(config: header!.payloadSignatureConfig)
        } catch {
            print("Could not parse header/payload for caching: \(error)")
        }

        let messageId = UUID()
        let cachedMessage = CachedMessage(
            data: data,
            timestamp: Date(),
            messageType: messageType,
            retryCount: 0,
            headerData: header?.toData(),
            payloadData: payload?.toData()
        )

        // Store in memory
        cachedMessages[messageId] = cachedMessage
        currentCacheSize += data.count

        // Persist to disk
        try persistMessage(messageId: messageId, message: cachedMessage)

        NotificationCenter.default.post(
            name: .messageCached,
            object: nil,
            userInfo: [
                "messageId": messageId,
                "messageType": messageType,
            ]
        )
    }

    func getCachedMessages(forStream streamPublicID: Data? = nil) -> [(UUID, CachedMessage)] {
        if let streamPublicID {
            return cachedMessages.filter { _, message in
                // FIXME:
                message.header?.policy.toData() == streamPublicID
            }.map { ($0, $1) }
        }
        return cachedMessages.map { ($0, $1) }
    }

    func removeMessage(_ messageId: UUID) throws {
        guard let message = cachedMessages[messageId] else { return }

        // Remove from memory
        cachedMessages.removeValue(forKey: messageId)
        currentCacheSize -= message.data.count

        // Remove from disk
        let messageURL = cacheDirectory.appendingPathComponent(messageId.uuidString)
        try? fileManager.removeItem(at: messageURL)

        NotificationCenter.default.post(
            name: .messageRemovedFromCache,
            object: nil,
            userInfo: ["messageId": messageId]
        )
    }

    func incrementRetryCount(_ messageId: UUID) throws {
        guard let message = cachedMessages[messageId] else { return }

        let updatedMessage = CachedMessage(
            data: message.data,
            timestamp: message.timestamp,
            messageType: message.messageType,
            retryCount: message.retryCount + 1,
            headerData: message.headerData,
            payloadData: message.payloadData
        )

        cachedMessages[messageId] = updatedMessage
        try persistMessage(messageId: messageId, message: updatedMessage)

        if updatedMessage.retryCount >= Constants.maxRetryAttempts {
            try removeMessage(messageId)
            NotificationCenter.default.post(
                name: .messageProcessingFailed,
                object: nil,
                userInfo: [
                    "messageId": messageId,
                    "error": ArkavoError.messageError("Max retry attempts reached"),
                ]
            )
        }
    }

    // MARK: - Private Methods

    private func createCacheDirectoryIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: cacheDirectory.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    private func loadCachedMessages() {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for fileURL in fileURLs {
            guard let messageId = UUID(uuidString: fileURL.lastPathComponent),
                  let data = try? Data(contentsOf: fileURL),
                  let message = try? JSONDecoder().decode(CachedMessage.self, from: data)
            else { continue }

            if message.isExpired {
                try? fileManager.removeItem(at: fileURL)
                continue
            }

            cachedMessages[messageId] = message
            currentCacheSize += message.data.count
        }
    }

    private func persistMessage(messageId: UUID, message: CachedMessage) throws {
        let messageURL = cacheDirectory.appendingPathComponent(messageId.uuidString)
        let encodedData = try JSONEncoder().encode(message)
        try encodedData.write(to: messageURL)
    }

    private func cleanCache() {
        // Remove expired messages
        var expiredIds: [UUID] = []
        for (id, message) in cachedMessages where message.isExpired {
            expiredIds.append(id)
        }

        for id in expiredIds {
            try? removeMessage(id)
        }

        // If still need space, remove oldest messages
        if currentCacheSize > Constants.maxCacheSize {
            let sortedMessages = cachedMessages.sorted { $0.value.timestamp < $1.value.timestamp }
            for (id, _) in sortedMessages {
                try? removeMessage(id)
                if currentCacheSize <= Constants.maxCacheSize {
                    break
                }
            }
        }
    }

    private func setupRetryTimer() {
        retryTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.retryInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryFailedMessages()
            }
        }
    }

    private func retryFailedMessages() {
        let messagesToRetry = cachedMessages.filter { !$0.value.isExpired }

        for (messageId, message) in messagesToRetry {
            NotificationCenter.default.post(
                name: .retryMessageProcessing,
                object: nil,
                userInfo: [
                    "messageId": messageId,
                    "data": message.data,
                    "messageType": message.messageType,
                ]
            )
        }
    }
}
