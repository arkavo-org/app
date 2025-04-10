import Foundation
import OpenTDFKit
import SwiftUI

// MARK: - P2P Message Extension for ChatViewModel

extension ChatViewModel {
    // Example for how ChatViewModel would be updated to use P2PClient
    // This is a demonstration extension - you would integrate this into the actual ChatViewModel

    /// Binds a P2PClient to this ChatViewModel
    func bindP2PClient(_ p2pClient: P2PClient) {
        // Set up P2PClient delegate
        p2pClient.delegate = self

        // Store p2pClient reference for later use
        self.p2pClient = p2pClient
    }

    /// Sends a message using P2PClient instead of direct P2P implementation
    func sendP2PMessageUsingClient(_ content: String, stream: Stream) async throws {
        guard let p2pClient else {
            throw ChatError.missingTDFClient
        }

        print("ChatViewModel: Sending P2P message via P2PClient")

        // Use P2PClient to send the message
        let nanoTDFData = try await p2pClient.sendMessage(content, toStream: stream.publicID)

        // Message is already persisted by P2PClient and will be shown in the UI
        print("ChatViewModel: P2P message sent successfully")
    }

    /// Sends a direct message to a specific peer using P2PClient
    func sendDirectMessageUsingClient(_ content: String, toPeer peerProfile: Profile) async throws {
        guard let p2pClient else {
            throw ChatError.missingTDFClient
        }

        print("ChatViewModel: Sending direct P2P message via P2PClient")

        // Use P2PClient to send the direct message
        let nanoTDFData = try await p2pClient.sendDirectMessage(
            content,
            toPeer: peerProfile.publicID,
            inStream: streamPublicID
        )

        // Message is already persisted by P2PClient and will be shown in the UI
        print("ChatViewModel: Direct P2P message sent successfully")
    }

    /// Handles decryption using P2PClient
    func decryptMessageUsingClient(_ nanoTDFData: Data) async throws -> Data {
        guard let p2pClient else {
            throw ChatError.missingTDFClient
        }

        return try await p2pClient.decryptMessage(nanoTDFData)
    }
}

// MARK: - P2PClientDelegate Implementation

extension ChatViewModel: P2PClientDelegate {
    func clientDidReceiveMessage(_: P2PClient, streamID: Data, messageData: Data, from profile: Profile) {
        // Only process messages for this ChatViewModel's stream
        guard streamID == streamPublicID else {
            return
        }

        // Process the message data
        Task {
            do {
                let thoughtModel = try ThoughtServiceModel.deserialize(from: messageData)

                let displayContent = processContent(thoughtModel.content, mediaType: thoughtModel.mediaType)
                let timestamp = Date()

                let message = ChatMessage(
                    id: thoughtModel.publicID.base58EncodedString,
                    userId: profile.publicID.base58EncodedString,
                    username: profile.name,
                    content: displayContent,
                    timestamp: timestamp,
                    attachments: [],
                    reactions: [],
                    isPinned: false,
                    publicID: thoughtModel.publicID,
                    creatorPublicID: profile.publicID,
                    mediaType: thoughtModel.mediaType,
                    rawContent: thoughtModel.content
                )

                // Avoid adding duplicates
                if !messages.contains(where: { $0.id == message.id }) {
                    messages.append(message)
                    messages.sort { $0.timestamp < $1.timestamp }
                }
            } catch {
                print("Error processing received P2P message: \(error)")
            }
        }
    }

    func clientDidChangeConnectionStatus(_: P2PClient, status: P2PConnectionStatus) {
        // Update UI or other state based on connection status
        Task { @MainActor in
            switch status {
            case let .connected(peerCount):
                // Update UI to show connected peers
                print("P2P connected with \(peerCount) peers")
            case .connecting:
                // Show connecting status
                print("P2P connecting...")
            case .disconnected:
                // Show disconnected status
                print("P2P disconnected")
            case let .failed(error):
                // Show error
                print("P2P connection failed: \(error)")
            }
        }
    }

    func clientDidUpdateKeyStatus(_: P2PClient, localKeys: Int, totalCapacity: Int) {
        // Update UI to show key status if needed
        print("P2P key status: \(localKeys)/\(totalCapacity)")
    }

    func clientDidEncounterError(_: P2PClient, error: Error) {
        // Handle errors from P2PClient
        print("P2P error: \(error)")
    }
}
