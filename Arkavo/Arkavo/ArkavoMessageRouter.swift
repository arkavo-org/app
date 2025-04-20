import ArkavoSocial
import FlatBuffers
import Foundation
import OpenTDFKit

@MainActor
class ArkavoMessageRouter: ObservableObject, ArkavoClientDelegate {
    let client: ArkavoClient
    let persistenceController: PersistenceController
    // Track pending messages by their ephemeral public key
    private var pendingMessages: [Data: (header: Header, payload: Payload, nano: NanoTDF)] = [:]

    init(client: ArkavoClient, persistenceController: PersistenceController) {
        self.client = client
        self.persistenceController = persistenceController
        client.delegate = self
    }

    // MARK: - ArkavoClientDelegate Methods

    func clientDidChangeState(_: ArkavoClient, state: ArkavoClientState) {
        NotificationCenter.default.post(
            name: .arkavoClientStateChanged,
            object: nil,
            userInfo: ["state": state]
        )
    }

    func clientDidReceiveMessage(_: ArkavoClient, message: Data) {
        guard message.first != nil else {
            print("Invalid message: empty data")
            return
        }
        print("ArkavoMessageRouter.clientDidReceiveMessage")
        Task {
            do {
                try await processMessage(message)
            } catch {
                print("Error handling message: \(error)")
                NotificationCenter.default.post(
                    name: .messageHandlingError,
                    object: nil,
                    userInfo: ["error": error]
                )
            }
        }
    }

    // handles WebSocket messages and NanoTDF in Data format
    func processMessage(_ data: Data, messageId _: UUID? = nil) async throws {
        guard let messageType = data.first else {
            throw ArkavoError.messageError("Invalid message: empty data")
        }
        // if data is NanoTDF, decrypt it
        if data.count >= 3 {
            let magicNumberAndVersion = data.prefix(3)
            print(magicNumberAndVersion.hexEncodedString())
            if magicNumberAndVersion == Data([0x4C, 0x31, 0x4C]) {
                try await handleNATSMessage(data)
                return
            }
        }

        let messageData = data.dropFirst()

        switch messageType {
        case 0x03: // Rewrap
            try await handleRewrapMessage(messageData)
        case 0x04: // Rewrapped key
            try await handleRewrappedKey(messageData)
        case 0x05: // NATS message
            try await handleNATSMessage(messageData)
        case 0x06: // NATS event
            if data.count > 2000 {
                throw ArkavoError.messageError("Message type 0x06 exceeds maximum allowed size")
            }
            try await handleNATSEvent(messageData)
        default:
            print("Unknown message type: 0x\(String(format: "%02X", messageType))")
        }
    }

    func clientDidReceiveError(_: ArkavoClient, error: Error) {
        NotificationCenter.default.post(
            name: .arkavoClientError,
            object: nil,
            userInfo: ["error": error]
        )
    }

    /// Centralized function to handle the final decrypted plaintext.
    private func processDecryptedMessage(plaintext: Data, header: Header) async {
        print("Processing final decrypted message. Size: \(plaintext.count)")

        // Check if creator is blocked
        let arkavoPolicyMetadata = ArkavoPolicy(header.policy)
        if let creatorPublicID = arkavoPolicyMetadata.metadata?.creator,
           let messagePublicID = arkavoPolicyMetadata.metadata?.id
        {
            do {
                let blocked = try await PersistenceController.shared.isBlockedProfile(Data(creatorPublicID))
                if blocked {
                    print("🚫 Blocked creator message dropped: Creator=\(Data(creatorPublicID).base58EncodedString), Message=\(Data(messagePublicID).base58EncodedString)")
                    return // Do not post notification for blocked messages
                }
            } catch {
                print("⚠️ Error checking if creator is blocked: \(error)")
                // Decide whether to proceed or drop message on error
            }
        } else {
            print("⚠️ Could not extract creator/message ID from policy metadata for block check.")
        }

        // Broadcast the decrypted message via NotificationCenter
        NotificationCenter.default.post(
            name: .messageDecrypted,
            object: nil,
            userInfo: [
                "data": plaintext, // The final decrypted content
                "header": header, // Pass the original header for context
                "policy": ArkavoPolicy(header.policy), // Pass the parsed policy
            ]
        )
        print("✅ Posted .messageDecrypted notification.")
    }

    // Define relevant error types if not already present
    enum DecryptionError: Error {
        case publicKeyNotFoundForDecryption
        case privateKeyNotFound
        case unsupportedCurve
        case keyDerivationFailed
        case decryptionFailed
        // ... other crypto errors ...
    }

    // MARK: - Message Handling

    private func handleNATSEvent(_ payload: Data) async throws {
        print("Received NATS event: \(payload.base64EncodedString())")
        var bb = ByteBuffer(data: payload)
        let rootOffset = bb.read(def: Int32.self, position: 0)
        do {
            var verifier = try Verifier(buffer: &bb)
            try Arkavo_Event.verify(&verifier, at: Int(rootOffset), of: Arkavo_Event.self)
            print("The bytes represent a valid Arkavo_Event")
        } catch {
            print("Verification failed: \(error)")
            return
        }
        let event = Arkavo_Event(bb, o: Int32(Int(rootOffset)))
        print("  Action: \(event.action)")
        switch event.dataType {
        case .userevent:
            if let userEvent = event.data(type: Arkavo_UserEvent.self) {
                try await handleUserEvent(userEvent)
            }
        case .cacheevent:
            if let cacheEvent = event.data(type: Arkavo_CacheEvent.self) {
                try await handleCacheEvent(cacheEvent)
            }
        case .routeevent:
            if event.status == Arkavo_ActionStatus.fulfilled,
               let routeEvent = event.data(type: Arkavo_RouteEvent.self)
            {
                print("Route Event: fulfilled \(routeEvent.sourceId)")
                // Handle fulfilled route event (e.g., call a service)
                // Example: streamService.handleRouteEventFulfilled(routeEvent)
                return
            }
            if event.status == Arkavo_ActionStatus.preparing,
               let routeEvent = event.data(type: Arkavo_RouteEvent.self)
            {
                try await handleRouteEvent(routeEvent)
            }
        case .none_:
            print("  No event data")
        }
    }

    private func handleUserEvent(_ userEvent: Arkavo_UserEvent?) async throws {
        guard let userEvent else {
            throw ArkavoError.invalidEvent("UserEvent is nil")
        }

        // Process the UserEvent
        print("TODO Processing UserEvent \(userEvent.sourceId)")
        // Add your logic here to handle the UserEvent
    }

    private func handleCacheEvent(_ cacheEvent: Arkavo_CacheEvent?) async throws {
        guard let cacheEvent else {
            throw ArkavoError.invalidEvent("CacheEvent is nil")
        }

        // Process the CacheEvent
        print("TODO Processing CacheEvent \(cacheEvent.targetId)")
        // Add your logic here to handle the CacheEvent
    }

    private func handleRouteEvent(_ routeEvent: Arkavo_RouteEvent?) async throws {
        guard let routeEvent else {
            throw ArkavoError.invalidEvent("RouteEvent is nil")
        }

        // Process the RouteEvent
        print("TODO Processing RouteEvent \(routeEvent.sourceId)")
        // Add your logic here to handle the RouteEvent
    }

    /// Determines if the resource locator signals direct decryption.
    private func isDirectDecryptionLocator(_ locator: ResourceLocator) -> Bool {
        // TODO: fix
        locator.body.starts(with: "arkavo-profile://")
    }

    private func handleRewrapMessage(_ data: Data) async throws {
        print("Handling Rewrap message of size: \(data.count)")

        // Create a deep copy of the data
        let copiedData = Data(data)
        let parser = BinaryParser(data: copiedData)
        let header = try parser.parseHeader()
        let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
        let nano = NanoTDF(header: header, payload: payload, signature: nil)

        let epk = header.ephemeralPublicKey
//        print("Message components:")
//        print("- Header size: \(header.toData().count)")
//        print("- EPK: \(epk.hexEncodedString())")
        // Store message data with detailed logging
        pendingMessages[epk] = (header, payload, nano)
//        print("Stored pending message with EPK: \(epk.hexEncodedString())")

        // Create and send rewrap message containing only the header
        let rewrapMessage = RewrapMessage(header: header)
        try await client.sendMessage(rewrapMessage.toData())

        // Post notification about the rewrap request
        NotificationCenter.default.post(
            name: .rewrapRequestReceived,
            object: nil,
            userInfo: ["header": header]
        )
    }

    private func handleNATSMessage(_ data: Data) async throws {
        print("Handling NATS message of size: \(data.count)")

        // Create a deep copy of the data
        let copiedData = Data(data)
        let parser = BinaryParser(data: copiedData)
        let header = try parser.parseHeader()
        let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
        let nano = NanoTDF(header: header, payload: payload, signature: nil)

        let epk = header.ephemeralPublicKey
        print("Message components:")
        print("- Header size: \(header.toData().count)")
        print("- Payload size: \(payload.toData().count)")
        print("- Nano size: \(nano.toData().count)")

        // TODO: if local KAS in locator then load keystore for this profile vie metadata, sender ID
        // then use the private key from to get the rewrap key

        // Store message data with detailed logging
        pendingMessages[epk] = (header, payload, nano)
        print("Stored pending message with EPK: \(epk.hexEncodedString())")

        // Send rewrap message
        let rewrapMessage = RewrapMessage(header: header)
        try await client.sendMessage(rewrapMessage.toData())
    }

    /// Performs decryption locally using the KeyStore.
    private func performDirectDecryption(nanoTDF _: NanoTDF) async throws {
        print("ℹ️ Placeholder Performing direct decryption...")
    }

    // Placeholder function to get the relevant public key for lookup based on locator
    private func getMyPublicKeyDataForDecryption(locator: ResourceLocator) async -> Data? {
        // Implement logic:
        // 1. Parse locator.body (e.g., "arkavo-profile://<profile-id>")
        // 2. Fetch the corresponding Profile using PersistenceController
        // 3. Return the profile's public key data used for receiving messages (if stored)
        // OR: If using a default key, return that.
        // For now, return a placeholder or the default key from KeyStore
        print("   DEBUG: Determining recipient public key for locator: \(locator.body)")
        // Example: If locator body contains the base58 ID of the recipient profile
        if locator.body.starts(with: "arkavo-profile://") {
            let profileIDString = String(locator.body.dropFirst("arkavo-profile://".count))
            if let profileIDData = Data(base58Encoded: profileIDString) {
                // In a real scenario, you might fetch the profile and check its keys.
                // For now, let's assume this ID corresponds to the default key.
                print("   DEBUG: Locator indicates profile \(profileIDString). Assuming default key.")
                return profileIDData
            }
        }
        return nil
    }

    private func handleRewrappedKey(_ data: Data) async throws {
        print("\nDecrypting rewrapped key:")

        let identifier = data.prefix(33)
//        print("- EPK: \(identifier.hexEncodedString())")

        // Find corresponding message
        guard let (header, payload, nano) = pendingMessages.removeValue(forKey: identifier) else {
            print("❌ No pending message found for EPK")
            throw ArkavoError.messageError("No pending message found")
        }
//        print("✅ Found pending message")

        // Extract key components
        let keyData = data.suffix(60)
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16
        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

//        print("Key components:")
//        print("- Nonce: \(nonce.hexEncodedString())")
//        print("- Rewrapped key: \(rewrappedKey.hexEncodedString())")
//        print("- Auth tag: \(authTag.hexEncodedString())")

        // Decrypt the key using ArkavoClient's helper
        let symmetricKey = try client.decryptRewrappedKey(
            nonce: nonce,
            rewrappedKey: rewrappedKey,
            authTag: authTag
        )
//        print("✅ Decrypted symmetric key")

        // Decrypt the message content
        let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
//        print("✅ Decrypted payload of size: \(decryptedData.count)")

        // Check if decrypted data is a valid URL string
        if let urlString = String(data: decryptedData, encoding: .utf8) {
            print("Decrypted URL: \(urlString)")
        }

        let arkavoPolicyMetadata = ArkavoPolicy(header.policy)
        if let creatorPublicID = arkavoPolicyMetadata.metadata?.creator,
           let messagePublicID = arkavoPolicyMetadata.metadata?.id
        {
            do {
                let blocked = try await PersistenceController.shared.isBlockedProfile(Data(creatorPublicID))
                if blocked {
                    print("Blocked creator not delivered: \(Data(creatorPublicID).base58EncodedString) \(Data(messagePublicID).base58EncodedString)")
                    return
                }
            } catch {
                print("Error checking if creator is blocked: \(error)")
            }
        }

        // Broadcast the decrypted message
        NotificationCenter.default.post(
            name: .messageDecrypted,
            object: nil,
            userInfo: [
                "data": decryptedData,
                "header": header,
                "payload": payload,
                // perhaps remove this and have handlers use header
                "policy": ArkavoPolicy(header.policy),
            ]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let arkavoClientStateChanged = Notification.Name("arkavoClientStateChanged")
    static let arkavoClientError = Notification.Name("arkavoClientError")
    static let messageHandlingError = Notification.Name("messageHandlingError")
    static let natsMessageReceived = Notification.Name("natsMessageReceived")
    static let natsEventReceived = Notification.Name("natsEventReceived")
    static let messageDecrypted = Notification.Name("messageDecrypted")
    static let rewrapDenied = Notification.Name("rewrapDenied")
    static let rewrappedKeyReceived = Notification.Name("rewrappedKeyReceived")
    static let rewrapRequestReceived = Notification.Name("rewrapRequestReceived")
    static let messageCached = Notification.Name("messageCached")
    static let messageRemovedFromCache = Notification.Name("messageRemovedFromCache")
    static let messageProcessingFailed = Notification.Name("messageProcessingFailed")
    static let retryMessageProcessing = Notification.Name("retryMessageProcessing")
}

enum FlatBufferVerificationError: Error {
    case verificationFailed(String)
    case invalidBuffer(String)
    case invalidOffset(String)
}

func verifyFlatBufferObject<T: Verifiable>(
    offset: Offset,
    type: T.Type,
    builderData: ByteBuffer,
    errorMessage: String
) throws {
    // Validate offset
    guard offset.o > 0 else {
        throw FlatBufferVerificationError.invalidOffset("Invalid offset for \(T.self)")
    }

    // Create and configure verifier
    do {
        // Create a mutable copy of the buffer
        var mutableBuffer = builderData
        var verifier = try Verifier(buffer: &mutableBuffer)
        try type.verify(&verifier, at: Int(offset.o), of: type)
    } catch {
        print("❌ \(type) verification failed: \(error)")
        print("- Offset: \(offset.o)")
        print("- Buffer size: \(builderData.size)")
        throw FlatBufferVerificationError.verificationFailed("\(errorMessage): \(error)")
    }
}
