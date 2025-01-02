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
        guard let messageType = message.first else {
            print("Invalid message: empty data")
            return
        }

        let messageData = message.dropFirst()

        Task {
            do {
                switch messageType {
                case 0x03: // Rewrap
                    try await handleRewrapMessage(messageData)

                case 0x04: // Rewrapped key
                    try await handleRewrappedKey(messageData)

                case 0x05: // NATS message
                    try await handleNATSMessage(messageData)

                case 0x06: // NATS event
                    try await handleNATSEvent(messageData)

                default:
                    print("Unknown message type: 0x\(String(format: "%02X", messageType))")
                }
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

    func clientDidReceiveError(_: ArkavoClient, error: Error) {
        NotificationCenter.default.post(
            name: .arkavoClientError,
            object: nil,
            userInfo: ["error": error]
        )
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
                print("Route Event: fulfilled")
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
        guard let userEvent = userEvent else {
            throw ArkavoError.invalidEvent("UserEvent is nil")
        }

        // Process the UserEvent
        print("Processing UserEvent")
        // Add your logic here to handle the UserEvent
    }

    private func handleCacheEvent(_ cacheEvent: Arkavo_CacheEvent?) async throws {
        guard let cacheEvent = cacheEvent else {
            throw ArkavoError.invalidEvent("CacheEvent is nil")
        }

        // Process the CacheEvent
        print("Processing CacheEvent")
        // Add your logic here to handle the CacheEvent
    }

    private func handleRouteEvent(_ routeEvent: Arkavo_RouteEvent?) async throws {
        guard let routeEvent = routeEvent else {
            throw ArkavoError.invalidEvent("RouteEvent is nil")
        }

        // Process the RouteEvent
        print("Processing RouteEvent")
        // Add your logic here to handle the RouteEvent
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
        print("Message components:")
        print("- Header size: \(header.toData().count)")
        print("- EPK: \(epk.hexEncodedString())")
        // Store message data with detailed logging
        pendingMessages[epk] = (header, payload, nano)
        print("Stored pending message with EPK: \(epk.hexEncodedString())")

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

        // Store message data with detailed logging
        pendingMessages[epk] = (header, payload, nano)
        print("Stored pending message with EPK: \(epk.hexEncodedString())")

        // Send rewrap message
        let rewrapMessage = RewrapMessage(header: header)
        try await client.sendMessage(rewrapMessage.toData())
    }

    private func handleRewrappedKey(_ data: Data) async throws {
        print("\nDecrypting rewrapped key:")

        let identifier = data.prefix(33)
        print("- EPK: \(identifier.hexEncodedString())")

        // Find corresponding message
        guard let (header, payload, nano) = pendingMessages.removeValue(forKey: identifier) else {
            print("❌ No pending message found for EPK")
            throw ArkavoError.messageError("No pending message found")
        }
        print("✅ Found pending message")

        // Extract key components
        let keyData = data.suffix(60)
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16
        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

        print("Key components:")
        print("- Nonce: \(nonce.hexEncodedString())")
        print("- Rewrapped key: \(rewrappedKey.hexEncodedString())")
        print("- Auth tag: \(authTag.hexEncodedString())")

        // Decrypt the key
        let symmetricKey = try client.decryptRewrappedKey(
            nonce: nonce,
            rewrappedKey: rewrappedKey,
            authTag: authTag
        )
        print("✅ Decrypted symmetric key")

        // Decrypt the message content
        let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
        print("✅ Decrypted payload of size: \(decryptedData.count)")

        // Check if decrypted data is a valid URL string
        if let urlString = String(data: decryptedData, encoding: .utf8) {
            print("Decrypted URL: \(urlString)")
        }

        // Broadcast the decrypted message
        NotificationCenter.default.post(
            name: .messageDecrypted,
            object: nil,
            userInfo: [
                "data": decryptedData,
                "header": header,
                "payload": payload,
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
}
