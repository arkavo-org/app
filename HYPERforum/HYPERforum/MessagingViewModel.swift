import ArkavoSocial
import Foundation
import SwiftUI

@MainActor
class MessagingViewModel: ObservableObject {
    @Published var messages: [ForumMessage] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var connectionState: ArkavoClientState = .disconnected

    private let arkavoClient: ArkavoClient
    private var currentUserId: String = ""
    private var currentUserName: String = ""

    // Encryption manager
    var encryptionManager: EncryptionManager?

    init(arkavoClient: ArkavoClient) {
        self.arkavoClient = arkavoClient
        setupClientDelegate()
    }

    func setCurrentUser(userId: String, userName: String) {
        currentUserId = userId
        currentUserName = userName
    }

    func setEncryptionManager(_ manager: EncryptionManager) {
        self.encryptionManager = manager
    }

    private func setupClientDelegate() {
        // Set up client delegate to receive messages
        arkavoClient.delegate = self
    }

    /// Send a message to a group (with optional encryption)
    func sendMessage(content: String, groupId: String) async {
        guard !content.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            // Create message payload
            let messageId = UUID().uuidString
            let payload = MessagePayload(
                type: "message",
                groupId: groupId,
                content: content,
                senderId: currentUserId,
                senderName: currentUserName,
                timestamp: Date().timeIntervalSince1970,
                messageId: messageId
            )

            // Encode to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(payload)

            // Check if encryption is enabled
            let shouldEncrypt = encryptionManager?.encryptionEnabled ?? false
            let isEncrypted: Bool

            if shouldEncrypt, let encryptionManager = encryptionManager {
                // Encrypt and send via encryptAndSendPayload (already sends)
                let policyData = encryptionManager.getPolicy(for: groupId)
                _ = try await arkavoClient.encryptAndSendPayload(
                    payload: jsonData,
                    policyData: policyData
                )
                isEncrypted = true
                print("Encrypted message sent: \(messageId)")
            } else {
                // Send plain via NATS message (0x05)
                try await arkavoClient.sendNATSMessage(jsonData)
                isEncrypted = false
                print("Plain message sent: \(messageId)")
            }

            // Add message to local list immediately (optimistic update)
            let message = ForumMessage(
                id: messageId,
                groupId: groupId,
                senderId: currentUserId,
                senderName: currentUserName,
                content: content,
                timestamp: Date(),
                threadId: nil,
                isEncrypted: isEncrypted
            )
            messages.append(message)

        } catch {
            self.error = "Failed to send message: \(error.localizedDescription)"
            print("Error sending message: \(error)")
        }

        isLoading = false
    }

    /// Send an encrypted message to a group
    func sendEncryptedMessage(content: String, groupId: String, policyData: Data) async {
        guard !content.isEmpty else { return }

        isLoading = true
        error = nil

        do {
            // Create message payload
            let messageId = UUID().uuidString
            let payload = MessagePayload(
                type: "message",
                groupId: groupId,
                content: content,
                senderId: currentUserId,
                senderName: currentUserName,
                timestamp: Date().timeIntervalSince1970,
                messageId: messageId
            )

            // Encode to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(payload)

            // Encrypt and send
            _ = try await arkavoClient.encryptAndSendPayload(
                payload: jsonData,
                policyData: policyData
            )

            // Add message to local list
            let message = ForumMessage(
                id: messageId,
                groupId: groupId,
                senderId: currentUserId,
                senderName: currentUserName,
                content: content,
                timestamp: Date(),
                threadId: nil,
                isEncrypted: true
            )
            messages.append(message)

            print("Encrypted message sent successfully: \(messageId)")
        } catch {
            self.error = "Failed to send encrypted message: \(error.localizedDescription)"
            print("Error sending encrypted message: \(error)")
        }

        isLoading = false
    }

    /// Load messages for a specific group
    func loadMessages(for groupId: String) {
        // Filter messages for this group
        // In a real implementation, this would fetch from a server or local database
        messages = messages.filter { $0.groupId == groupId }
    }

    /// Clear all messages
    func clearMessages() {
        messages.removeAll()
    }

    /// Get messages for a specific group
    func getMessages(for groupId: String) -> [ForumMessage] {
        messages.filter { $0.groupId == groupId }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - ArkavoClientDelegate

extension MessagingViewModel: ArkavoClientDelegate {
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        connectionState = state
        print("Connection state changed: \(state)")
    }

    func clientDidReceiveMessage(_ client: ArkavoClient, message: Data) {
        print("Received message: \(message.count) bytes")

        // Parse the message
        guard let messageType = message.first else {
            print("Invalid message: no type byte")
            return
        }

        print("Message type: 0x\(String(format: "%02X", messageType))")

        // Handle NATS messages (0x05 or 0x06)
        if messageType == 0x05 || messageType == 0x06 {
            handleNATSMessage(message.dropFirst())
        }
    }

    func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        self.error = error.localizedDescription
        print("Client error: \(error)")
    }

    private func handleNATSMessage(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(MessagePayload.self, from: data)

            // Create message from payload
            let message = ForumMessage(
                id: payload.messageId,
                groupId: payload.groupId,
                senderId: payload.senderId,
                senderName: payload.senderName,
                content: payload.content,
                timestamp: Date(timeIntervalSince1970: payload.timestamp),
                threadId: nil,
                isEncrypted: false
            )

            // Only add if not already in list (avoid duplicates from echo)
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                print("Added new message from \(message.senderName)")
            }
        } catch {
            print("Failed to decode NATS message: \(error)")
        }
    }
}
