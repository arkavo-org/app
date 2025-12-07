import ArkavoKit
import FlatBuffers
import OpenTDFKit
import SwiftData
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
    @Published var isLoading = true
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

        // Set loading to false after streams are loaded
        isLoading = false
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
            queue: nil,
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
            queue: nil,
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
            queue: nil,
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data else { return }
            Task { @MainActor [weak self] in
                print("\n=== GroupViewModel Handling NATS Message ===")
                // Decide if GroupViewModel needs to handle this or if it's delegated elsewhere
                await self?.handleNATSMessage(data) // Keep handler for now
            }
        }
        notificationObservers.append(natsObserver)

    }

    deinit {
        MainActor.assumeIsolated {
            notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }

    func requestStream(withPublicID publicID: Data) async throws -> Stream? {
        print("Requesting stream with publicID: \(publicID.base58EncodedString)")

        // Check if we already have the stream locally
        if let existingStream = try await PersistenceController.shared.fetchStream(withPublicID: publicID) {
            print("Found existing stream: \(existingStream.streamName)")
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
            targetIdVectorOffset: builder.createVector(bytes: publicID),
        )

        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .invite,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .userevent,
            dataOffset: userEventOffset,
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
                print("Stream received and saved: \(stream.streamName)")
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
            print("Stream already exists: \(existingStream.streamName)")
            return
        }

        // Create new stream
        let stream = Stream(
            publicID: Data(streamPublicId),
            creatorPublicID: Data(creatorPublicId),
            name: streamName,
            blurb: streamProfile.blurb ?? "",
            interests: streamProfile.interests ?? "",
            location: streamProfile.location ?? "",
            hasHighEncryption: streamProfile.encryptionLevel == .el2,
            hasHighIdentityAssurance: streamProfile.identityAssuranceLevel == .ial2,
            policies: Policies(
                admission: .open,
                interaction: .open,
                age: .forAll,
            ),
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
        let nameOffset = builder.create(string: stream.streamName)
        let blurbOffset = builder.create(string: stream.streamBlurb)
        let interestsOffset = builder.create(string: stream.streamInterests)
        let locationOffset = builder.create(string: stream.streamLocation)

        // Create Profile
        let profileOffset = Arkavo_Profile.createProfile(
            &builder,
            nameOffset: nameOffset,
            blurbOffset: blurbOffset,
            interestsOffset: interestsOffset,
            locationOffset: locationOffset,
            locationLevel: .approximate,
            identityAssuranceLevel: stream.streamHasHighIdentityAssurance ? .ial2 : .ial1,
            encryptionLevel: stream.streamHasHighEncryption ? .el2 : .el1,
        )

        // Create Activity
        let activityOffset = Arkavo_Activity.createActivity(
            &builder,
            dateCreated: Int64(Date().timeIntervalSince1970),
            expertLevel: .novice,
            activityLevel: .low,
            trustLevel: .low,
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
            streamLevel: .sl1,
        )

        // Create EntityRoot with Stream as the entity
        let entityRootOffset = Arkavo_EntityRoot.createEntityRoot(
            &builder,
            entityType: .stream,
            entityOffset: streamOffset,
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
            oneTimeAccess: false,
        )

        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .cache,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .cacheevent,
            dataOffset: cacheEventOffset,
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
                nano: nano,
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
                authTag: authTag,
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
        // 1. Get the list of regular stream IDs currently displayed
        let regularStreamIDs = await MainActor.run { streams.map { $0.persistentModelID } }

        // 2. Identify the actual Stream objects to delete based on the offsets
        let streamIDsToDelete = offsets.map { regularStreamIDs[$0] }

        // 3. Fetch and delete each identified stream directly from the context using its persistentModelID
        var deletedCount = 0
        var successfullyDeletedIDs = Set<PersistentIdentifier>()

        for persistentModelID in streamIDsToDelete {
            // Fetch the stream directly from the persistence controller using persistentModelID
            if let streamInContext = PersistenceController.shared.fetchStream(withPersistentModelID: persistentModelID) {
                    let name = streamInContext.streamName
                    let publicID = streamInContext.publicID
                    print("GroupViewModel: Attempting to fetch and delete stream '\(name)' (ID: \(publicID.base58EncodedString))")
                    // Ensure it's managed by the correct context before deleting
                    if streamInContext.modelContext == PersistenceController.shared.mainContext {
                        PersistenceController.shared.mainContext.delete(streamInContext)
                        print("   Fetched and marked stream for deletion in context.")
                        deletedCount += 1
                        successfullyDeletedIDs.insert(persistentModelID)
                    } else {
                        // This case should ideally not happen if fetch works correctly
                        print("   ❌ ERROR: Fetched stream is not managed by the main context. Deletion skipped.")
                    }
                } else {
                    // Log the error clearly if fetch fails
                    print("   ❌ ERROR: Could not find stream with persistentModelID \(persistentModelID) in context for deletion.")
                }
        }

        // 4. Save the changes only if deletions were successful
        if deletedCount > 0 {
            do {
                try await PersistenceController.shared.saveChanges()
                print("GroupViewModel: Successfully saved changes after deleting \(deletedCount) stream(s).")

                // 5. Update the @Published streams array directly to trigger UI refresh
                await MainActor.run { // Ensure UI updates on main thread
                    let initialCount = streams.count
                    streams.removeAll { successfullyDeletedIDs.contains($0.persistentModelID) }
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
        isLoading = true
        await loadStreams()
    }

}

// MARK: - Extensions

// MARK: - Main View

struct GroupView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: GroupViewModel = ViewModelFactory.shared.makeViewModel()
    @State private var isShareSheetPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let systemMargin: CGFloat = 16

    // Static constant for the base URL used in sharing
    static let streamBaseURL = "https://app.arkavo.com/stream/"

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
                        isPresented: $isShareSheetPresented,
                    )
                }
            }
        }
    }

    // Stream list
    private func streamListView(geometry: GeometryProxy) -> some View {
        // Show loading indicator while data is loading
        if viewModel.isLoading {
            return AnyView(
                ProgressView()
                    .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width)
                    .frame(maxHeight: .infinity),
            )
        }

        // Show WaveEmptyStateView if no streams exist after loading
        if viewModel.streams.isEmpty {
            return AnyView(
                WaveEmptyStateView()
                    .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width),
            )
        }

        return AnyView(
            List {
                Section {
                    ForEach(viewModel.streams) { stream in
                        streamRow(stream: stream)
                            .listRowInsets(EdgeInsets(top: 5, leading: systemMargin, bottom: 5, trailing: systemMargin))
                            .listRowBackground(Color(.systemBackground))
                    }
                    .onDelete(perform: deleteStream)
                } header: {
                    Text("Streams")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width)
            .background(Color(.systemBackground).ignoresSafeArea()),
        )
    }

    // Individual stream row
    func streamRow(stream: Stream) -> some View {
        GroupCardView(
            stream: stream,
            onSelect: {
                viewModel.selectedStream = stream
                sharedState.selectedStreamPublicID = stream.publicID
                sharedState.showChatOverlay = true
            },
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

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
                            Text(stream.streamName.isEmpty ? "Unknown" : stream.streamName)
                                .font(.headline)
                                .foregroundColor(.primary)
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
                    isPresented: $isShareSheetPresented,
                )
            }
        }
    }

    private func iconForStream(_ stream: Stream) -> String {
        // Hash-based icon for streams
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
