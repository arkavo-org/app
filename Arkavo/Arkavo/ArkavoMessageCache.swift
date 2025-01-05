// import Foundation
// import OpenTDFKit
//
// @MainActor
// class MessageRouterCache {
//    // MARK: - Types
//
//    struct CachedMessage: Codable {
//        let data: Data
//        let timestamp: Date
//        let messageType: UInt8
//        let retryCount: Int
//        let headerData: Data? // Store raw header data instead of Header
//        let payloadData: Data? // Store raw payload data instead of Payload
//
//        // Computed properties to get Header and Payload when needed
//        var header: Header? {
//            guard let headerData else { return nil }
//            do {
//                let parser = BinaryParser(data: headerData)
//                return try parser.parseHeader()
//            } catch {
//                print("Failed to parse header: \(error)")
//                return nil
//            }
//        }
//
//        var payload: Payload? {
//            guard let payloadData,
//                  let header else { return nil }
//            do {
//                let parser = BinaryParser(data: payloadData)
//                return try parser.parsePayload(config: header.payloadSignatureConfig)
//            } catch {
//                print("Failed to parse payload: \(error)")
//                return nil
//            }
//        }
//
//        var isExpired: Bool {
//            Date().timeIntervalSince(timestamp) > Constants.messageExpirationInterval
//        }
//    }
//
//    private enum Constants {
//        static let maxCacheSize = 50 * 1024 * 1024 // 50MB total cache limit
//        static let messageExpirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
//        static let maxRetryAttempts = 3
//        static let retryInterval: TimeInterval = 60 // 1 minute between retries
//    }
//
//    // MARK: - Properties
//
//    private var cachedMessages: [UUID: CachedMessage] = [:]
//    private var currentCacheSize: Int = 0
//    private var retryTimer: Timer?
//    private let fileManager: FileManager = .default
//    private let cacheDirectory: URL
//    private weak var router: ArkavoMessageRouter?
//
//    // MARK: - Initialization
//
//    init(router: ArkavoMessageRouter) throws {
//        self.router = router
//        let baseURL = try fileManager.url(
//            for: .cachesDirectory,
//            in: .userDomainMask,
//            appropriateFor: nil,
//            create: true
//        )
//        cacheDirectory = baseURL.appendingPathComponent("ArkavoRouterCache", isDirectory: true)
//        try createCacheDirectoryIfNeeded()
//        loadCachedMessages()
//        setupRetryTimer()
//    }
//
//    deinit {
//        retryTimer?.invalidate()
//    }
//
//    // MARK: - Cache Management
//
//    func cacheMessage(data: Data, messageType: UInt8, header: Header? = nil, payload: Payload? = nil) throws {
//        let messageId = UUID()
//
//        // Check if we need to make space
//        if currentCacheSize + data.count > Constants.maxCacheSize {
//            cleanCache()
//        }
//
//        guard currentCacheSize + data.count <= Constants.maxCacheSize else {
//            throw ArkavoError.messageError("Message too large for cache")
//        }
//
//        let cachedMessage = CachedMessage(
//            data: data,
//            timestamp: Date(),
//            messageType: messageType,
//            retryCount: 0,
//            headerData: header?.toData(),
//            payloadData: payload?.toData()
//        )
//
//        cachedMessages[messageId] = cachedMessage
//        currentCacheSize += data.count
//
//        try persistMessage(messageId: messageId, message: cachedMessage)
//
//        NotificationCenter.default.post(
//            name: .messageCached,
//            object: nil,
//            userInfo: [
//                "messageId": messageId,
//                "messageType": messageType,
//            ]
//        )
//    }
//
//    func getCachedMessages(forStreamPublicID streamPublicID: Data? = nil) -> [(UUID, CachedMessage)] {
//        if let streamPublicID {
//            return cachedMessages.filter { _, message in
//                message.header?.policy.remote?.toData() == streamPublicID
//            }.map { ($0, $1) }
//        }
//        return cachedMessages.map { ($0, $1) }
//    }
//
//    func removeMessage(_ messageId: UUID) throws {
//        guard let message = cachedMessages[messageId] else { return }
//        cachedMessages.removeValue(forKey: messageId)
//        currentCacheSize -= message.data.count
//
//        let messageURL = cacheDirectory.appendingPathComponent(messageId.uuidString)
//        try? fileManager.removeItem(at: messageURL)
//
//        NotificationCenter.default.post(
//            name: .messageRemovedFromCache,
//            object: nil,
//            userInfo: ["messageId": messageId]
//        )
//    }
//
//    // MARK: - Private Methods
//
//    private func createCacheDirectoryIfNeeded() throws {
//        var isDirectory: ObjCBool = false
//        if !fileManager.fileExists(atPath: cacheDirectory.path, isDirectory: &isDirectory) {
//            try fileManager.createDirectory(
//                at: cacheDirectory,
//                withIntermediateDirectories: true
//            )
//        }
//    }
//
//    private func loadCachedMessages() {
//        guard let fileURLs = try? fileManager.contentsOfDirectory(
//            at: cacheDirectory,
//            includingPropertiesForKeys: nil
//        ) else { return }
//
//        for fileURL in fileURLs {
//            guard let messageId = UUID(uuidString: fileURL.lastPathComponent),
//                  let data = try? Data(contentsOf: fileURL),
//                  let message = try? JSONDecoder().decode(CachedMessage.self, from: data)
//            else { continue }
//
//            if message.isExpired {
//                try? fileManager.removeItem(at: fileURL)
//                continue
//            }
//
//            cachedMessages[messageId] = message
//            currentCacheSize += message.data.count
//        }
//    }
//
//    private func persistMessage(messageId: UUID, message: CachedMessage) throws {
//        let messageURL = cacheDirectory.appendingPathComponent(messageId.uuidString)
//        let encodedData = try JSONEncoder().encode(message)
//        try encodedData.write(to: messageURL)
//    }
//
//    private func cleanCache() {
//        // Remove expired messages
//        var expiredIds: [UUID] = []
//        for (id, message) in cachedMessages where message.isExpired {
//            expiredIds.append(id)
//        }
//
//        for id in expiredIds {
//            try? removeMessage(id)
//        }
//
//        // If still need space, remove oldest messages
//        if currentCacheSize > Constants.maxCacheSize {
//            let sortedMessages = cachedMessages.sorted { $0.value.timestamp < $1.value.timestamp }
//            for (id, _) in sortedMessages {
//                try? removeMessage(id)
//                if currentCacheSize <= Constants.maxCacheSize {
//                    break
//                }
//            }
//        }
//    }
//
//    private func setupRetryTimer() {
//        retryTimer = Timer.scheduledTimer(
//            withTimeInterval: Constants.retryInterval,
//            repeats: true
//        ) { [weak self] _ in
//            Task { @MainActor [weak self] in
//                self?.retryFailedMessages()
//            }
//        }
//    }
//
//    private func retryFailedMessages() {
//        let messagesToRetry = cachedMessages.filter { !$0.value.isExpired }
//
//        for (messageId, message) in messagesToRetry {
//            guard let router else { return }
//
//            Task {
//                do {
//                    try await router.processMessage(message.data, messageId: messageId)
//                    try removeMessage(messageId)
//                } catch {
//                    print("Failed to process cached message: \(error)")
//                }
//            }
//        }
//    }
// }
