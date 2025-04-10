import FlatBuffers
import Foundation
import MultipeerConnectivity
import OpenTDFKit
import SwiftUI

/*
 * This file demonstrates how the ChatViewModel would be updated to use the P2PClient abstraction.
 *
 * HOW TO INTEGRATE:
 * 1. Update the ChatViewModel class to include a p2pClient property
 * 2. Modify the init() method to get/create a P2PClient instance
 * 3. Replace the existing P2P code with calls to the P2PClient
 * 4. Add the P2PClientDelegate implementation
 */

// MARK: - Updated ChatViewModel with P2PClient support

/*
 @MainActor
 class ChatViewModel: ObservableObject {
     let client: ArkavoClient
     let account: Account
     let profile: Profile
     let streamPublicID: Data
     @Published var messages: [ChatMessage] = []
     private var notificationObservers: [NSObjectProtocol] = []
     private static var instanceCount = 0
     private let instanceId: Int

     // NEW: P2PClient reference
     private var p2pClient: P2PClient?

     // The rest of the properties...

     init(client: ArkavoClient, account: Account, profile: Profile, streamPublicID: Data) {
         Self.instanceCount += 1
         instanceId = Self.instanceCount
         print("🔵 Initializing ChatViewModel #\(instanceId)")

         self.client = client
         self.account = account
         self.profile = profile
         self.streamPublicID = streamPublicID

         // NEW: Get P2PClient from factory
         self.p2pClient = ViewModelFactory.shared.getP2PClient()

         setupNotifications()

         // Load existing thoughts for this stream
         Task {
             await loadExistingMessages()
             // NEW: Setup as P2PClient delegate
             if let p2pClient = self.p2pClient {
                 p2pClient.delegate = self
             }
         }
     }

     deinit {
         notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
         print("🔴 Deinitializing ChatViewModel #\(instanceId)")
         Self.instanceCount -= 1
     }

     // MARK: - Message Sending

     func sendMessage(content: String) async throws {
         print("ChatViewModel #\(instanceId): sendMessage called.")
         guard !content.isEmpty else { return }

         // Check if this is a direct message chat
         if let directProfile = directMessageProfile {
             print("ChatViewModel #\(instanceId): Sending as direct message to \(directProfile.name)")
             try await sendDirectMessageUsingClient(content, toPeer: directProfile)
             return
         }

         // Check if this is a general InnerCircle (P2P) stream
         if let stream = try? await PersistenceController.shared.fetchStream(withPublicID: streamPublicID),
            stream.isInnerCircleStream
         {
             print("ChatViewModel #\(instanceId): Sending as general P2P message in stream \(stream.name)")
             try await sendP2PMessageUsingClient(content, stream: stream)
             return
         }

         // Otherwise, send as a regular (non-P2P) message via the client/websocket
         print("ChatViewModel #\(instanceId): Sending as regular message via client.")
         try await sendRegularMessage(content: content)
     }

     // MARK: - Using P2PClient for P2P messages

     /// Sends a P2P message using P2PClient
     private func sendP2PMessageUsingClient(_ content: String, stream: Stream) async throws {
         guard let p2pClient = p2pClient else {
             throw ChatError.missingTDFClient
         }

         // Simply use P2PClient to handle message sending, encryption, and persistence
         let nanoTDFData = try await p2pClient.sendMessage(content, toStream: stream.publicID)

         // Add message to local UI immediately (optional if P2PClient already handles this)
         addLocalChatMessage(content: content, thoughtPublicID: UUID().uuidStringData, timestamp: Date(), isP2P: true)
     }

     /// Sends a direct message using P2PClient
     private func sendDirectMessageUsingClient(_ content: String, toPeer peerProfile: Profile) async throws {
         guard let p2pClient = p2pClient else {
             throw ChatError.missingTDFClient
         }

         // Use P2PClient to handle direct message sending, encryption, and persistence
         let nanoTDFData = try await p2pClient.sendDirectMessage(
             content,
             toPeer: peerProfile.publicID,
             inStream: streamPublicID
         )

         // Add message to local UI immediately (optional if P2PClient already handles this)
         addLocalChatMessage(content: content, thoughtPublicID: UUID().uuidStringData, timestamp: Date(), isP2P: true)
     }

     // MARK: - Existing methods that remain unchanged
     // ...

 }

 // MARK: - P2PClientDelegate Implementation

 extension ChatViewModel: P2PClientDelegate {

     func clientDidReceiveMessage(_ client: P2PClient, streamID: Data, messageData: Data, from profile: Profile) {
         // Only process messages for this ChatViewModel's stream
         guard streamID == self.streamPublicID else {
             return
         }

         // Process the message data to display in UI
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

     func clientDidChangeConnectionStatus(_ client: P2PClient, status: P2PConnectionStatus) {
         // Update UI or other state based on connection status
         Task { @MainActor in
             // This would update UI components showing connection status
         }
     }

     func clientDidUpdateKeyStatus(_ client: P2PClient, localKeys: Int, totalCapacity: Int) {
         // Update UI to show key status if needed
         // This could update a progress indicator or status label
     }

     func clientDidEncounterError(_ client: P2PClient, error: Error) {
         // Handle errors from P2PClient
         print("P2P error in ChatViewModel #\(instanceId): \(error)")
         // Potentially show an error alert or update UI
     }
 }

 // Helper extension for UUID
 extension UUID {
     var uuidStringData: Data {
         // Convert UUID to Data for use as publicID
         withUnsafeBytes(of: uuid) { Data($0) }
     }
 }
 */

// This file serves as a reference for how to update ChatViewModel to use P2PClient.
// It is commented out to avoid compilation issues but shows the necessary changes.
