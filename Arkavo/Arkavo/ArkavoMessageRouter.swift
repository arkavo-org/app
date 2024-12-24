import ArkavoSocial
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
                case 0x04: // Rewrapped key
                    try await handleRewrappedKey(messageData)

                case 0x05: // NATS message
                    try await handleNATSMessage(messageData, type: .message)

                case 0x06: // NATS event
                    try await handleNATSMessage(messageData, type: .event)

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

    private func handleNATSMessage(_ data: Data, type: NATSMessageType) async throws {
        // Create a deep copy of the data
        let copiedData = Data(data)
        let parser = BinaryParser(data: copiedData)
        let header = try parser.parseHeader()
        let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
        let nano = NanoTDF(header: header, payload: payload, signature: nil)

        let epk = header.ephemeralPublicKey
        print("Parsed NATS \(type) - EPK: \(epk.hexEncodedString())")

        // Store message data
        pendingMessages[epk] = (header, payload, nano)

        // Broadcast receipt of message
        NotificationCenter.default.post(
            name: type == .message ? .natsMessageReceived : .natsEventReceived,
            object: nil,
            userInfo: [
                "data": data,
                "header": header,
                "payload": payload,
            ]
        )

        // Send rewrap message
        let rewrapMessage = RewrapMessage(header: header)
        try await client.sendMessage(rewrapMessage.toData())
    }

    private func handleRewrappedKey(_ data: Data) async throws {
        print("\nHandling rewrapped key message of length: \(data.count)")

        // Handle DENY response
        guard data.count == 93 else {
            if data.count == 33 {
                let identifier = data
                NotificationCenter.default.post(
                    name: .rewrapDenied,
                    object: nil,
                    userInfo: ["identifier": identifier]
                )
                return
            }
            throw ArkavoError.messageError("Invalid rewrapped key length: \(data.count)")
        }

        // Extract components
        let identifier = data.prefix(33)
        let keyData = data.suffix(60)
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16
        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

        // Find corresponding message
        guard let (header, payload, nano) = pendingMessages.removeValue(forKey: identifier) else {
            throw ArkavoError.messageError("No pending message found for EPK: \(identifier.hexEncodedString())")
        }

        // Decrypt the key
        let symmetricKey = try client.decryptRewrappedKey(
            nonce: nonce,
            rewrappedKey: rewrappedKey,
            authTag: authTag
        )

        // Decrypt the message content
        let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)

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

// MARK: - Supporting Types

enum NATSMessageType {
    case message
    case event
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
}
