import ArkavoSocial
import Combine // Import Combine for Timer
import FlatBuffers
import MultipeerConnectivity
import OpenTDFKit
import SwiftUI
import UIKit

// MARK: - Models

// Placeholder for the detailed info expected from PeerDiscoveryManager
// Moved definition to GroupViewModel.swift for better organization
// struct LocalKeyStoreInfo {
//     let validKeyCount: Int
//     let expiredKeyCount: Int
//     let capacity: Int // Keep capacity if available, otherwise use constant
// }

@MainActor
final class GroupViewModel: ViewModel, ObservableObject { // Removed ArkavoClientDelegate conformance
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var streams: [Stream] = []
    @Published var selectedStream: Stream?
    @Published var connectionState: ArkavoClientState = .disconnected
    // Track pending streams by their ephemeral public key
    private var pendingStreams: [Data: (header: Header, payload: Payload, nano: NanoTDF)] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    // One-time TDF is now always enabled

    @MainActor
    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        Task { @MainActor in
            await self.setup()
        }
    }

    private func setup() async {
        setupNotifications()
        await loadStreams()
        print("GroupViewModel initialized:")
        print("- Client delegate set: \(client.delegate != nil)") // Delegate is set on P2PGroupViewModel
        print("- Account streams count: \(account.streams.count)")
        print("- Profile name: \(profile.name)")
    }

    private func loadStreams() async {
        // Get all account streams
        let allStreams = account.streams

        // Filter to only include streams with no initial thoughts (group chat streams)
        streams = allStreams.filter { stream in
            // If there are no sources (initial thoughts), it's a group chat stream
            stream.isGroupChatStream
        }
    }

    private func setupNotifications() {
        print("GroupViewModel: setupNotifications")
        // Clean up any existing observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        // Add observers
        // Note: .arkavoClientStateChanged might be redundant if connectionState is driven by PeerDiscoveryManager
        let stateObserver = NotificationCenter.default.addObserver(
            forName: .arkavoClientStateChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let state = notification.userInfo?["state"] as? ArkavoClientState else { return }
            Task { @MainActor [weak self] in
                // Consider if this should be driven by PeerDiscoveryManager.connectionStatus instead
                self?.connectionState = state
            }
        }
        notificationObservers.append(stateObserver)

        // Observer for decrypted messages (likely handled by P2PGroupViewModel now)
        // Keep this for now in case GroupViewModel needs to react to specific decrypted data types
        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy
            else {
                print("❌ No data in decrypted message notification")
                return
            }

            Task { @MainActor [weak self] in
                do {
                    // Example: Handle specific policy types relevant to GroupViewModel
                    if policy.type == .streamProfile {
                        print("\n=== GroupViewModel Processing Decrypted Stream Data ===")
                        print("Data size: \(data.count)")
                        print("Policy type: \(policy.type)")
                        try await self?.handleStreamData(data)
                    }
                    // Add other policy type handling if needed by GroupViewModel
                } catch {
                    print("❌ Error processing stream data in GroupViewModel: \(error)")
                    print("Error details: \(String(describing: error))")
                }
            }
        }
        notificationObservers.append(messageObserver)

        // Observer for NATS messages (potentially handled by P2PGroupViewModel or ChatViewModel)
        // Keep this for now in case GroupViewModel needs to react directly to NATS messages
        let natsObserver = NotificationCenter.default.addObserver(
            forName: .natsMessageReceived,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data else { return }
            Task { @MainActor [weak self] in
                print("\n=== GroupViewModel Handling NATS Message ===")
                // Decide if GroupViewModel needs to handle this or if it's delegated elsewhere
                await self?.handleNATSMessage(data) // Keep handler for now
            }
        }
        notificationObservers.append(natsObserver)

        // NEW: Observer for shared profiles saved locally
        let profileSavedObserver = NotificationCenter.default.addObserver(
            forName: .profileSharedAndSaved,
            object: nil,
            queue: .main // Ensure handler runs on main thread
        ) { [weak self] notification in
            guard let profilePublicID = notification.userInfo?["profilePublicID"] as? Data else {
                print("❌ ProfileShare: Received .profileSharedAndSaved notification without profilePublicID.")
                return
            }
            Task { @MainActor [weak self] in
                await self?.handleProfileSharedAndSaved(profilePublicID: profilePublicID)
            }
        }
        notificationObservers.append(profileSavedObserver)

        // NEW: Observer for shared KeyStores saved locally
        let keyStoreSavedObserver = NotificationCenter.default.addObserver(
            forName: .keyStoreSharedAndSaved,
            object: nil,
            queue: .main // Ensure handler runs on main thread
        ) { notification in
            guard let profilePublicID = notification.userInfo?["profilePublicID"] as? Data else {
                print("❌ KeyStoreShare: Received .keyStoreSharedAndSaved notification without profilePublicID.")
                return
            }
            Task { @MainActor in
                // Optionally handle this notification, e.g., update UI to show peer has KeyStore
                print("GroupViewModel: Handling .keyStoreSharedAndSaved notification for ID: \(profilePublicID.base58EncodedString)")
                // Example: Refresh peer list or specific peer row UI
            }
        }
        notificationObservers.append(keyStoreSavedObserver)
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func requestStream(withPublicID publicID: Data) async throws -> Stream? {
        print("Requesting stream with publicID: \(publicID.base58EncodedString)")

        // Check if we already have the stream locally
        if let existingStream = try await PersistenceController.shared.fetchStream(withPublicID: publicID) {
            print("Found existing stream: \(existingStream.profile.name)")
            return existingStream
        }

        let accountProfilePublicID = profile.publicID

        // Create FlatBuffer request
        var builder = FlatBufferBuilder(initialSize: 384)

        // Create UserEvent
        let userEventOffset = Arkavo_UserEvent.createUserEvent(
            &builder,
            sourceType: .accountProfile,
            targetType: .streamProfile,
            sourceIdVectorOffset: builder.createVector(bytes: accountProfilePublicID),
            targetIdVectorOffset: builder.createVector(bytes: publicID)
        )

        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .invite,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .userevent,
            dataOffset: userEventOffset
        )

        builder.finish(offset: eventOffset)
        let eventData = builder.data

        // Send event and wait for response
        print("Sending stream request event")
        try await client.sendNATSEvent(eventData)

        // Wait for potential response (with timeout)
        let timeoutSeconds: UInt64 = 5
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < TimeInterval(timeoutSeconds) {
            // Check if stream has been created
            if let stream = try await PersistenceController.shared.fetchStream(withPublicID: publicID) {
                print("Stream received and saved: \(stream.profile.name)")
                return stream
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        }

        print("No stream found after timeout")
        return nil
    }

    func handleStreamData(_ data: Data) async throws {
        print("\n=== handleStreamData ===")
        print("Received data size: \(data.count)")
        var buffer = ByteBuffer(data: data)

        // Verify and parse EntityRoot
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_EntityRoot.verify(&verifier, at: Int(rootOffset), of: Arkavo_EntityRoot.self)

        let entityRoot = Arkavo_EntityRoot(buffer, o: Int32(rootOffset))
        guard let arkStream = entityRoot.entity(type: Arkavo_Stream.self) else {
            throw ArkavoError.invalidResponse
        }

        // Extract required fields
        guard let streamPublicId = arkStream.publicId?.id,
              let creatorPublicId = arkStream.creatorPublicId?.id,
              let streamProfile = arkStream.profile,
              let streamName = streamProfile.name
        else {
            throw ArkavoError.invalidResponse
        }

        let newStreamPublicID = Data(streamPublicId)
        print("Processing stream: \(streamName) with ID: \(newStreamPublicID.base58EncodedString)")

        // Check if stream already exists
        if let existingStream = try await PersistenceController.shared.fetchStream(withPublicID: newStreamPublicID) {
            print("Stream already exists: \(existingStream.profile.name)")
            return
        }

        // Create new stream
        let stream = Stream(
            publicID: Data(streamPublicId),
            creatorPublicID: Data(creatorPublicId),
            profile: Profile(
                name: streamName,
                blurb: streamProfile.blurb ?? "", // Use blurb from streamProfile, not self.profile
                interests: streamProfile.interests ?? "",
                location: streamProfile.location ?? "",
                hasHighEncryption: streamProfile.encryptionLevel == .el2,
                hasHighIdentityAssurance: streamProfile.identityAssuranceLevel == .ial2
            ),
            policies: Policies(
                admission: .open, // Default policy, adjust as needed
                interaction: .open, // Default policy, adjust as needed
                age: .forAll // Default policy, adjust as needed
            )
        )

        // First save the stream
        try PersistenceController.shared.saveStream(stream)
        print("Stream saved: \(stream.publicID.base58EncodedString)")

        // Then update account and save changes
        if !account.streams.contains(where: { $0.publicID == stream.publicID }) {
            account.streams.append(stream)
            try await PersistenceController.shared.saveChanges()
            print("Account updated with new stream")
        }

        // Update local streams array if not already present
        if !streams.contains(where: { $0.publicID == stream.publicID }) {
            streams.append(stream)
            print("Local streams array updated")
        }

        print("Stream handling completed successfully: \(stream.publicID.base58EncodedString)")
    }

    func sendStreamCacheEvent(stream: Stream) async throws {
        // Create Stream using FlatBuffers
        var builder = FlatBufferBuilder(initialSize: 1024)

        // Create nested structures first
        let nameOffset = builder.create(string: stream.profile.name)
        let blurbOffset = builder.create(string: stream.profile.blurb ?? "")
        let interestsOffset = builder.create(string: stream.profile.interests)
        let locationOffset = builder.create(string: stream.profile.location)

        // Create Profile
        let profileOffset = Arkavo_Profile.createProfile(
            &builder,
            nameOffset: nameOffset,
            blurbOffset: blurbOffset,
            interestsOffset: interestsOffset,
            locationOffset: locationOffset,
            locationLevel: .approximate,
            identityAssuranceLevel: stream.profile.hasHighIdentityAssurance ? .ial2 : .ial1,
            encryptionLevel: stream.profile.hasHighEncryption ? .el2 : .el1
        )

        // Create Activity
        let activityOffset = Arkavo_Activity.createActivity(
            &builder,
            dateCreated: Int64(Date().timeIntervalSince1970),
            expertLevel: .novice,
            activityLevel: .low,
            trustLevel: .low
        )

        // Create PublicIds
        let publicIdVector = builder.createVector(bytes: stream.publicID)
        let publicIdOffset = Arkavo_PublicId.createPublicId(&builder, idVectorOffset: publicIdVector)
        let creatorPublicIdVector = builder.createVector(bytes: stream.creatorPublicID)
        let creatorPublicIdOffset = Arkavo_PublicId.createPublicId(&builder, idVectorOffset: creatorPublicIdVector)

        // Create Stream
        let streamOffset = Arkavo_Stream.createStream(
            &builder,
            publicIdOffset: publicIdOffset,
            profileOffset: profileOffset,
            activityOffset: activityOffset,
            creatorPublicIdOffset: creatorPublicIdOffset,
            membersPublicIdVectorOffset: Offset(),
            streamLevel: .sl1
        )

        // Create EntityRoot with Stream as the entity
        let entityRootOffset = Arkavo_EntityRoot.createEntityRoot(
            &builder,
            entityType: .stream,
            entityOffset: streamOffset
        )

        builder.finish(offset: entityRootOffset)
        let nanoPayload = builder.data

        let targetPayload = try await client.encryptRemotePolicy(payload: nanoPayload, remotePolicyBody: ArkavoPolicy.PolicyType.streamProfile.rawValue)

        // Create CacheEvent
        builder = FlatBufferBuilder(initialSize: 1024)
        let targetIdVector = builder.createVector(bytes: stream.publicID)
        let targetPayloadVector = builder.createVector(bytes: targetPayload)

        let cacheEventOffset = Arkavo_CacheEvent.createCacheEvent(
            &builder,
            targetIdVectorOffset: targetIdVector,
            targetPayloadVectorOffset: targetPayloadVector,
            ttl: 604_800, // 1 week TTL
            oneTimeAccess: false
        )

        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .cache,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .cacheevent,
            dataOffset: cacheEventOffset
        )

        builder.finish(offset: eventOffset)
        let data = builder.data

        try await client.sendNATSEvent(data)
    }

    // --- REMOVED ArkavoClientDelegate Methods ---
    // nonisolated func clientDidChangeState(_: ArkavoSocial.ArkavoClient, state: ArkavoSocial.ArkavoClientState) { ... }
    // nonisolated func clientDidReceiveMessage(_: ArkavoClient, message: Data) { ... }
    // nonisolated func clientDidReceiveError(_: ArkavoSocial.ArkavoClient, error: any Error) { ... }
    // --- END REMOVED ArkavoClientDelegate Methods ---

    private func handleNATSMessage(_ data: Data) async {
        do {
            // Create a deep copy of the data
            let copiedData = Data(data)
            let parser = BinaryParser(data: copiedData)
            let header = try parser.parseHeader()
            print("\n=== Processing NATS Message ===")
            print("Checking content rating...")
            print("Message content rating: \(header.policy)")
            let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
            let nano = NanoTDF(header: header, payload: payload, signature: nil)

            let epk = header.ephemeralPublicKey
            print("Parsed NATS message - EPK: \(epk.hexEncodedString())")

            // Store with correct types
            pendingStreams[epk] = (
                header: header,
                payload: payload,
                nano: nano
            )

            // Send rewrap message to get the key
            print("Sending rewrap message for EPK: \(epk.hexEncodedString())")
            let rewrapMessage = RewrapMessage(header: header)
            try await client.sendMessage(rewrapMessage.toData())

        } catch {
            print("Error processing NATS message: \(error)")
        }
    }

    private func handleRewrappedKeyMessage(_ data: Data) async {
        print("\n=== handleRewrappedKeyMessage ===")
        let identifier = data.prefix(33)
        print("Looking for stream with EPK: \(identifier.hexEncodedString())")

        // Find corresponding stream data
        guard let (_, _, nano) = pendingStreams.removeValue(forKey: identifier) else {
            print("❌ No pending stream found for EPK: \(identifier.hexEncodedString())")
            return
        }

        print("✅ Found matching stream data!")
        let keyData = data.suffix(60)
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16
        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

        do {
//            print("Decrypting rewrapped key...")
            let symmetricKey = try client.decryptRewrappedKey(
                nonce: nonce,
                rewrappedKey: rewrappedKey,
                authTag: authTag
            )
//            print("Successfully decrypted rewrapped key")

            // Decrypt the stream data
//            print("Decrypting stream data...")
            let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
//            print("Successfully decrypted stream data of size: \(decryptedData.count)")

            // Now process the decrypted FlatBuffer data
//            print("Processing decrypted stream data...")
            try await handleStreamData(decryptedData)

        } catch {
            print("❌ Error processing rewrapped key: \(error)")
        }
    }

    // NEW: Handle the notification that a shared profile was saved
    private func handleProfileSharedAndSaved(profilePublicID: Data) async {
        print("GroupViewModel: Handling .profileSharedAndSaved notification for ID: \(profilePublicID.base58EncodedString)")
        do {
            // 1. Find the local user's "InnerCircle" stream
            // This assumes the user has exactly one stream named "InnerCircle".
            // A more robust implementation might involve selecting the target stream.
            guard let innerCircleStream = account.streams.first(where: { $0.isInnerCircleStream }) else {
                print("❌ ProfileShare: Could not find local 'InnerCircle' stream to add shared profile.")
                // Optionally inform the user
                return
            }
            print("   Found InnerCircle stream: \(innerCircleStream.profile.name)")

            // 2. Fetch the newly saved Profile from persistence
            guard let sharedProfile = try await PersistenceController.shared.fetchProfile(withPublicID: profilePublicID) else {
                print("❌ ProfileShare: Could not fetch the shared profile (\(profilePublicID.base58EncodedString)) from persistence after notification.")
                return
            }
            print("   Fetched shared profile: \(sharedProfile.name)")

            // 3. Add the profile to the stream's innerCircleProfiles (if not already present)
            if !innerCircleStream.isInInnerCircle(sharedProfile) {
                innerCircleStream.addToInnerCircle(sharedProfile)
                print("   Added profile \(sharedProfile.name) to InnerCircle stream members.")

                // 4. Save the changes to the stream
                try await PersistenceController.shared.saveChanges()
                print("   Saved changes to InnerCircle stream.")

                // 5. Post notification to refresh the UI
                NotificationCenter.default.post(name: .refreshInnerCircleMembers, object: nil)
                print("   Posted .refreshInnerCircleMembers notification.")

            } else {
                print("   Profile \(sharedProfile.name) is already in the InnerCircle stream. No changes needed.")
            }

        } catch {
            print("❌ ProfileShare: Error handling saved profile notification: \(error)")
            // Optionally inform the user
        }
    }
}

// MARK: - InnerCircle UI Constants and Enums

// Constants for consistent styling within InnerCircle related views
struct InnerCircleConstants {
    static let systemMargin: CGFloat = 16
    static let halfMargin: CGFloat = systemMargin / 2
    static let doubleMargin: CGFloat = systemMargin * 2

    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8

    static let minimumTouchTarget: CGFloat = 44

    // Typography
    static let headerFont: Font = .system(size: 20, weight: .bold)
    static let primaryTextFont: Font = .system(size: 17, weight: .regular)
    static let secondaryTextFont: Font = .system(size: 15, weight: .regular)
    static let statusIndicatorFont: Font = .system(size: 13, weight: .semibold)
    static let captionFont: Font = .system(size: 12, weight: .regular) // Example caption size

    // Colors (Examples based on guide)
    static let primaryActionColor: Color = .blue // #007AFF
    static let trustGreen: Color = Color(red: 52/255, green: 199/255, blue: 89/255) // #34C759
    static let trustYellow: Color = Color(red: 255/255, green: 204/255, blue: 0/255) // #FFCC00
    static let trustRed: Color = Color(red: 255/255, green: 59/255, blue: 48/255) // #FF3B30
    static let backgroundColor: Color = .black // #000000 (Assuming dark mode focus)
    static let cardBackgroundColor: Color = Color(.systemGray6) // #1C1C1E (Example dark mode card bg)
    static let primaryTextColor: Color = .white
    static let secondaryTextColor: Color = .gray
}

// Example Trust Status Enum (Needs actual implementation based on data model)
enum TrustStatus {
    case unknown, pending, verified, trusted, compromised

    var description: String {
        switch self {
        case .unknown: "Unknown"
        case .pending: "Verification Pending"
        case .verified: "Verified"
        case .trusted: "Trusted"
        case .compromised: "Compromised"
        }
    }

    var color: Color {
        switch self {
        case .unknown: InnerCircleConstants.secondaryTextColor
        case .pending: InnerCircleConstants.trustYellow
        case .verified: InnerCircleConstants.primaryActionColor
        case .trusted: InnerCircleConstants.trustGreen
        case .compromised: InnerCircleConstants.trustRed
        }
    }

    var icon: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .pending: "hourglass"
        case .verified: "checkmark.seal.fill"
        case .trusted: "lock.shield.fill"
        case .compromised: "exclamationmark.shield.fill"
        }
    }
}


// MARK: - Extensions

// Add notification name for refreshing InnerCircle members
extension Notification.Name {
    static let refreshInnerCircleMembers = Notification.Name("refreshInnerCircleMembers")
}

// MARK: - Main View

struct GroupView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: GroupViewModel = ViewModelFactory.shared.makeViewModel()
    // Observe the PeerDiscoveryManager for OT-TDF data
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @State private var isShareSheetPresented = false
    @State private var isPeerSearchActive = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Define systemMargin at the GroupView level
    private let systemMargin: CGFloat = 16

    // Static constant for the base URL used in sharing
    static let streamBaseURL = "https://app.arkavo.com/stream/"
    // Static constant for "just now" string
    static let justNowString = "just now"

    var body: some View {
        if sharedState.showCreateView {
            GroupCreateView(viewModel: viewModel)
        } else {
            mainContent
        }
    }

    // Breaking down the complex body into smaller views
    private var mainContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Stream list or loading view
                streamListView(geometry: geometry)

                // Chat overlay
                chatOverlayView
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let stream = viewModel.selectedStream {
                // Use the static constant to build the URL
                let urlString = "\(GroupView.streamBaseURL)\(stream.publicID.base58EncodedString)"
                if let url = URL(string: urlString) {
                    ShareSheet(
                        activityItems: [url],
                        isPresented: $isShareSheetPresented
                    )
                }
            }
        }
        // Refresh UI when key exchange states change
        .onChange(of: peerManager.peerKeyExchangeStates) { _, _ in
            // This ensures the UI updates when a state changes for any peer
            print("GroupView: Detected change in peerKeyExchangeStates")
        }
    }

    // Stream list or loading view
    private func streamListView(geometry: GeometryProxy) -> some View {
        Group {
            if viewModel.streams.isEmpty {
                emptyStreamView
            } else {
                streamScrollView(geometry: geometry)
            }
        }
    }

    // Empty state view
    private var emptyStreamView: some View {
        VStack {
            Spacer()
            WaveLoadingView(message: "Awaiting")
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { sharedState.isAwaiting = true }
        .onDisappear { sharedState.isAwaiting = false }
    }

    // Scrollable stream list - Refactored Structure
    private func streamScrollView(geometry: GeometryProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: InnerCircleConstants.systemMargin) { // Use constant

                // --- InnerCircle Section (P2P) ---
                innerCircleSection()
                    .padding(.horizontal, InnerCircleConstants.systemMargin) // Add horizontal padding to section

                // --- Regular Streams Section ---
                // Only show if there are non-InnerCircle streams
                let regularStreams = viewModel.streams.filter { !$0.isInnerCircleStream }
                if !regularStreams.isEmpty {
                    Section {
                        ForEach(regularStreams) { stream in
                            streamRow(stream: stream) // Keep existing streamRow for non-InnerCircle
                        }
                    } header: {
                        Text("Other Streams") // Example header for separation
                            .font(InnerCircleConstants.headerFont)
                            .foregroundColor(InnerCircleConstants.primaryTextColor)
                            .padding(.top, InnerCircleConstants.systemMargin)
                            .padding(.horizontal, InnerCircleConstants.systemMargin)
                    }
                }
            }
            .padding(.vertical, InnerCircleConstants.systemMargin) // Use constant
        }
        .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width) // Keep specific width
        .background(InnerCircleConstants.backgroundColor.ignoresSafeArea()) // Use constant color
    }

    // --- NEW: InnerCircle Section View ---
    private func innerCircleSection() -> some View {
        // Find the InnerCircle stream (assuming one exists)
        let innerCircleStream = viewModel.streams.first { $0.isInnerCircleStream }

        return VStack(spacing: 0) {
            // 1. Status Header (Connection + KeyStore)
            innerCircleStatusHeader()
                .background(InnerCircleConstants.cardBackgroundColor) // Use constant
                .cornerRadius(InnerCircleConstants.cornerRadius, corners: [.topLeft, .topRight]) // Use constant

            // 2. Peer Discovery Controls & List
            innerCirclePeerDiscoveryUI()
                .background(InnerCircleConstants.cardBackgroundColor) // Use constant
                .cornerRadius(InnerCircleConstants.cornerRadius, corners: [.bottomLeft, .bottomRight]) // Use constant

            // 3. InnerCircle Member List (if stream exists)
            // This part is now handled by InnerCircleView, which should be presented differently,
            // perhaps as a navigation destination or separate tab.
            // For now, we remove the direct member listing from here.
            // if let stream = innerCircleStream {
            //     InnerCircleView(stream: stream, peerManager: peerManager)
            //         .environmentObject(sharedState)
            //         .padding(.top, InnerCircleConstants.halfMargin) // Add space if needed
            // }
        }
        .clipShape(RoundedRectangle(cornerRadius: InnerCircleConstants.cornerRadius)) // Clip the whole Vstack
    }

    // --- NEW: InnerCircle Status Header View ---
    private func innerCircleStatusHeader() -> some View {
        HStack {
            // Connection Status Indicator (from existing helper)
            connectionStatusIndicator(status: peerManager.connectionStatus)

            Spacer()

            // Local KeyStore Status Indicator (Simplified)
            KeyStoreStatusIndicator(peerManager: peerManager)

        }
        .padding(InnerCircleConstants.systemMargin) // Use constant
    }

    // Individual stream row with InnerCircle UI if applicable
    private func streamRow(stream: Stream) -> some View {
        VStack(spacing: 0) {
            // Main card view for the stream
            GroupCardView(
                stream: stream,
                onSelect: {
                    viewModel.selectedStream = stream
                    sharedState.selectedStreamPublicID = stream.publicID
                    sharedState.showChatOverlay = true
                }
            )

            // --- START: Inner Circle Members List ---
            // Display members only if it's an InnerCircle stream
            if stream.isInnerCircleStream {
                VStack(alignment: .leading, spacing: 4) {
                    // Header for the members list
                    Text("Inner Circle Members")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)
                        .padding(.horizontal, systemMargin) // Use systemMargin

                    // Display message if no members
                    if stream.innerCircleProfiles.isEmpty {
                        Text("No members added yet.")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal, systemMargin) // Use systemMargin
                            .padding(.bottom, systemMargin / 2) // Use systemMargin multiple (8pt)
                    } else {
                        // List the members (sorted by name)
                        // Use LazyVStack for potentially long lists
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(stream.innerCircleProfiles.sorted { $0.name < $1.name }, id: \.id) { profile in
                                HStack {
                                    // Simple display: just the name
                                    Text("• \(profile.name)") // Add bullet point
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    // Optional: Add online/offline status indicator here later
                                    // You would need to check peerManager.connectedPeerProfiles
                                    // based on profile.publicID
                                }
                                .padding(.horizontal, systemMargin) // Use systemMargin
                            }
                        }
                        .padding(.bottom, systemMargin / 2) // Use systemMargin multiple (8pt)
                    }
                }
                // Use the secondary grouped background for this section
                .background(Color(.secondarySystemGroupedBackground))
                // Round bottom corners to match the card above if it's the last element
                .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
            }
            // --- END: Inner Circle Members List ---
        }
        // Apply corner radius to the entire VStack containing the card and members list
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // Inner Circle peer discovery UI (P2P related) - Refactored
    private func innerCirclePeerDiscoveryUI() -> some View {
        VStack(spacing: InnerCircleConstants.halfMargin) { // Use constant

            // --- NEW: Prominent Search CTA ---
            Button {
                Task { await togglePeerSearch() }
            } label: {
                HStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
                    Image(systemName: isPeerSearchActive ? "stop.circle.fill" : "antenna.radiowaves.left.and.right.circle.fill")
                        .font(.system(size: 22)) // Use guide size
                    Text(isPeerSearchActive ? "Stop Discovery" : "Discover Peers")
                        .font(InnerCircleConstants.primaryTextFont) // Use constant font
                        .fontWeight(.semibold) // Make text slightly bolder
                    if isPeerSearchActive {
                        Spacer() // Push pulse to right only when active
                        ProgressView().scaleEffect(0.8) // Simple pulse/activity indicator
                            .tint(InnerCircleConstants.primaryActionColor)
                    }
                }
                .padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
                .padding(.horizontal, InnerCircleConstants.systemMargin) // Use constant
                .frame(maxWidth: .infinity)
                .background(isPeerSearchActive ? InnerCircleConstants.trustRed.opacity(0.15) : InnerCircleConstants.primaryActionColor.opacity(0.15)) // Use constant colors
                .foregroundColor(isPeerSearchActive ? InnerCircleConstants.trustRed : InnerCircleConstants.primaryActionColor) // Use constant colors
                .cornerRadius(InnerCircleConstants.cornerRadius) // Use constant
            }
            .buttonStyle(.plain) // Remove default button chrome
            .padding(.horizontal, InnerCircleConstants.systemMargin) // Padding for the button
            .padding(.vertical, InnerCircleConstants.halfMargin) // Padding around button

            // Connected peers list view (or available devices)
            connectedPeersView // Display the list of connected/available peers

            // Removed KeyStore Status View
        }
        // Removed animation modifiers from here, apply to specific elements if needed
        // .animation(.easeInOut(duration: 0.3), value: isPeerSearchActive)
        // .animation(.easeInOut(duration: 0.3), value: peerManager.connectedPeers)
        // .animation(.easeInOut(duration: 0.3), value: peerManager.localKeyStoreInfo)
        // .animation(.easeInOut(duration: 0.3), value: peerManager.connectedPeerProfiles)
        // .animation(.easeInOut(duration: 0.3), value: peerManager.peerKeyExchangeStates)
    }

    // Toggle peer search state
    private func togglePeerSearch() async {
        isPeerSearchActive.toggle()

        if isPeerSearchActive {
            do {
                // Select this stream and start searching
                try await peerManager.setupMultipeerConnectivity()
                try peerManager.startSearchingForPeers()

                // Automatically present the browser controller for manual peer selection
                presentBrowserController() // Show browser by default
            } catch {
                // If there was an error starting peer search, show it to the user
                print("Failed to start peer search: \(error.localizedDescription)")
                // Update status via peerManager's published properties
                isPeerSearchActive = false // Revert state if failed
            }
        } else {
            // Stop searching
            peerManager.stopSearchingForPeers()
        }
    }

    // Connected peers list view
    private var connectedPeersView: some View {
        VStack(spacing: systemMargin / 2) { // Use systemMargin multiple (8pt)
            let peerCount = peerManager.connectedPeers.count
            let connectionStatus = peerManager.connectionStatus

            // Status bar with improved connection status display
            HStack {
                connectionStatusIndicator(status: connectionStatus)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                    Text("\(peerCount) \(peerCount == 1 ? "Peer" : "Peers")")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                }
            }
            .padding(.top, systemMargin * 0.375) // Use systemMargin multiple (~6pt)
            .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt)

            // Show search status banner when active
            if case .searching = connectionStatus {
                HStack {
                    Text("Broadcasting and listening...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
                .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt)
                .background(Color(.secondarySystemBackground).opacity(0.5))
                .cornerRadius(6)
            }

            // Show error message if there's an error
            if case let .failed(error) = connectionStatus {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error.localizedDescription).font(.caption).foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            // Divider if we have peers or specific states
            if peerCount > 0 || connectionStatus == .searching || connectionStatus == .connecting {
                Divider().padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
            }

            if peerCount > 0 {
                // Title for peers section
                Text("Nearby Devices")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt)
                    .padding(.bottom, systemMargin / 8) // Use systemMargin multiple (2pt)

                // Show list of connected peers using the refactored peerRow
                LazyVStack(spacing: InnerCircleConstants.halfMargin) { // Use LazyVStack and constant
                    // Use peerManager.connectedPeerProfiles which holds the Profile data
                    ForEach(peerManager.connectedPeers, id: \.self) { peer in
                        // Pass the peer and the profile (if available) to peerRow
                        // Also pass the peerManager to handle actions
                        peerRow(peer: peer, profile: peerManager.connectedPeerProfiles[peer], peerManager: peerManager)
                            // Add haptic feedback example on tap (if making row tappable)
                            // .onTapGesture {
                            //     // Trigger haptic feedback
                            //     let haptic = UIImpactFeedbackGenerator(style: .light)
                            //     haptic.impactOccurred()
                            //     // Handle tap action (e.g., navigate to details)
                            // }
                    }
                }

                // Add a browse button for finding more peers
                Button(action: { presentBrowserController() }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Find More Peers")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
                }
                .buttonStyle(.bordered)
                .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)

            } else if case .idle = connectionStatus {
                emptyStateView() // Not searching and no peers
            } else if isPeerSearchActive {
                searchingStateView() // Searching or connecting but no peers yet
            }
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        // Removed bottom padding to let parent control spacing
        // Removed background to let parent control background
        // .background(Color(.secondarySystemGroupedBackground))
    }

    // Connection status indicator
    private func connectionStatusIndicator(status: ConnectionStatus) -> some View {
        HStack(spacing: 5) { // Added spacing
            Group { // Group for applying frame consistently
                switch status {
                case .idle:
                    Circle().fill(Color.gray)
                case .searching:
                    // Use pulsing animation for searching
                    Circle()
                        .fill(Color.blue)
                        .opacity(0.8)
                        .scaleEffect(pulsate ? 1.2 : 0.8) // Add pulsation
                        .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsate)
                case .connecting:
                    Circle().fill(Color.orange) // Changed color for connecting
                case .connected:
                    Circle().fill(Color.green)
                case .failed:
                    Circle().fill(Color.red)
                }
            }
            .frame(width: 10, height: 10) // Slightly larger indicator

            Text(statusText(for: status))
                .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                .foregroundColor(statusColor(for: status))
        }
        .padding(.vertical, InnerCircleConstants.halfMargin / 2) // Add small vertical padding
        .onAppear { pulsate = true } // Start pulsation on appear
        .onDisappear { pulsate = false } // Stop pulsation on disappear
    }

    @State private var pulsate: Bool = false // State for pulsation animation

    private func statusText(for status: ConnectionStatus) -> String {
        switch status {
        case .idle: "Inactive"
        case .searching: "Searching"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .idle: .gray
        case .searching: .blue
        case .connecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }

    // Empty state view when no search is active
    private func emptyStateView() -> some View {
        VStack(spacing: systemMargin / 2) { // Use systemMargin multiple (8pt)
            Spacer().frame(height: systemMargin * 1.25) // Use systemMargin multiple (20pt)
            Image(systemName: "person.2.slash").font(.largeTitle).foregroundColor(.secondary.opacity(0.5))
            Text("Not Searching").font(.callout).foregroundColor(.secondary)
            // Updated text to guide user to the main toggle button
            Text("Tap 'Search for Nearby Devices' above to find peers.")
                .font(.caption) // Slightly larger caption
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, systemMargin) // Use systemMargin
            // Removed the redundant "Start Searching" button
            Spacer().frame(height: systemMargin * 1.25) // Use systemMargin multiple (20pt)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    // Searching state view when actively looking for peers
    private func searchingStateView() -> some View {
        VStack(spacing: systemMargin / 2) { // Use systemMargin multiple (8pt)
            Spacer().frame(height: systemMargin * 0.625) // Use systemMargin multiple (10pt)
            SignalPulseView().frame(width: 50, height: 50)
            Text("Scanning for Devices...").font(.callout).foregroundColor(.secondary)
            Text("Ensure other devices are also searching.").font(.caption2).foregroundColor(.secondary.opacity(0.8))
            // Removed "Browse Manually" button
            Spacer().frame(height: systemMargin * 0.625) // Use systemMargin multiple (10pt)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    // Present the browser controller manually
    private func presentBrowserController() {
        if let browserVC = peerManager.getPeerBrowser(),
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootController = windowScene.windows.first?.rootViewController
        {
            // Dismiss existing presentation if any before presenting new one
            rootController.presentedViewController?.dismiss(animated: false)
            rootController.present(browserVC, animated: true)
        } else {
            print("Could not get browser view controller or root view controller.")
        }
    }

    // Individual peer row - Updated to accept Profile and PeerManager
    // --- MODIFIED peerRow ---
    private func peerRow(peer: MCPeerID, profile: Profile?, peerManager: PeerDiscoveryManager) -> some View {
        // Get key exchange state for this specific peer
        let keyState = peerManager.peerKeyExchangeStates[peer]?.state ?? .idle
        let (_, statusIcon, statusColor) = displayInfo(for: keyState) // Use helper
        let isKeyExchangeButtonDisabled = switch keyState {
        case .idle, .failed: false // Enable for idle or failed (retry)
        default: true // Disable during active exchange or completion
        }
        let isProfileLoaded = profile != nil

        return HStack {
            // Profile View or Fallback
            if let profile {
                PeerProfileView(profile: profile, connectionTime: peerManager.peerConnectionTimes[peer])
            } else {
                // Fallback view when profile is not yet available
                HStack {
                    Image(systemName: "person.circle.fill").foregroundColor(.gray).font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.displayName).font(.subheadline).fontWeight(.medium).foregroundColor(.secondary)
                        Text("Connecting...").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    ProgressView().scaleEffect(0.5)
                }
            }

            Spacer() // Pushes buttons to the right

            // Action Buttons (only if profile is loaded)
            if isProfileLoaded {
                HStack(spacing: 5) { // Group buttons together
                    // Key Exchange Status and Button
                    HStack(spacing: 5) {
                        // Status Icon (optional)
                        if let iconName = statusIcon {
                            Image(systemName: iconName)
                                .font(.caption)
                                .foregroundColor(statusColor)
                        }

                        // Key Exchange Button
                        Button {
                            Task {
                                do {
                                    print("UI (peerRow): Initiating key regeneration with peer \(peer.displayName)")
                                    try await peerManager.initiateKeyRegeneration(with: peer)
                                    print("UI (peerRow): Key regeneration initiated successfully for \(peer.displayName)")
                                } catch {
                                    print("❌ UI (peerRow): Failed to initiate key regeneration for \(peer.displayName): \(error)")
                                    // Optionally show an error to the user
                                    sharedState.setState("Key exchange failed: \(error.localizedDescription)", forKey: "errorMessage")
                                }
                            }
                        } label: {
                            Group {
                                switch keyState {
                                case .idle:
                                    Image(systemName: "key.radiowaves.forward")
                                case .failed:
                                    Image(systemName: "arrow.clockwise") // Retry icon
                                case .completed:
                                    Image(systemName: "checkmark.shield")
                                default: // In progress states
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12) // Consistent size
                                }
                            }
                            .font(.caption) // Smaller icon/progress
                            .foregroundColor(statusColor) // Use status color for button content
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small) // Smaller button
                        .tint(statusColor) // Tint the border/background
                        .disabled(isKeyExchangeButtonDisabled)
                    }

                    // Share Profile Button (IMPLEMENTED)
                    Button {
                        // Call the implemented sharePeerProfile function
                        sharePeerProfile(peer: peer)
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue) // Consistent tint for share actions
                    .disabled(!isProfileLoaded) // Disable if profile not loaded
                    .help("Share Profile")

                    // Share KeyStore Button (IMPLEMENTED)
                    Button {
                        sharePeerKeyStore(peer: peer) // Call the implemented function
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.blue) // Consistent tint for share actions
                    .disabled(!isProfileLoaded) // Disable if profile not loaded
                    .help("Share KeyStore")
                }
            }
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal, systemMargin / 4) // Use systemMargin multiple (4pt) for spacing between rows
    }

    // --- REFACTORED peerRow towards PeerCardView ---
    private func peerRow(peer: MCPeerID, profile: Profile?, peerManager: PeerDiscoveryManager) -> some View {
        // Determine trust status (Placeholder - needs real logic)
        let trustStatus: TrustStatus = profile != nil ? .verified : .pending // Example logic
        // KeyStore Percentage - Placeholder: This needs data about the *peer's* keystore or local status in context
        let keyStorePercentage: Double = 0.85 // Placeholder value

        return HStack(spacing: InnerCircleConstants.systemMargin) { // Use constant
            // Avatar with trust indicator
            ZStack(alignment: .bottomTrailing) {
                // Use PeerProfileView's avatar logic or similar
                PeerProfileView.avatarView(profile: profile, peerId: peer) // Pass peerId for fallback color
                    .frame(width: 50, height: 50)

                // Trust indicator badge
                Circle()
                    .fill(trustStatus.color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Image(systemName: trustStatus.icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white) // Ensure contrast
                    )
                    .accessibilityLabel(Text("Trust status: \(trustStatus.description)"))
            }

            // Peer Info
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name ?? peer.displayName)
                    .font(InnerCircleConstants.primaryTextFont) // Use constant
                    .fontWeight(.semibold)
                    .foregroundColor(InnerCircleConstants.primaryTextColor) // Use constant

                Text(trustStatus.description)
                    .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant

                // Connection Time (if available and connected)
                if let time = peerManager.peerConnectionTimes[peer] {
                     Text("Connected \(connectionTimeString(time))")
                         .font(InnerCircleConstants.captionFont) // Use constant
                         .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                 } else if profile == nil {
                     Text("Connecting...") // Show connecting if profile not loaded
                         .font(InnerCircleConstants.captionFont)
                         .foregroundColor(InnerCircleConstants.secondaryTextColor)
                 }

                // Key status indicator (Placeholder - Needs real data)
                // if trustStatus == .trusted {
                //     KeyStoreIndicator(percentage: keyStorePercentage) // Needs data source
                // }
            }

            Spacer()

            // Action Buttons (Example - refine based on actual state logic)
            HStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
                // Example: Key Renewal Button (Placeholder Logic)
                if trustStatus == .trusted { // Only show for trusted peers
                    Button {
                        // TODO: Implement Key Renewal Initiation
                        print("Initiate Key Renewal with \(peer.displayName)")
                        // Example: Show peer selection sheet or confirmation
                    } label: {
                        Image(systemName: "key.fill") // Icon for renewal
                            .font(.system(size: 18, weight: .semibold)) // Use guide size
                            .foregroundColor(keyStorePercentage < 0.1 ? InnerCircleConstants.trustYellow : InnerCircleConstants.secondaryTextColor) // Highlight if low
                            .frame(minWidth: InnerCircleConstants.minimumTouchTarget, minHeight: InnerCircleConstants.minimumTouchTarget) // Ensure touch target
                    }
                    .accessibilityLabel(Text("Renew keys with \(profile?.name ?? peer.displayName)"))
                    .disabled(keyStorePercentage >= 0.1) // Example disable logic
                }

                // Example: Connect/View Details Button
                Button {
                    // TODO: Implement Connect or View Details action
                    if profile == nil {
                        print("Attempt connection to \(peer.displayName)")
                        // peerManager.invitePeer(peer) // Example action
                    } else {
                        print("View details for \(profile!.name)")
                        // Navigate to detail view or show modal
                    }
                } label: {
                    Image(systemName: profile == nil ? "link.badge.plus" : "info.circle") // Different icons based on state
                        .font(.system(size: 18, weight: .semibold)) // Use guide size
                        .foregroundColor(InnerCircleConstants.primaryActionColor) // Use constant
                        .frame(minWidth: InnerCircleConstants.minimumTouchTarget, minHeight: InnerCircleConstants.minimumTouchTarget) // Ensure touch target
                }
                .accessibilityLabel(Text(profile == nil ? "Connect with \(peer.displayName)" : "View details for \(profile!.name)"))
            }
        }
        .padding(InnerCircleConstants.systemMargin) // Use constant
        .background(InnerCircleConstants.cardBackgroundColor) // Use constant
        .cornerRadius(InnerCircleConstants.cornerRadius) // Use constant
        .contentShape(Rectangle()) // Make entire card tappable if needed for navigation
        .padding(.horizontal, InnerCircleConstants.halfMargin) // Spacing between cards
    }

    // --- END REFACTORED peerRow ---


    // --- START: Implemented/Modified Methods ---

    /// Action for sharing a peer's profile via P2P message.
    private func sharePeerProfile(peer: MCPeerID) {
        print("Attempting to share profile for peer: \(peer.displayName)")

        // 1. Get the Profile object associated with the peer ID
        guard let profileToShare = peerManager.connectedPeerProfiles[peer] else {
            print("❌ Error: Could not find profile for peer \(peer.displayName) to share.")
            sharedState.setState("Error: Could not find profile for \(peer.displayName).", forKey: "errorMessage")
            return
        }

        // 2. Serialize the Profile data (using Profile.toData which excludes sensitive keys)
        let profileData: Data
        do {
            profileData = try profileToShare.toData()
            print("   Serialized profile \(profileToShare.name) (\(profileData.count) bytes)")
        } catch {
            print("❌ Error: Failed to serialize profile \(profileToShare.name): \(error)")
            sharedState.setState("Error: Failed to prepare profile data for sharing.", forKey: "errorMessage")
            return
        }

        // 3. Create the P2P message payload
        let payload = ProfileSharePayload(profileData: profileData)

        // 4. Send the P2P message using PeerDiscoveryManager
        Task {
            do {
                try await peerManager.sendP2PMessage(type: .profileShare, payload: payload, toPeers: [peer])
                print("✅ Successfully sent profile share message for \(profileToShare.name) to \(peer.displayName)")
                // Provide user feedback
                sharedState.setState("Profile for \(profileToShare.name) sent to \(peer.displayName).", forKey: "statusMessage")
            } catch {
                print("❌ Error: Failed to send profile share message to \(peer.displayName): \(error)")
                sharedState.setState("Error: Failed to send profile to \(peer.displayName).", forKey: "errorMessage")
            }
        }
    }

    /// Action for sharing the local user's public KeyStore with a peer.
    private func sharePeerKeyStore(peer: MCPeerID) {
        print("KeyStoreShare: Attempting to share local public KeyStore with peer: \(peer.displayName)")

        // Get the recipient's profile name for feedback messages
        let recipientName = peerManager.connectedPeerProfiles[peer]?.name ?? peer.displayName

        Task {
            do {
                // 1. Get the local user's profile (needed for sender ID)
                guard let myProfile = ViewModelFactory.shared.getCurrentProfile() else {
                    throw P2PGroupViewModel.P2PError.profileNotAvailable
                }

                // 2. Get or Create the local KeyStore and extract its public data
                // This helper handles creation, key generation, saving private data, and returning public data.
                let publicKeyStoreData = try await peerManager.getOrCreateLocalPublicKeystoreData()
                print("   Obtained public KeyStore data (\(publicKeyStoreData.count) bytes) for local user \(myProfile.name).")

                // 3. Create the P2P message payload
                let payload = KeyStoreSharePayload(
                    senderProfileID: myProfile.publicID.base58EncodedString,
                    keyStorePublicData: publicKeyStoreData,
                    timestamp: Date()
                )
                print("   Created KeyStoreSharePayload.")

                // 4. Send the P2P message using PeerDiscoveryManager
                try await peerManager.sendP2PMessage(type: .keyStoreShare, payload: payload, toPeers: [peer])
                print("✅ Successfully sent public KeyStore share message to \(peer.displayName)")

                // 5. Provide user feedback
                sharedState.setState("Public KeyStore sent to \(recipientName).", forKey: "statusMessage")

            } catch let error as P2PGroupViewModel.P2PError {
                print("❌ KeyStoreShare: P2PError sharing KeyStore with \(peer.displayName): \(error)")
                sharedState.setState("Error sharing KeyStore with \(recipientName): \(error.localizedDescription)", forKey: "errorMessage")
            } catch {
                print("❌ KeyStoreShare: Unexpected error sharing KeyStore with \(peer.displayName): \(error)")
                sharedState.setState("Error sharing KeyStore with \(recipientName).", forKey: "errorMessage")
            }
        }
    }


    // --- END: Implemented/Modified Methods ---

    // Helper function to get display info (copied from InnerCircleMemberRow for use in peerRow)
    private func displayInfo(for state: KeyExchangeState) -> (text: String, icon: String?, color: Color) {
        switch state {
        case .idle:
            return ("Ready to Exchange", "key.radiowaves.forward", .blue)
        case .requestSent:
            return ("Request Sent", "paperplane", .orange)
        case .requestReceived:
            return ("Request Received", "envelope.badge", .orange)
        case .offerSent:
            return ("Offer Sent", "paperplane.fill", .orange)
        case .offerReceived:
            return ("Offer Received", "envelope.open.badge.clock", .orange)
        case .ackSent:
            return ("Ack Sent", "checkmark.message", .orange)
        case .ackReceived:
            return ("Ack Received", "checkmark.message.fill", .orange)
        case .commitSent:
            return ("Commit Sent", "lock.shield", .orange) // Using lock.shield temporarily
        case .completed:
            return ("Keys Exchanged", "checkmark.shield.fill", .green)
        case let .failed(reason):
            let shortReason = reason.prefix(30) + (reason.count > 30 ? "..." : "")
            return ("Failed: \(shortReason)", "exclamationmark.triangle.fill", .red)
        }
    }

    // Format the connection time
    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 { return GroupView.justNowString } // Use constant
        if timeInterval < 3600 { let minutes = Int(timeInterval / 60); return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        if timeInterval < 86400 { let hours = Int(timeInterval / 3600); return "\(hours) hour\(hours == 1 ? "" : "s") ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // Animated signal pulse for searching animation
    struct SignalPulseView: View {
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0.0
        @State private var pulsate: Bool = false

        var body: some View {
            ZStack {
                ZStack {
                    ForEach(0 ..< 3) { i in
                        Circle().stroke(Color.blue.opacity(0.7 - Double(i) * 0.2), lineWidth: 1).scaleEffect(scale - CGFloat(i) * 0.1)
                    }
                }.scaleEffect(pulsate ? 1.2 : 0.8)
                Circle().trim(from: 0.2, to: 0.8).stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3])).rotationEffect(.degrees(rotation)).scaleEffect(0.7)
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                }
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsate = true }
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) { rotation = 360 }
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) { scale = 1.1 }
            }
        }
    }

    // Chat overlay view
    private var chatOverlayView: some View {
        Group {
            if sharedState.showChatOverlay,
               let streamPublicID = sharedState.selectedStreamPublicID
            {
                ChatOverlay(streamPublicID: streamPublicID)
            }
        }
    }
}

// MARK: - InnerCircle Member Views

// Main view for displaying all InnerCircle members
struct InnerCircleView: View {
    let stream: Stream
    @ObservedObject var peerManager: PeerDiscoveryManager // Use @ObservedObject
    @EnvironmentObject var sharedState: SharedState
    @State private var showOfflineMembers: Bool = true
    @State private var searchText: String = ""
    @State private var innerCircleProfiles: [Profile] = [] // All profiles belonging to this InnerCircle
    @State private var showStatusMessage = false
    @State private var statusMessage = ""
    @State private var refreshObserver: NSObjectProtocol? // Observer token
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            searchAndFilterBar

            // Member count header
            memberCountHeader

            Divider()

            // Members list
            membersScrollView
        }
        .onAppear {
            setupView() // Call setup function
            setupNotificationObservers() // Setup observers
        }
        .onDisappear {
            removeNotificationObservers() // Remove observers
        }
        .overlay(statusMessageOverlay)
        // Refresh UI when key exchange states change
        .onChange(of: peerManager.peerKeyExchangeStates) { _, _ in
            // This ensures the UI updates when a state changes for any peer
            print("InnerCircleView: Detected change in peerKeyExchangeStates")
        }
    }

    // MARK: - Setup and Teardown

    // Initial setup when the view appears
    private func setupView() {
        Task {
            await loadInnerCircleProfiles()
        }
        checkForStatusMessage()
    }

    // Setup notification observers
    private func setupNotificationObservers() {
        // Listen for notifications to refresh the member list
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .refreshInnerCircleMembers,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await loadInnerCircleProfiles()
            }
        }
    }

    // Remove notification observers
    private func removeNotificationObservers() {
        if let observer = refreshObserver {
            NotificationCenter.default.removeObserver(observer)
            refreshObserver = nil
        }
    }

    // Check for and display any pending status messages
    private func checkForStatusMessage() {
        if let message = sharedState.getState(forKey: "statusMessage") as? String, !message.isEmpty {
            statusMessage = message
            showStatusMessage = true
            // Clear the message after retrieving it
            sharedState.setState("", forKey: "statusMessage")
        }
    }

    // MARK: - Computed Properties (Refactored for Simplicity)

    // All currently connected online profiles from peer manager
    private var onlineProfiles: [Profile] {
        Array(peerManager.connectedPeerProfiles.values)
    }

    // All offline profiles (in InnerCircle but not currently connected)
    private var offlineProfiles: [Profile] {
        // Get IDs of online profiles for efficient lookup
        let onlineProfileIDs = Set(onlineProfiles.map(\.id))
        // Filter the full list of InnerCircle members
        return innerCircleProfiles.filter { profile in
            !onlineProfileIDs.contains(profile.id)
        }
    }

    // Filtered online profiles based on search text
    private var filteredOnlineProfiles: [Profile] {
        let profiles = onlineProfiles // Start with online profiles
        if searchText.isEmpty {
            return profiles // No filter needed
        } else {
            // Apply search filter
            return profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // Filtered offline profiles based on search text
    private var filteredOfflineProfiles: [Profile] {
        let profiles = offlineProfiles // Start with offline profiles
        if searchText.isEmpty {
            return profiles // No filter needed
        } else {
            // Apply search filter
            return profiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // MARK: - Helper Functions

    // Check if a profile is currently online via P2P
    private func isProfileOnline(_ profile: Profile) -> Bool {
        // Check if any profile in the connectedPeerProfiles dictionary has the same ID
        peerManager.connectedPeerProfiles.values.contains { $0.id == profile.id }
    }

    // Load all InnerCircle profiles from the stream relationship
    private func loadInnerCircleProfiles() async {
        // Directly access the stream's innerCircleProfiles relationship
        // This assumes the 'stream' object passed to InnerCircleView is up-to-date
        // and its relationships are loaded by SwiftData.
        // No need for manual fetching or filtering.
        innerCircleProfiles = stream.innerCircleProfiles
        print("Loaded \(innerCircleProfiles.count) InnerCircle profiles directly from stream relationship.")

        // Note: If 'stream' might be stale or relationships aren't automatically loaded,
        // you might need to re-fetch the stream first:
        // if let freshStream = try? await PersistenceController.shared.fetchStream(withID: stream.id) {
        //     self.innerCircleProfiles = freshStream.innerCircleProfiles
        // } else {
        //     print("Error refreshing stream for InnerCircle profiles")
        //     self.innerCircleProfiles = []
        // }
    }

    // Get connection time for an online profile
    private func getConnectionTime(for profile: Profile) -> Date? {
        // Find the MCPeerID for this profile
        for (peer, peerProfile) in peerManager.connectedPeerProfiles {
            if peerProfile.id == profile.id {
                return peerManager.peerConnectionTimes[peer]
            }
        }
        return nil
    }

    // MARK: - Subviews

    private var searchAndFilterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search members", text: $searchText)
                .font(.subheadline)

            Spacer()

            Toggle(isOn: $showOfflineMembers) {
                Text("Show Offline")
                    .font(.caption)
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.8)
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        .background(Color(.secondarySystemBackground))
    }

    private var memberCountHeader: some View {
        HStack {
            Text("Members")
                .font(.subheadline)
                .fontWeight(.medium)

            // Use the computed properties for counts
            Text("(\(onlineProfiles.count) online, \(offlineProfiles.count) offline)")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                Task {
                    await loadInnerCircleProfiles()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
    }

    private var membersScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Online members section
                let onlineToShow = filteredOnlineProfiles
                if !onlineToShow.isEmpty {
                    sectionHeader(title: "Online", count: onlineToShow.count)

                    ForEach(onlineToShow) { profile in
                        InnerCircleMemberRow(
                            profile: profile,
                            isOnline: true,
                            connectionTime: getConnectionTime(for: profile),
                            stream: stream,
                            peerManager: peerManager // Pass peerManager
                        )
                        .padding(.horizontal, systemMargin) // Use systemMargin
                        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                        .environmentObject(sharedState)
                    }
                }

                // Offline members section
                let offlineToShow = filteredOfflineProfiles
                if showOfflineMembers, !offlineToShow.isEmpty {
                    sectionHeader(title: "Offline", count: offlineToShow.count)

                    ForEach(offlineToShow) { profile in
                        InnerCircleMemberRow(
                            profile: profile,
                            isOnline: false,
                            // lastSeen removed
                            stream: stream,
                            peerManager: peerManager // Pass peerManager
                        )
                        .padding(.horizontal, systemMargin) // Use systemMargin
                        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
                        .environmentObject(sharedState)
                    }
                }

                // Empty state
                if onlineToShow.isEmpty, offlineToShow.isEmpty || !showOfflineMembers {
                    emptyStateView
                }
            }
            .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        }
    }

    // Section header view
    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, systemMargin) // Use systemMargin
        .padding(.vertical, systemMargin / 4) // Use systemMargin multiple (4pt)
        .background(Color(.systemGroupedBackground))
    }

    // Empty state view
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Members Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(searchText.isEmpty ?
                "There are no members to display." :
                "No members match your search.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, systemMargin) // Use systemMargin
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, systemMargin * 2.5) // Use systemMargin multiple (40pt)
    }

    // Status message overlay
    @ViewBuilder
    private var statusMessageOverlay: some View {
        if showStatusMessage {
            VStack {
                Text(statusMessage)
                    .foregroundColor(.white)
                    .padding(systemMargin) // Use systemMargin
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(10)
                    .padding(systemMargin) // Use systemMargin
                    .onAppear {
                        // Auto-dismiss after a few seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            showStatusMessage = false
                        }
                    }
                Spacer()
            }
        }
    }
}

// Row view for individual InnerCircle members
struct InnerCircleMemberRow: View {
    let profile: Profile
    let isOnline: Bool
    var connectionTime: Date? = nil
    // Removed lastSeen property as it's no longer in Profile
    // var lastSeen: Date? = nil
    @EnvironmentObject var sharedState: SharedState
    var stream: Stream
    @ObservedObject var peerManager: PeerDiscoveryManager // Use @ObservedObject
    @State private var showRemoveConfirmation = false
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16

    // Computed property to get the current key exchange state for this profile (if online)
    private var keyExchangeState: KeyExchangeState? {
        guard isOnline, let peer = peerManager.findPeer(byProfileID: profile.publicID) else {
            return nil
        }
        return peerManager.peerKeyExchangeStates[peer]?.state
    }

    // Computed property to determine if the key exchange button should be disabled
    private var isKeyExchangeButtonDisabled: Bool {
        guard isOnline, let state = keyExchangeState else {
            return true // Disable if offline or no state found
        }
        // Disable unless idle or failed (allow retry from failed)
        switch state {
        case .idle, .failed:
            return false
        default:
            return true
        }
    }

    var body: some View {
        HStack {
            // Avatar
            avatarView
                .frame(width: 40, height: 40)

            // Profile info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                if isOnline {
                    if let time = connectionTime {
                        Text("Connected \(timeAgoString(time))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Online")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    // Display Key Exchange Status if online
                    keyExchangeStatusView() // <-- INTEGRATED STATUS VIEW
                        .font(.caption2) // Smaller font for status
                        .padding(.top, 1)

                } else {
                    // Removed lastSeen display
                    Text("Offline") // Simple offline indicator
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator (Online/Offline dot)
            statusIndicator

            // Message button - Only enabled for online peers
            Button(action: {
                // Open chat with this member
                if isOnline {
                    openDirectChat()
                }
            }) {
                Image(systemName: "message")
                    .font(.subheadline)
                    .foregroundColor(isOnline ? .blue : .gray)
                    .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
                    .background(Circle().fill(isOnline ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!isOnline)

            // Key Exchange Button - Only show for online peers
            if isOnline {
                keyExchangeButton() // <-- INTEGRATED KEY EXCHANGE BUTTON
            }

            // Remove member button
            Button(action: {
                showRemoveConfirmation = true
            }) {
                Image(systemName: "person.fill.xmark")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
                    .background(Circle().fill(Color.red.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .alert("Remove Member", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    removeFromInnerCircle()
                }
            } message: {
                Text("Are you sure you want to remove \(profile.name) from your InnerCircle? They will no longer be able to communicate directly with you.")
            }
        }
        .padding(.vertical, systemMargin / 2) // Use systemMargin multiple (8pt)
        .padding(.horizontal, systemMargin * 0.75) // Use systemMargin multiple (12pt)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // Open direct chat with this member
    private func openDirectChat() {
        // Set the InnerCircle stream as selected
        sharedState.selectedStreamPublicID = stream.publicID

        // Show chat overlay
        sharedState.showChatOverlay = true

        // Store the selected profile for direct messaging
        sharedState.setState(profile, forKey: "selectedDirectMessageProfile")
    }

    // Avatar view
    private var avatarView: some View {
        let initials = profile.name.prefix(2).uppercased()
        let color = avatarColor(for: profile.publicID)

        return ZStack {
            Circle()
                .fill(color)
            Text(initials)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
    }

    // Status indicator
    private var statusIndicator: some View {
        Group {
            if isOnline {
                // Online indicator
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 16, height: 16)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            } else {
                // Offline indicator
                Circle()
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
            }
        }
    }

    // Generate avatar color from profile ID
    private func avatarColor(for data: Data) -> Color {
        var hash = 0
        for byte in data {
            hash = hash &* 31 &+ Int(byte)
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }

    // Format time ago string
    private func timeAgoString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 { return GroupView.justNowString } // Use constant
        if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        }
        if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        }
        if timeInterval < 604_800 { // 7 days
            let days = Int(timeInterval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // Remove member from InnerCircle
    private func removeFromInnerCircle() {
        Task { @MainActor in // Ensure execution on main actor
            do {
                // 1. Find the MCPeerID associated with the profile being removed
                var peerToDisconnect: MCPeerID?
                for (peer, connectedProfile) in peerManager.connectedPeerProfiles {
                    if connectedProfile.id == profile.id {
                        peerToDisconnect = peer
                        break
                    }
                }

                // 2. Remove KeyStore data for this profile
                try await PersistenceController.shared.deleteKeyStoreDataFor(profile: profile)

                // 3. Remove the profile from this stream's members list
                stream.removeFromInnerCircle(profile)
                try await PersistenceController.shared.saveChanges() // Save changes after modifying stream

                // 4. Disconnect the peer if they are currently connected
                if let peer = peerToDisconnect {
                    print("Disconnecting peer \(peer.displayName) associated with removed profile \(profile.name)")
                    peerManager.disconnectPeer(peer) // Use the existing method
                } else {
                    print("Peer for profile \(profile.name) was not connected, no disconnection needed.")
                }

                // 5. Update the UI to reflect the member is removed
                // The list should refresh when InnerCircleView's loadInnerCircleProfiles is called

                // 6. Show an optional toast/banner notifying that the member was removed
                sharedState.setState("Successfully removed \(profile.name) from your InnerCircle", forKey: "statusMessage")

                // 7. Trigger a refresh of the members list
                NotificationCenter.default.post(name: .refreshInnerCircleMembers, object: nil)

            } catch {
                print("Error removing member from InnerCircle: \(error)")
                // Show error message
                sharedState.setState("Failed to remove \(profile.name): \(error.localizedDescription)", forKey: "errorMessage")
            }
        }
    }

    // MARK: - Key Exchange UI Helpers

    // View to display the current key exchange status text and icon
    @ViewBuilder
    private func keyExchangeStatusView() -> some View {
        if let state = keyExchangeState {
            let (text, icon, color) = displayInfo(for: state)
            HStack(spacing: 3) {
                if let iconName = icon {
                    Image(systemName: iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 10, height: 10) // Smaller icon
                        .foregroundColor(color)
                }
                Text(text)
                    .foregroundColor(color)
            }
            // Add animation for state changes
            .animation(.easeInOut(duration: 0.3), value: state)
        } else {
            // Default view if no state (or offline) - Indicate keys are ready/default state
            HStack(spacing: 3) {
                Image(systemName: "lock.shield") // Use a neutral icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 10, height: 10)
                    .foregroundColor(.gray) // Neutral color
                Text("Secure") // Neutral text
                    .foregroundColor(.gray)
            }
        }
    }

    // Button for initiating or retrying key exchange
    @ViewBuilder
    private func keyExchangeButton() -> some View {
        let keyState: KeyExchangeState = keyExchangeState ?? .idle // Default to idle if nil
        let isFailed = if case KeyExchangeState.failed = keyState { true } else { false }
        let (text, _, color) = displayInfo(for: keyState) // Get text and color
        let isDisabled = isKeyExchangeButtonDisabled

        Button {
            // Find the peer and initiate regeneration
            if let peer = peerManager.findPeer(byProfileID: profile.publicID) {
                Task {
                    do {
                        print("UI: Initiating key regeneration with peer \(peer.displayName) for profile \(profile.name)")
                        try await peerManager.initiateKeyRegeneration(with: peer)
                        print("UI: Key regeneration initiated successfully for \(profile.name)")
                    } catch {
                        print("❌ UI: Failed to initiate key regeneration for \(profile.name): \(error)")
                        // Optionally show an error to the user (e.g., using an alert or status message)
                        sharedState.setState("Key exchange failed: \(error.localizedDescription)", forKey: "errorMessage") // Example error handling
                    }
                }
            } else {
                print("❌ UI: Could not find MCPeerID for profile \(profile.name) to initiate key exchange.")
            }
        } label: {
            Group {
                switch keyState {
                case .idle:
                    Image(systemName: "key.radiowaves.forward")
                        .foregroundColor(.blue)
                case KeyExchangeState.failed:
                    Image(systemName: "arrow.clockwise") // Retry icon
                        .foregroundColor(.orange)
                case .completed:
                    Image(systemName: "checkmark.shield")
                        .foregroundColor(.green)
                case .requestSent, .requestReceived, .offerSent, .offerReceived, .ackSent, .ackReceived, .commitSent:
                    ProgressView() // Show spinner while in progress
                        .scaleEffect(0.6) // Smaller spinner
                        .frame(width: 16, height: 16) // Ensure consistent size
                        .tint(.orange) // Tint spinner orange during progress
                }
            }
            .font(.subheadline) // Match message icon size
            .padding(systemMargin / 2) // Use systemMargin multiple (8pt)
            // Use clear background when disabled or completed, otherwise use tinted background
            .background(Circle().fill((isDisabled && !isFailed) ? Color.clear : color.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        // Add tooltip/help text
        .help(isDisabled ? text : (isFailed ? "Retry Key Exchange" : "Initiate Key Exchange"))
        // Add animation for state changes
        .animation(.easeInOut(duration: 0.3), value: keyState)
    }

    // Helper to get display info based on KeyExchangeState
    private func displayInfo(for state: KeyExchangeState) -> (text: String, icon: String?, color: Color) {
        switch state {
        case .idle:
            return ("Ready to Exchange", "key.radiowaves.forward", .blue)
        case .requestSent:
            return ("Request Sent", "paperplane", .orange)
        case .requestReceived:
            return ("Request Received", "envelope.badge", .orange)
        case .offerSent:
            return ("Offer Sent", "paperplane.fill", .orange)
        case .offerReceived:
            return ("Offer Received", "envelope.open.badge.clock", .orange)
        case .ackSent:
            return ("Ack Sent", "checkmark.message", .orange)
        case .ackReceived:
            return ("Ack Received", "checkmark.message.fill", .orange)
        case .commitSent:
            // Using a more indicative icon for the final step before completion
            return ("Committing Keys", "lock.shield.fill", .orange)
        case .completed:
            return ("Keys Exchanged", "checkmark.shield.fill", .green)
        case let .failed(reason):
            // Keep reason short for UI
            let shortReason = reason.prefix(30) + (reason.count > 30 ? "..." : "")
            // Provide a more user-friendly default if reason is empty
            let displayText = reason.isEmpty ? "Failed" : "Failed: \(shortReason)"
            return (displayText, "exclamationmark.triangle.fill", .red)
        }
    }
}

// MARK: - Peer Profile View

struct PeerProfileView: View {
    let profile: Profile
    let connectionTime: Date?
    
    var body: some View {
        HStack {
            // Generated Avatar
            avatarView
                .frame(width: 32, height: 32) // Consistent size
            
            // Profile Info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary) // Use primary color for name
                
                if let time = connectionTime {
                    Text("Connected \(connectionTimeString(time))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Connected") // Fallback if time isn't available
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Connection Status Indicator (Green dot)
            ZStack {
                Circle().fill(Color.green.opacity(0.2)).frame(width: 16, height: 16)
                Circle().fill(Color.green).frame(width: 8, height: 8)
            }
        }
    }
    
    // Static avatar view generator for use in PeerRow and potentially elsewhere
    static func avatarView(profile: Profile?, peerId: MCPeerID? = nil) -> some View {
        let name = profile?.name ?? peerId?.displayName ?? "?"
        let idData = profile?.publicID ?? Data(peerId?.displayName.utf8 ?? Data()) // Use name for color if no profile ID
        let initials = name.prefix(2).uppercased()
        let color = avatarColor(for: idData) // Use publicID or name hash for consistent color
        
        return ZStack {
            Circle()
                .fill(color)
            Text(initials)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
    }
    
    // Static color generator
    static func avatarColor(for data: Data) -> Color {
        // Simple hash-based color generation
        var hash = 0
        for byte in data {
            hash = hash &* 31 &+ Int(byte) // Basic hash combining
        }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
    
    // Format the connection time (copied from GroupView for encapsulation)
    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 { return GroupView.justNowString } // Use constant
        if timeInterval < 3600 { let minutes = Int(timeInterval / 60); return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        if timeInterval < 86400 { let hours = Int(timeInterval / 3600); return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
        // MARK: - Server Card (Now used for non-InnerCircle streams)
        
        struct GroupCardView: View {
            let stream: Stream
            let onSelect: () -> Void
            @State private var isShareSheetPresented = false
            // Standard system margin from HIG
            private let systemMargin: CGFloat = 16
            
            var body: some View {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // Group Icon
                        Button(action: onSelect) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: iconForStream(stream))
                                        .font(.title3)
                                        .foregroundStyle(.blue)
                                }
                                
                                // Group Info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stream.profile.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    // Add InnerCircle badge if applicable
                                    if stream.isInnerCircleStream {
                                        Text("InnerCircle")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.15))
                                            .foregroundColor(.blue)
                                            .cornerRadius(8)
                                    }
                                }
                                
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Share Button
                        Button(action: {
                            isShareSheetPresented = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.trailing, systemMargin / 4) // Use systemMargin multiple (4pt)
                    }
                    .padding(systemMargin) // Use systemMargin
                    .background(Color(.secondarySystemGroupedBackground))
                    // Apply corner radius based on whether it's an InnerCircle stream (members shown below)
                    .cornerRadius(10, corners: stream.isInnerCircleStream ? [.topLeft, .topRight] : .allCorners)
                }
                // Removed clipShape here, applied conditionally above and to the parent VStack in streamRow
                // .clipShape(RoundedRectangle(cornerRadius: 12))
                .sheet(isPresented: $isShareSheetPresented) {
                    // Use the static constant from GroupView to build the URL
                    let urlString = "\(GroupView.streamBaseURL)\(stream.publicID.base58EncodedString)"
                    if let url = URL(string: urlString) {
                        ShareSheet(
                            activityItems: [url],
                            isPresented: $isShareSheetPresented
                        )
                    }
                }
            }
            
            private func iconForStream(_ stream: Stream) -> String {
                // Use specific icon for InnerCircle
                if stream.isInnerCircleStream {
                    return "network" // Or "wifi", "shared.with.you" etc.
                }
                
                // Fallback to hash-based icon for regular streams
                let hashValue = stream.publicID.hashValue
                let iconIndex = abs(hashValue) % 32
                let iconNames = [
                    "person.fill", "figure.child", "figure.wave", "person.3.fill",
                    "star.fill", "heart.fill", "flag.fill", "book.fill",
                    "house.fill", "car.fill", "bicycle", "airplane",
                    "tram.fill", "bus.fill", "ferry.fill", "train.side.front.car",
                    "leaf.fill", "flame.fill", "drop.fill", "snowflake",
                    "cloud.fill", "sun.max.fill", "moon.fill", "sparkles",
                    "camera.fill", "phone.fill", "envelope.fill", "message.fill",
                    "bell.fill", "tag.fill", "cart.fill", "creditcard.fill",
                ]
                return iconNames[iconIndex]
            }
        }
        
        // Helper for applying corner radius to specific corners
        struct RoundedCorner: Shape {
            var radius: CGFloat = .infinity
            var corners: UIRectCorner = .allCorners
            
            func path(in rect: CGRect) -> Path {
                let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
                return Path(path.cgPath)
            }
        }
        
        extension View {
            func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
                clipShape(RoundedCorner(radius: radius, corners: corners))
            }
        }
        
        
        struct PolicyRow: View {
            let icon: String
            let title: String
            let value: String
            
            var body: some View {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    
                    Text(title)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(value)
                        .foregroundStyle(.primary)
                }
            }
        }
        
        struct ThoughtRow: View {
            let thought: Thought
            
            var body: some View {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(thought.nano.hexEncodedString()) // Consider showing something more user-friendly
                            .font(.headline)
                            .lineLimit(1) // Limit display if hex is too long
                        Spacer()
                        Text(thought.metadata.createdAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(thought.metadata.createdAt.formatted())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        
        // MARK: - KeyStore Status Indicator (Simplified for Header)
        
        struct KeyStoreStatusIndicator: View {
            @ObservedObject var peerManager: PeerDiscoveryManager
            // Constants from InnerCircleConstants could be used here too if needed
            
            private var keyStoreInfo: LocalKeyStoreInfo? { peerManager.localKeyStoreInfo }
            private var percentage: Double {
                guard let info = keyStoreInfo, info.capacity > 0 else { return 0 }
                return Double(info.validKeyCount) / Double(info.capacity)
            }
            private var isLowOnKeys: Bool { percentage < 0.10 } // Example threshold
            private var hasExpiredKeys: Bool { (keyStoreInfo?.expiredKeyCount ?? 0) > 0 }
            
            private var indicatorColor: Color {
                if isLowOnKeys { return InnerCircleConstants.trustRed }
                if hasExpiredKeys { return InnerCircleConstants.trustYellow }
                if percentage < 0.5 { return InnerCircleConstants.trustYellow }
                return InnerCircleConstants.trustGreen
            }
            
            private var iconName: String {
                if isLowOnKeys || hasExpiredKeys { return "exclamationmark.shield.fill" }
                return "lock.shield.fill"
            }
            
            var body: some View {
                HStack(spacing: 4) {
                    if peerManager.isRegeneratingKeys {
                        ProgressView().scaleEffect(0.6)
                    } else if keyStoreInfo != nil {
                        Image(systemName: iconName)
                            .font(.system(size: 12)) // Smaller icon for header
                            .foregroundColor(indicatorColor)
                        Text(String(format: "%.0f%%", percentage * 100))
                            .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                            .foregroundColor(indicatorColor)
                    } else {
                        // Loading state
                        ProgressView().scaleEffect(0.6)
                        Text("Loading...")
                            .font(InnerCircleConstants.captionFont) // Use constant
                            .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                    }
                }
                .animation(.easeInOut, value: peerManager.localKeyStoreInfo)
                .animation(.easeInOut, value: peerManager.isRegeneratingKeys)
                // Add accessibility later
            }
        }
        
        
        // MARK: - PeerDiscoveryManager Mock Extensions (for compilation)
        
        // These should be replaced by actual implementations in PeerDiscoveryManager
        
        // Add a placeholder property to PeerDiscoveryManager if it doesn't exist
        // This is just for compilation and assumes the real manager will publish this.
        extension PeerDiscoveryManager {
            // Placeholder - Replace with actual published property
            // @Published var localKeyStoreInfo: LocalKeyStoreInfo? = nil // Type already updated
            // @Published var isRegeneratingKeys: Bool = false // Already exists
            
            // Check if key exchange is actively in progress with a specific peer
            func isExchangingKeys(with peer: MCPeerID) -> Bool {
                guard let state = peerKeyExchangeStates[peer]?.state else {
                    return false // No state tracked for this peer
                }
                // Return true if state is anything other than idle, completed, or failed
                switch state {
                case .idle, .completed, .failed:
                    return false
                default:
                    return true
                }
            }
            
            // Check if key exchange is actively in progress with a specific profile
            func isExchangingKeys(with profile: Profile) -> Bool {
                // Find the MCPeerID associated with this profile among connected peers
                guard let peer = findPeer(byProfileID: profile.publicID) else {
                    // Profile not found among connected peers
                    return false
                }
                // Check the state for the found peer
                return isExchangingKeys(with: peer)
            }
        }
    }
}
