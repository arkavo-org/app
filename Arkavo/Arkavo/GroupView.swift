import ArkavoSocial
import FlatBuffers
import OpenTDFKit
import SwiftUI

// MARK: - Models

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

    private func handleNATSMessage(_ data: Data) async {
        do {
            // Create a deep copy of the data
            let copiedData = Data(data)
            let parser = BinaryParser(data: copiedData)
            let header = try parser.parseHeader()
            print("\n=== Group View Processing NATS Message ===")
            // Log the KAS locator body
            print("KAS Locator: \(header.payloadKeyAccess.kasLocator.body)")
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

    /// Deletes streams at the specified offsets from the filtered list of regular streams.
    func deleteStream(at offsets: IndexSet) async {
        // 1. Get the list of regular streams currently displayed
        // Ensure we filter based on the *current* state of viewModel.streams
        let regularStreams = await MainActor.run { streams.filter { !$0.isInnerCircleStream } }

        // 2. Identify the actual Stream objects to delete based on the offsets
        let streamsToDelete = offsets.map { regularStreams[$0] }

        // 3. Fetch and delete each identified stream directly from the context using its publicID
        var deletedCount = 0
        // Get the publicIDs to delete
        let publicIDsToDelete = streamsToDelete.map(\.publicID)

        for publicID in publicIDsToDelete {
            let streamName = streamsToDelete.first { $0.publicID == publicID }?.profile.name ?? "Unknown" // Get name for logging
            print("GroupViewModel: Attempting to fetch and delete stream '\(streamName)' (ID: \(publicID.base58EncodedString))")
            do {
                // Fetch the stream directly from the persistence controller
                if let streamInContext = try await PersistenceController.shared.fetchStream(withPublicID: publicID) {
                    // Ensure it's managed by the correct context before deleting
                    if streamInContext.modelContext == PersistenceController.shared.mainContext {
                        PersistenceController.shared.mainContext.delete(streamInContext)
                        print("   Fetched and marked stream for deletion in context.")
                        deletedCount += 1
                    } else {
                        // This case should ideally not happen if fetch works correctly
                        print("   ❌ ERROR: Fetched stream is not managed by the main context. Deletion skipped.")
                    }
                } else {
                    // Log the error clearly if fetch fails
                    print("   ❌ ERROR: Could not find stream \(publicID.base58EncodedString) in context for deletion.")
                }
            } catch {
                print("   ❌ ERROR: Failed to fetch stream \(publicID.base58EncodedString) for deletion: \(error)")
            }
        }

        // 4. Save the changes only if deletions were successful
        if deletedCount > 0 {
            // Keep track of IDs successfully marked for deletion
            let successfullyDeletedIDs = Set(publicIDsToDelete.prefix(deletedCount)) // Assuming order is preserved or adjust logic if needed

            do {
                try await PersistenceController.shared.saveChanges()
                print("GroupViewModel: Successfully saved changes after deleting \(deletedCount) stream(s).")

                // 5. Update the @Published streams array directly to trigger UI refresh
                await MainActor.run { // Ensure UI updates on main thread
                    let initialCount = streams.count
                    streams.removeAll { successfullyDeletedIDs.contains($0.publicID) }
                    print("GroupViewModel: Updated @Published streams array. Removed \(initialCount - streams.count) stream(s).")
                }
                // No need to call loadStreams() anymore as we updated the array directly
                // await loadStreams()
            } catch {
                print("❌ GroupViewModel: Error saving changes after deleting streams: \(error)")
                // Optionally show an error to the user
                // Consider rolling back context changes if save fails? SwiftData might handle this.
                // Consider rolling back context changes if save fails? SwiftData might handle this.
            }
        } else {
            print("GroupViewModel: No streams were marked for deletion.")
            // Still reload streams in case the state was inconsistent or fetch failed
            await loadStreams()
        }
    }

    /// Reloads the streams list, typically called after a creation or deletion action.
    func reloadStreamsAfterCreation() async {
        print("GroupViewModel: Reloading streams after potential creation/modification...")
        await loadStreams()
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
    // Observe the PeerDiscoveryManager for OT-TDF data - MOVED to GroupCreateView
    // @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager() // Keep for InnerCircleView
    @State private var isShareSheetPresented = false
    // @State private var innerCircleMessageText: String = "" // REMOVED: State for InnerCircle chat input
    // @FocusState private var isInnerCircleInputFocused: Bool // REMOVED: Focus state for the input field
    // @State private var isPeerSearchActive = false // MOVED to GroupCreateView
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Define systemMargin at the GroupView level
    private let systemMargin: CGFloat = 16 // Keep if needed by other parts, otherwise remove

    // Static constant for the base URL used in sharing
    static let streamBaseURL = "https://app.arkavo.com/stream/"
    // Static constant for "just now" string - MOVED to GroupCreateView
    // static let justNowString = "just now"

    var body: some View {
        // Use mainContent as the base view
        mainContent
            // Present GroupCreateView as a sheet
            .sheet(isPresented: $sharedState.showCreateView, onDismiss: {
                // Reload streams when the sheet is dismissed
                Task {
                    await viewModel.reloadStreamsAfterCreation()
                }
            }) {
                // Pass the necessary viewModel to the sheet content
                GroupCreateView(viewModel: viewModel)
                    .environmentObject(sharedState) // Ensure sheet has access to sharedState
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

    // Stream list - Changed ScrollView/LazyVStack to List
    private func streamListView(geometry: GeometryProxy) -> some View {
        List {
            // --- 1. InnerCircle Stream Section ---
            // Find the InnerCircle stream
            if let innerCircleStream = viewModel.streams.first(where: { $0.isInnerCircleStream }) {
                Section {
                    // Use the dedicated view for InnerCircle members
                    InnerCircleView(stream: innerCircleStream, peerManager: peerManager)
                        .environmentObject(sharedState)
                        .background(InnerCircleConstants.cardBackgroundColor) // Match background
                        .cornerRadius(InnerCircleConstants.cornerRadius) // Apply corner radius
                    // --- REMOVED: InnerCircle Chat Input ---
                }
                .listRowInsets(EdgeInsets(top: systemMargin / 2, leading: systemMargin, bottom: systemMargin / 2, trailing: systemMargin)) // Add padding around the InnerCircleView
                .listRowBackground(InnerCircleConstants.backgroundColor) // Match list background
                .listRowSeparator(.hidden) // Hide separator for this section
            }

            // --- 2. Other Streams Section ---
            let regularStreams = viewModel.streams.filter { !$0.isInnerCircleStream }
            if !regularStreams.isEmpty {
                Section {
                    // Iterate ONLY over regular streams
                    ForEach(regularStreams) { stream in
                        streamRow(stream: stream) // Use existing streamRow for non-InnerCircle
                            .listRowInsets(EdgeInsets(top: 5, leading: InnerCircleConstants.systemMargin, bottom: 5, trailing: InnerCircleConstants.systemMargin)) // Add padding within row
                            .listRowBackground(InnerCircleConstants.backgroundColor) // Match background
                    }
                    // Apply onDelete ONLY to regular streams
                    .onDelete(perform: deleteStream)
                } header: {
                    Text("Streams") // Header for regular streams
                        .font(InnerCircleConstants.headerFont)
                        .foregroundColor(InnerCircleConstants.primaryTextColor)
                    // List handles section header styling, remove extra padding
                    // .padding(.top, InnerCircleConstants.systemMargin)
                    // .padding(.horizontal, InnerCircleConstants.systemMargin)
                }
                .listRowSeparator(.hidden) // Hide separators if desired
            }
        }
        .listStyle(.plain) // Use plain style to remove default List background/styling
        .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width) // Keep specific width
        .background(InnerCircleConstants.backgroundColor.ignoresSafeArea()) // Use constant color
    }

    // Individual stream row (now only uses GroupCardView)
    func streamRow(stream: Stream) -> some View {
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
            // --- END: Implemented/Modified Methods --- MOVED to InnerCircleView
        }
    }

    // --- REMOVED: innerCircleMembersSection() ---
    // The logic is now directly embedded within streamListView for clarity.

    // --- REMOVED: Send InnerCircle Message Action ---

    // Function to handle stream deletion
    private func deleteStream(at offsets: IndexSet) {
        Task {
            await viewModel.deleteStream(at: offsets)
        }
    }

    // Chat overlay view
    var chatOverlayView: some View {
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
