import ArkavoSocial
import FlatBuffers
import OpenTDFKit
import SwiftUI
import MultipeerConnectivity

// MARK: - Models

@MainActor
final class GroupViewModel: ViewModel, ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var streams: [Stream] = []
    @Published var selectedStream: Stream?
    @Published var connectionState: ArkavoClientState = .disconnected
    // Track pending streams by their ephemeral public key
    private var pendingStreams: [Data: (header: Header, payload: Payload, nano: NanoTDF)] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    // Expose the one-time TDF mode flag
    let oneTimeTDFEnabled: Bool = true

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
        print("- Client delegate set: \(client.delegate != nil)")
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
        let stateObserver = NotificationCenter.default.addObserver(
            forName: .arkavoClientStateChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let state = notification.userInfo?["state"] as? ArkavoClientState else { return }
            Task { @MainActor [weak self] in
                self?.connectionState = state
            }
        }
        notificationObservers.append(stateObserver)

        // Observer for decrypted messages
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
                    if policy.type == .streamProfile {
                        print("\n=== GroupViewModel Processing Decrypted Stream Data ===")
                        print("Data size: \(data.count)")
                        print("Policy type: \(policy.type)")
                        try await self?.handleStreamData(data)
                    }
                } catch {
                    print("❌ Error processing stream data: \(error)")
                    print("Error details: \(String(describing: error))")
                }
            }
        }
        notificationObservers.append(messageObserver)

        // Observer for NATS messages
        let natsObserver = NotificationCenter.default.addObserver(
            forName: .natsMessageReceived,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data else { return }
            Task { @MainActor [weak self] in
                print("\n=== Handling NATS Message ===")
                await self?.handleNATSMessage(data)
            }
        }
        notificationObservers.append(natsObserver)
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
                blurb: profile.blurb,
                interests: streamProfile.interests ?? "",
                location: streamProfile.location ?? "",
                hasHighEncryption: streamProfile.encryptionLevel == .el2,
                hasHighIdentityAssurance: streamProfile.identityAssuranceLevel == .ial2
            ),
            policies: Policies(
                admission: .open,
                interaction: .open,
                age: .forAll
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

    func shareVideo(_ video: Video, to stream: Stream) async {
        print("Sharing video \(video.id) to stream \(stream.profile.name)")
        //        do {
        //            try await client.shareVideo(video, to: stream)
        //        } catch {
        //            print("Error sharing video: \(error)")
        //        }
    }

    nonisolated func clientDidChangeState(_: ArkavoSocial.ArkavoClient, state: ArkavoSocial.ArkavoClientState) {
        Task { @MainActor in
            self.connectionState = state
        }
    }

    nonisolated func clientDidReceiveMessage(_: ArkavoClient, message: Data) {
        print("\n=== clientDidReceiveMessage ===")
        guard let messageType = message.first else {
            print("No message type byte found")
            return
        }
        print("Message type: 0x\(String(format: "%02X", messageType))")

        let messageData = message.dropFirst()

        Task {
            switch messageType {
            case 0x04: // Rewrapped key
                await handleRewrappedKeyMessage(messageData)

            case 0x05: // NATS message NanoTDF
                await handleNATSMessage(messageData)

            default:
                print("Unknown message type: 0x\(String(format: "%02X", messageType))")
            }
        }
    }

    nonisolated func clientDidReceiveError(_: ArkavoSocial.ArkavoClient, error: any Error) {
        Task { @MainActor in
            print("Arkavo client error: \(error)")
            // You might want to update UI state here
            // self.errorMessage = error.localizedDescription
            // self.showError = true
        }
    }

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
}

// MARK: - Main View

struct GroupView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: GroupViewModel = ViewModelFactory.shared.makeViewModel()
    @State private var showMembersList = false
    @State private var isShareSheetPresented = false
    @State private var isPeerSearchActive = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
                let urlString = "https://app.arkavo.com/stream/\(stream.publicID.base58EncodedString)"
                if let url = URL(string: urlString) {
                    ShareSheet(
                        activityItems: [url],
                        isPresented: $isShareSheetPresented
                    )
                }
            }
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
    
    // Scrollable stream list
    private func streamScrollView(geometry: GeometryProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.streams) { stream in
                    streamRow(stream: stream)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    // Individual stream row with InnerCircle UI if applicable
    private func streamRow(stream: Stream) -> some View {
        VStack(spacing: 0) {
            // Main card view
            GroupCardView(
                stream: stream,
                onSelect: {
                    viewModel.selectedStream = stream
                    sharedState.selectedStreamPublicID = stream.publicID
                    sharedState.showChatOverlay = true
                }
            )
            
            // InnerCircle UI if applicable
            if stream.isInnerCircleStream {
                // Add one-time TDF badge
                HStack {
                    Spacer()
                    if viewModel.oneTimeTDFEnabled {
                        Text("One-Time TDF")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                
                innerCirclePeerDiscoveryUI(for: stream)
            }
        }
    }
    
    // Inner Circle peer discovery UI
    private func innerCirclePeerDiscoveryUI(for stream: Stream) -> some View {
        VStack(spacing: 0) {
            // Search toggle button with improved visual design
            HStack {
                Button(action: {
                    Task {
                        await togglePeerSearch(for: stream)
                    }
                }) {
                    HStack {
                        // Icon with dynamic appearance
                        ZStack {
                            Circle()
                                .fill(isPeerSearchActive ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                                .frame(width: 36, height: 36)
                            
                            Image(systemName: isPeerSearchActive ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(isPeerSearchActive ? .red : .blue)
                        }
                        
                        // Text label with more detail
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isPeerSearchActive ? "Stop Searching" : "Search for Nearby Devices")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(isPeerSearchActive ? .red : .blue)
                            
                            Text(isPeerSearchActive ? "Broadcasting your presence to nearby devices" : "Find other devices in your immediate area")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Indicator for active state
                        if isPeerSearchActive {
                            // Pulsing dot when active
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .opacity(isPeerSearchActive ? 1.0 : 0.0)
                                .scaleEffect(isPeerSearchActive ? 1.0 : 0.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(PlainButtonStyle()) // Use plain button style for custom appearance
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .animation(.easeInOut(duration: 0.2), value: isPeerSearchActive)
            
            // Connected peers list when active
            if isPeerSearchActive && viewModel.selectedStream == stream {
                connectedPeersView
            }
        }
    }
    
    // Toggle peer search state
    private func togglePeerSearch(for stream: Stream) async {
        isPeerSearchActive.toggle()
        
        // Connect to the peer discovery manager
        let peerManager = ViewModelFactory.shared.getPeerDiscoveryManager()
        
        if isPeerSearchActive {
            do {
                // Select this stream and start searching
                peerManager.selectedStream = stream
                try await peerManager.setupMultipeerConnectivity(for: stream)
                try peerManager.startSearchingForPeers()
                
                // Optionally present the browser controller for manual peer selection
                if let browserVC = peerManager.getPeerBrowser(),
                   let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootController = windowScene.windows.first?.rootViewController {
                    rootController.present(browserVC, animated: true)
                }
            } catch {
                // If there was an error starting peer search, show it to the user
                print("Failed to start peer search: \(error.localizedDescription)")
                isPeerSearchActive = false
            }
        } else {
            // Stop searching
            peerManager.stopSearchingForPeers()
        }
    }
    
    // Connected peers list view
    private var connectedPeersView: some View {
        VStack(spacing: 8) {
            // Get the peer discovery manager to display connected peers
            let peerManager = ViewModelFactory.shared.getPeerDiscoveryManager()
            let peerCount = peerManager.connectedPeers.count
            let connectionStatus = peerManager.connectionStatus
            
            // Status bar with improved connection status display
            HStack {
                connectionStatusIndicator(status: connectionStatus)
                
                Spacer()
                
                // Show connected peer count with icon
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                    
                    Text("\(peerCount) \(peerCount == 1 ? "Peer" : "Peers")")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                }
            }
            .padding(.top, 6)
            .padding(.horizontal, 4)
            
            // Show search status banner when active
            if case .searching = connectionStatus {
                // Searching animation banner
                HStack {
                    Text("Broadcasting and listening for nearby devices...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Activity indicator
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(Color(.secondarySystemBackground).opacity(0.5))
                .cornerRadius(6)
            }
            
            // Show error message if there's an error
            if case .failed(let error) = connectionStatus {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Divider if we have peers
            if peerCount > 0 {
                Divider()
                    .padding(.vertical, 4)
                
                // Title for peers section
                Text("Nearby Devices")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 2)
                
                // Show list of connected peers with spacing between them
                VStack(spacing: 6) {
                    ForEach(peerManager.connectedPeers, id: \.self) { peer in
                        peerRow(peer: peer)
                    }
                }
                
                // Add a browse button for finding more peers
                Button(action: {
                    presentBrowserController()
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Find More Peers")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
                
            } else if case .idle = connectionStatus {
                // Not searching and no peers
                emptyStateView()
            } else {
                // Searching or connecting but no peers yet
                searchingStateView()
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .animation(.easeInOut(duration: 0.2), value: isPeerSearchActive)
    }
    
    // Connection status indicator
    private func connectionStatusIndicator(status: ConnectionStatus) -> some View {
        HStack {
            switch status {
            case .idle:
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("Inactive")
                    .font(.caption)
                    .foregroundColor(.gray)
                
            case .searching:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .opacity(0.8)
                    .animation(Animation.easeInOut(duration: 1.0).repeatForever(), value: true)
                Text("Actively Searching")
                    .font(.caption)
                    .foregroundColor(.green)
                
            case .connecting:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundColor(.blue)
                
            case .connected:
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
                
            case .failed:
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("Connection Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    // Empty state view when no search is active
    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 20)
            
            Image(systemName: "person.2.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No Devices Found")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Text("Toggle the search button to start looking for nearby devices")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                if let stream = viewModel.selectedStream {
                    Task {
                        await togglePeerSearch(for: stream)
                    }
                }
            }) {
                Text("Start Searching")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, 8)
    }
    
    // Searching state view when actively looking for peers
    private func searchingStateView() -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 10)
            
            // Pulsing signal animation
            SignalPulseView()
                .frame(width: 50, height: 50)
            
            Text("Scanning for Devices...")
                .font(.callout)
                .foregroundColor(.secondary)
            
            Text("This may take a moment")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
            
            Button(action: {
                presentBrowserController()
            }) {
                Text("Browse Manually")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, 8)
    }
    
    // Present the browser controller manually
    private func presentBrowserController() {
        let peerManager = ViewModelFactory.shared.getPeerDiscoveryManager()
        if let browserVC = peerManager.getPeerBrowser(),
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootController = windowScene.windows.first?.rootViewController {
            rootController.present(browserVC, animated: true)
        }
    }
    
    // Individual peer row
    private func peerRow(peer: MCPeerID) -> some View {
        let peerManager = ViewModelFactory.shared.getPeerDiscoveryManager()
        
        return HStack {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                // Display connection timestamp with real time if available
                if let connectionTime = peerManager.peerConnectionTimes[peer] {
                    Text("Connected \(connectionTimeString(connectionTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Connected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Connection status indicator with animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 16, height: 16)
                
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
            }
            
            // Add message button
            Button(action: {
                // Handle sending a message to this specific peer
                // Would be implemented in a more complete version
            }) {
                Image(systemName: "message.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .buttonStyle(BorderlessButtonStyle())
            .padding(.leading, 8)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal, 4)
    }
    
    // Format the connection time
    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    // Animated signal pulse for searching animation
    struct SignalPulseView: View {
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0.0
        @State private var pulsate: Bool = false
        
        var body: some View {
            ZStack {
                // First concentric circle group with pulse animation
                ZStack {
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Color.blue.opacity(0.7 - Double(i) * 0.2), lineWidth: 1)
                            .scaleEffect(scale - CGFloat(i) * 0.1)
                    }
                }
                .scaleEffect(pulsate ? 1.2 : 0.8)
                
                // Second ring that rotates
                Circle()
                    .trim(from: 0.2, to: 0.8)
                    .stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3]))
                    .rotationEffect(.degrees(rotation))
                    .scaleEffect(0.7)
                
                // Center elements
                ZStack {
                    // Center dot background
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 12, height: 12)
                    
                    // Center dot
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                }
            }
            .onAppear {
                // Pulse animation
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsate = true
                }
                
                // Continuous rotation animation
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
                
                // Scale animation
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                    scale = 1.1
                }
            }
        }
    }
    
    // Chat overlay view
    private var chatOverlayView: some View {
        Group {
            if sharedState.showChatOverlay,
               let streamPublicID = sharedState.selectedStreamPublicID {
                ChatOverlay(streamPublicID: streamPublicID)
            }
        }
    }
}

// MARK: - Server Card

struct GroupCardView: View {
    let stream: Stream
    let onSelect: () -> Void
    @State private var isShareSheetPresented = false

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
                .padding(.trailing, 4)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $isShareSheetPresented) {
            ShareSheet(
                activityItems: [URL(string: "https://app.arkavo.com/stream/\(stream.publicID.base58EncodedString)")!],
                isPresented: $isShareSheetPresented
            )
        }
    }

    private func iconForStream(_ stream: Stream) -> String {
        // Convert the publicID to a hash value
        let hashValue = stream.publicID.hashValue

        // Use the hash value modulo 32 to determine the icon
        let iconIndex = abs(hashValue) % 32

        // Define an array of 32 SF Symbols
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
                Text(thought.nano.hexEncodedString())
                    .font(.headline)
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
