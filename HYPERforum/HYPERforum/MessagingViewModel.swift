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

    // Encryption manager (required for secure messaging)
    private(set) var encryptionManager: EncryptionManager

    // Message deduplication
    private var messageIds: Set<String> = []
    private var pendingMessages: Set<String> = []

    init(arkavoClient: ArkavoClient, encryptionManager: EncryptionManager) {
        self.arkavoClient = arkavoClient
        self.encryptionManager = encryptionManager
        setupClientDelegate()
    }

    func setCurrentUser(userId: String, userName: String) {
        guard !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "User ID and name cannot be empty"
            return
        }
        currentUserId = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        currentUserName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates message input before sending
    private func validateMessageInput(content: String, groupId: String) throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate content
        guard !trimmedContent.isEmpty else {
            throw ValidationError.emptyContent
        }
        guard trimmedContent.count <= 10000 else {
            throw ValidationError.contentTooLong
        }

        // Validate groupId
        guard !groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.invalidGroupId
        }
        guard UUID(uuidString: groupId) != nil else {
            throw ValidationError.invalidGroupId
        }

        // Validate user identity is set
        guard !currentUserId.isEmpty, !currentUserName.isEmpty else {
            throw ValidationError.userNotSet
        }
    }

    enum ValidationError: LocalizedError {
        case emptyContent
        case contentTooLong
        case invalidGroupId
        case userNotSet

        var errorDescription: String? {
            switch self {
            case .emptyContent: return "Message cannot be empty"
            case .contentTooLong: return "Message exceeds maximum length of 10,000 characters"
            case .invalidGroupId: return "Invalid group ID"
            case .userNotSet: return "User identity not set"
            }
        }
    }

    private func setupClientDelegate() {
        // Set up client delegate to receive messages
        arkavoClient.delegate = self
    }

    /// Send a message to a group (with optional encryption)
    func sendMessage(content: String, groupId: String) async {
        // Validate input
        do {
            try validateMessageInput(content: content, groupId: groupId)
        } catch {
            self.error = error.localizedDescription
            return
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        error = nil

        do {
            // Create message payload
            let messageId = UUID().uuidString
            let payload = MessagePayload(
                type: "message",
                groupId: groupId,
                content: trimmedContent,
                senderId: currentUserId,
                senderName: currentUserName,
                timestamp: Date().timeIntervalSince1970,
                messageId: messageId
            )

            // Encode to JSON
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(payload)

            // Check if encryption is enabled
            let shouldEncrypt = encryptionManager.encryptionEnabled
            let isEncrypted: Bool

            if shouldEncrypt {
                // Encrypt and send via encryptAndSendPayload (already sends)
                let policyData = try encryptionManager.getPolicy(for: groupId)
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
                content: trimmedContent,
                timestamp: Date(),
                threadId: nil,
                isEncrypted: isEncrypted
            )

            // Track as pending to avoid duplication when echo arrives
            pendingMessages.insert(messageId)
            messageIds.insert(messageId)
            messages.append(message)

        } catch {
            self.error = "Failed to send message: \(error.localizedDescription)"
            print("Error sending message: \(error)")
        }

        isLoading = false
    }

    /// Send an encrypted message to a group
    func sendEncryptedMessage(content: String, groupId: String, policyData: Data) async {
        // Validate input
        do {
            try validateMessageInput(content: content, groupId: groupId)
        } catch {
            self.error = error.localizedDescription
            return
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)

        isLoading = true
        error = nil

        do {
            // Create message payload
            let messageId = UUID().uuidString
            let payload = MessagePayload(
                type: "message",
                groupId: groupId,
                content: trimmedContent,
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
                content: trimmedContent,
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
        messageIds.removeAll()
        pendingMessages.removeAll()
    }

    /// Clean up old pending messages (called periodically)
    func cleanupPendingMessages() {
        // Remove pending messages that are already in the message list
        pendingMessages = pendingMessages.filter { messageId in
            !messages.contains { $0.id == messageId }
        }
        print("Cleaned up pending messages: \(pendingMessages.count) remaining")
    }

    /// Get messages for a specific group
    func getMessages(for groupId: String) -> [ForumMessage] {
        messages.filter { $0.groupId == groupId }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - ArkavoClientDelegate

extension MessagingViewModel: ArkavoClientDelegate {
    @MainActor
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState) {
        connectionState = state
        print("Connection state changed: \(state)")
    }

    @MainActor
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

    @MainActor
    func clientDidReceiveError(_ client: ArkavoClient, error: Error) {
        self.error = error.localizedDescription
        print("Client error: \(error)")
    }

    private func handleNATSMessage(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            let payload = try decoder.decode(MessagePayload.self, from: data)

            // Check if this message is already known (deduplication)
            guard !messageIds.contains(payload.messageId) else {
                // If it was pending, mark as confirmed
                if pendingMessages.contains(payload.messageId) {
                    pendingMessages.remove(payload.messageId)
                    print("Confirmed pending message: \(payload.messageId)")
                }
                return
            }

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

            // Add to tracking and message list
            messageIds.insert(message.id)
            messages.append(message)
            print("Added new message from \(message.senderName)")

        } catch {
            print("Failed to decode NATS message: \(error)")
        }
    }
}
