import ArkavoSocial
import CryptoKit
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
            let magicNumberAndVersion = data.prefix(2)
            print(magicNumberAndVersion.hexEncodedString())
            if magicNumberAndVersion == Data([0x4C, 0x31]) {
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
            // FIXME: hack, not sure why I am getting 064c31
//            try await handleNATSEvent(messageData)
            try await handleNATSMessage(messageData)
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
        // test if valid
        _ = try ArkavoPolicy.parseMetadata(from: header.policy.body!.body)
        let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
        let nano = NanoTDF(header: header, payload: payload, signature: nil)

        let epk = header.ephemeralPublicKey
        print("Message components:")
        print("- Header size: \(header.toData().count)")
        print("- Payload size: \(payload.toData().count)")
        print("- Nano size: \(nano.toData().count)")
        print("- KAS Locator: \(header.kas.body)")
        print("- EPK: \(epk.hexEncodedString())")

        let kasIdentifier = header.kas.body
        print("   KAS Identifier from NATS message header: \(kasIdentifier)")

        if kasIdentifier == "kas.arkavo.net" {
            // --- Path A: Use Central KAS (Request Rewrap) ---
            print("   KAS matches default kas.arkavo.net. Requesting rewrap...")
            // Store message data with detailed logging
            pendingMessages[epk] = (header, payload, nano)
            print("Stored pending message with EPK: \(epk.hexEncodedString())")

            // Send rewrap message
            let rewrapMessage = RewrapMessage(header: header)
            try await client.sendMessage(rewrapMessage.toData())

        } else {
            // --- Path B: Use Local KeyStore (Direct Decryption) ---
            print("   KAS identifier (\(kasIdentifier)) indicates local decryption needed for NATS message.")
            guard let accountProfile = try await PersistenceController.shared.getOrCreateAccount().profile else {
                print("❌ Invalid account profile")
                throw ArkavoError.profileNotFound("account")
            }
            if accountProfile.publicID.base58EncodedString != kasIdentifier {
                print("skipping direct decryption: KAS locator does not match profile account")
                return
            }
            // FIXME: remove !
            let metadata = try ArkavoPolicy.parseMetadata(from: header.policy.body!.body)
            let creator = Data(metadata.creator)
            print(creator.base58EncodedString)
            // Call handleDirectDecryption with the sender's ID
            try await handleDirectDecryption(nano: nano, senderProfileID: creator)
        }
    }

    /// Handles decryption using a local Private KeyStore based on sender profile ID.
    /// Used for NATS messages where KAS locator points to a peer, and for P2P messages.
    private func handleDirectDecryption(nano: NanoTDF, senderProfileID: Data) async throws {
        print("Attempting direct decryption for sender: \(senderProfileID.base58EncodedString)...")

        // 1. Load Private KeyStore for the sender (Function already takes Profile ID)
        print("   Loading private KeyStore for sender...")
        guard let privateKeyStore = await loadPrivateKeyStore(forPeer: senderProfileID) else {
            print("❌ Failed to load private KeyStore for sender \(senderProfileID.base58EncodedString).")
            throw ArkavoError.keyStoreError(senderProfileID.base58EncodedString)
        }
        print("   Private KeyStore loaded successfully.")

        // 3. Decrypt the payload
        print("   Decrypting payload using private KeyStore with public key \(nano.header.ephemeralPublicKey.hexEncodedString())")
        
        // --- CRYPTOKIT SANITY CHECK FOR EPHEMERAL PUBLIC KEY ---

        let ephemeralPublicKeyBytes = nano.header.payloadKeyAccess.kasPublicKey
        let policyECCMode = Curve.secp256r1
        // 2. Attempt to initialize a CryptoKit PublicKey object.
        // This will throw an error if the key data is invalid for the specified curve/format.
        do {
            switch policyECCMode {
            case .secp256r1:
                _ = try P256.KeyAgreement.PublicKey(compressedRepresentation: ephemeralPublicKeyBytes)
                print("✅ Sanity Check (CryptoKit P256): Ephemeral Public Key is valid format.")
            case .secp384r1:
                _ = try P384.KeyAgreement.PublicKey(compressedRepresentation: ephemeralPublicKeyBytes)
                print("✅ Sanity Check (CryptoKit P384): Ephemeral Public Key is valid format.")
            case .secp521r1:
                _ = try P521.KeyAgreement.PublicKey(compressedRepresentation: ephemeralPublicKeyBytes)
                print("✅ Sanity Check (CryptoKit P521): Ephemeral Public Key is valid format.")
            }
        } catch let error as CryptoKitError { // Catch specific CryptoKit errors
            print("❌ Sanity Check Failed (CryptoKit): Ephemeral Public Key is invalid or malformed for curve \(policyECCMode). Error: \(error)")
        } catch { // Catch any other errors during initialization
            print("❌ Sanity Check Failed (CryptoKit): An unexpected error occurred during public key initialization for curve \(policyECCMode). Error: \(error)")
        }
        let publicKS = await privateKeyStore.exportPublicKeyStore()
        let tmpPublicKey = try await publicKS.getAndRemovePublicKey()
//        let tmp = await privateKeyStore.generateKeyPair()
        print("TEMP public key \(tmpPublicKey.hexEncodedString())")
//        await privateKeyStore.store(keyPair: tmp)
        let tmpprivatekey = await privateKeyStore.getPrivateKey(forPublicKey: tmpPublicKey)
        print("TEMP private key \(tmpprivatekey?.hexEncodedString() ?? "not found")")
        // --- END OF CRYPTOKIT SANITY CHECK ---
        
//        guard let privateKey = await privateKeyStore.getPrivateKey(forPublicKey: nano.header.payloadKeyAccess.kasPublicKey) else {
//            print("❌ Failed to find a matching private key from sender.")
//            return
//        }
        
        let symmetricKeyBytes = try await privateKeyStore.derivePayloadSymmetricKey(
            kasPublicKey: nano.header.payloadKeyAccess.kasPublicKey,
            tdfEphemeralPublicKey: nano.header.ephemeralPublicKey
        )
        print("   Derived symmetric key successfully: \(symmetricKeyBytes.hexEncodedString())")
        
        // Use the derived symmetric key to decrypt the NanoTDF payload
        do {
            let symmetricKey = SymmetricKey(data: symmetricKeyBytes)
            let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
            print("✅ Payload decrypted successfully. Size: \(decryptedData.count)")
            
            // For debug purposes, try to show the beginning of the message if it's text
            if let textPreview = String(data: decryptedData.prefix(min(100, decryptedData.count)), encoding: .utf8) {
                print("   Preview of decrypted data: \(textPreview)")
            }
            
            // 4. Process the decrypted message
            await processDecryptedMessage(plaintext: decryptedData, header: nano.header)
        } catch {
            print("❌ Failed to decrypt payload. Error: \(error)")
            return
        }
    }

    /// Helper to load the private KeyStore associated with a given peer profile ID.
    private func loadPrivateKeyStore(forPeer senderProfileID: Data) async -> KeyStore? {
        do {
            // Fetch the Profile object associated with the SENDER
            guard let peerProfile = try await persistenceController.fetchProfile(withPublicID: senderProfileID) else {
                print("   loadPrivateKeyStore: Profile not found for ID \(senderProfileID.base58EncodedString)")
                return nil
            }

            // Get the PRIVATE KeyStore data stored FOR THIS PEER on the local device
            guard let privateData = peerProfile.keyStorePrivate, !privateData.isEmpty else {
                print("   loadPrivateKeyStore: No private KeyStore data found on profile \(peerProfile.name)")
                return nil
            }

            // Deserialize the KeyStore
            // TODO: Determine curve dynamically if needed. Assuming p256.
            let keyStore = KeyStore(curve: .secp256r1)
            try await keyStore.deserialize(from: privateData) // Deserialize into the instance
            print("   loadPrivateKeyStore: Deserialized private KeyStore for \(peerProfile.name)")
            return keyStore

        } catch {
            print("❌ Error loading/deserializing private KeyStore for \(senderProfileID.base58EncodedString): \(error)")
            return nil
        }
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
