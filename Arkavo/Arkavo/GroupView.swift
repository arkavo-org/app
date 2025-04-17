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

// MARK: - Extensions

// Add notification name for refreshing InnerCircle members
// Kept here as GroupViewModel posts it. InnerCircleView observes it.
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

    // Scrollable stream list - Restructured based on UI Critique
    private func streamScrollView(geometry: GeometryProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: InnerCircleConstants.doubleMargin) { // Increased spacing between major sections

                // --- 2. InnerCircle Members Section ---
                innerCircleMembersSection()
                    .padding(.horizontal, InnerCircleConstants.systemMargin)

                // --- 3. Peer Discovery Tools Section ---
                peerDiscoverySection()
                    .padding(.horizontal, InnerCircleConstants.systemMargin)

                // --- 4. Other Streams Section ---
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

    // --- NEW: 2. InnerCircle Members Section ---
    private func innerCircleMembersSection() -> some View {
        // Find the InnerCircle stream
        guard let innerCircleStream = viewModel.streams.first(where: { $0.isInnerCircleStream }) else {
            // Return an empty view or placeholder if the stream doesn't exist
            return AnyView(EmptyView())
        }

        // Use the InnerCircleView (now defined in InnerCircleViews.swift)
        return AnyView(
            VStack(alignment: .leading, spacing: InnerCircleConstants.halfMargin) {
                Spacer()
                // Embed the view from the other file
                InnerCircleView(stream: innerCircleStream, peerManager: peerManager)
                    .environmentObject(sharedState)
                    .background(InnerCircleConstants.cardBackgroundColor)
                    .cornerRadius(InnerCircleConstants.cornerRadius)
            }
        )
    }

    // --- NEW: 3. Peer Discovery Tools Section ---
    private func peerDiscoverySection() -> some View {
        VStack(alignment: .leading, spacing: InnerCircleConstants.halfMargin) {
            HStack {
                Text("Discover & Connect")
                    .font(InnerCircleConstants.headerFont)
                    .foregroundColor(InnerCircleConstants.primaryTextColor)
                Spacer()
            }
            // Contains the Discover button and the list of discovered/connecting peers
            innerCirclePeerDiscoveryUI()
                .background(InnerCircleConstants.cardBackgroundColor)
                .cornerRadius(InnerCircleConstants.cornerRadius)
        }
    }

    // --- MODIFIED: InnerCircle Status Header View (Connection Only) ---
    private func innerCircleStatusHeader() -> some View {
        HStack {
            Label {
                Text("Connection Status")
                    .font(InnerCircleConstants.secondaryTextFont) // Use constant
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
            } icon: {
                connectionStatusIndicatorIcon(status: peerManager.connectionStatus)
            }
            Spacer()
            Text(statusText(for: peerManager.connectionStatus)) // Keep text label
                .font(InnerCircleConstants.statusIndicatorFont) // Use constant
                .foregroundColor(statusColor(for: peerManager.connectionStatus)) // Keep color coding
        }
    }

    // --- NEW: Helper for Status Indicator Icon ---
    private func connectionStatusIndicatorIcon(status: ConnectionStatus) -> some View {
        let color = statusColor(for: status)

        return Group {
            if status == .searching {
                Circle()
                    .fill(color)
                    .opacity(0.8)
                    .scaleEffect(pulsate ? 1.2 : 0.8) // Add pulsation
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsate)
            } else {
                Circle().fill(color)
            }
        }
        .frame(width: 10, height: 10) // Consistent size
    }

    // --- NEW: KeyStore Status Row ---
    private func keyStoreStatusRow() -> some View {
        HStack {
            Label {
                Text("Local KeyStore")
                    .font(InnerCircleConstants.secondaryTextFont)
                    .foregroundColor(InnerCircleConstants.secondaryTextColor)
            } icon: {
                Image(systemName: "key.fill") // Example icon
                    .foregroundColor(InnerCircleConstants.secondaryTextColor)
            }

            Spacer()

            // Re-integrate the simplified indicator
            KeyStoreStatusIndicator(peerManager: peerManager)

            // Placeholder Renew Button (Logic needs implementation)
            if let keyInfo = peerManager.localKeyStoreInfo, keyInfo.validKeyCount > 0 {
                let isLow = (Double(keyInfo.validKeyCount) / Double(keyInfo.capacity)) < 0.10
                Button("Renew Keys") {
                    // TODO: Implement Key Renewal Initiation Flow
                    print("Initiate Key Renewal Flow...")
                }
                .font(InnerCircleConstants.statusIndicatorFont)
                .foregroundColor(isLow ? InnerCircleConstants.trustYellow : InnerCircleConstants.primaryActionColor)
                .disabled(!isLow) // Example: Enable only when low
                .padding(.leading, InnerCircleConstants.halfMargin)
                .accessibilityLabel("Renew one-time keys")
            }
        }
    }

    // Individual stream row (now only uses GroupCardView)
    private func streamRow(stream: Stream) -> some View {
        if !stream.isInnerCircleStream {
            return AnyView(
                GroupCardView(
                    stream: stream,
                    onSelect: {
                        viewModel.selectedStream = stream
                        sharedState.selectedStreamPublicID = stream.publicID
                        sharedState.showChatOverlay = true
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            )
        } else {
            return AnyView(EmptyView())
        }
    }

    // Inner Circle peer discovery UI (P2P related) - Refactored
    private func innerCirclePeerDiscoveryUI() -> some View {
        VStack(spacing: InnerCircleConstants.systemMargin) { // Use constant for spacing within this section
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
            // Removed vertical padding here, handled by VStack spacing

            // Discovered peers list view (or empty state)
            discoveredPeersView // Renamed for clarity

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

    // Renamed and Refactored: Shows discovered/connecting peers
    private var discoveredPeersView: some View {
        VStack(spacing: InnerCircleConstants.halfMargin) { // Use constant
            let peerCount = peerManager.connectedPeers.count // Still relevant for count
            let connectionStatus = peerManager.connectionStatus // Still relevant for status

            // Removed old status bar - handled in innerCircleStatusHeader now

            // Show search status banner when active (Simplified)
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
            // Show search status banner when active (Simplified)
            if case .searching = connectionStatus {
                Text("Scanning for nearby devices...")
                    .font(InnerCircleConstants.captionFont) // Use constant
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
            }

            // Show error message if there's an error (Keep existing logic)
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

            // Divider only needed if peers are shown
            if peerCount > 0 {
                Divider().padding(.vertical, InnerCircleConstants.halfMargin) // Use constant
            }

            if peerCount > 0 {
                // Title for peers section (Adjust if showing "Discovered" vs "Connected")
                Text("Discovered Devices (\(peerCount))") // Updated title
                    .font(InnerCircleConstants.secondaryTextFont) // Use constant
                    .fontWeight(.medium)
                    .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, InnerCircleConstants.halfMargin / 2) // Use constant

                // Show list of discovered/connected peers using the refactored peerRow
                // Note: peerRow needs further updates for "Verify Trust" button based on actual state
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
                // Removed "Find More Peers" button - discovery is initiated by main button

            } else if isPeerSearchActive {
                // Show searching state only if no peers found yet
                searchingStateView()
            } else {
                // Show empty state if idle and no peers
                emptyStateView()
            }
        }
        // Removed horizontal padding - handled by parent section
        // Removed background - handled by parent section
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
            // Updated empty state based on critique
            Image(systemName: "person.2.slash")
                .font(.system(size: 36)) // Use guide size
                .foregroundColor(.gray) // Use guide color

            Text("No Peers Discovered") // Updated title
                .font(InnerCircleConstants.headerFont.weight(.medium)) // Use constant font, adjust weight
                .foregroundColor(InnerCircleConstants.primaryTextColor) // Use constant

            Text("Tap 'Discover Peers' to find nearby devices. Once found, you can verify trust and add them to your InnerCircle.") // Updated text
                .font(InnerCircleConstants.secondaryTextFont) // Use constant
                .foregroundColor(InnerCircleConstants.secondaryTextColor) // Use constant
                .multilineTextAlignment(.center)
                .padding(.horizontal, InnerCircleConstants.systemMargin) // Use constant
            // Removed the redundant "Start Searching" button
        }
        .padding(.vertical, InnerCircleConstants.doubleMargin) // Use constant for vertical padding
        .frame(maxWidth: .infinity)
        // Removed background/corner radius - let parent section handle card appearance
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

    private func peerRow(peer: MCPeerID, profile: Profile?, peerManager: PeerDiscoveryManager) -> some View {
        // Determine trust status (Placeholder - needs real logic)
        let trustStatus: TrustStatus = profile != nil ? .verified : .pending // Example logic
        // KeyStore Percentage - Placeholder: This needs data about the *peer's* keystore or local status in context
        let keyStorePercentage = 0.85 // Placeholder value

        return HStack(spacing: InnerCircleConstants.systemMargin) { // Use constant
            // Avatar with trust indicator
            ZStack(alignment: .bottomTrailing) {
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

                // Example: Verify Trust / View Details Button
                Button {
                    // TODO: Implement Verify Trust or View Details action
                    if trustStatus == .pending || trustStatus == .unknown {
                        print("Initiate Trust Verification with \(peer.displayName)")
                        // Show verification modal/flow
                    } else if trustStatus == .trusted || trustStatus == .verified {
                        print("View details for \(profile?.name ?? peer.displayName)")
                        // Navigate to detail view or show modal
                    } else {
                        // Handle other states (e.g., compromised)
                    }
                } label: {
                    // Icon changes based on trust status
                    let iconName = (trustStatus == .pending || trustStatus == .unknown) ? "lock.open.shield.fill" : "info.circle"
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold)) // Use guide size
                        .foregroundColor(InnerCircleConstants.primaryActionColor) // Use constant
                        .frame(minWidth: InnerCircleConstants.minimumTouchTarget, minHeight: InnerCircleConstants.minimumTouchTarget) // Ensure touch target
                }
                .accessibilityLabel(Text((trustStatus == .pending || trustStatus == .unknown) ? "Verify trust with \(profile?.name ?? peer.displayName)" : "View details for \(profile?.name ?? peer.displayName)"))
            }
        }
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
        // Ensure the iconIndex is within bounds
        return iconNames[iconIndex]
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
