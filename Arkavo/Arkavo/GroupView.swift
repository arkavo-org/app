import ArkavoSocial
import FlatBuffers
import MultipeerConnectivity
import OpenTDFKit
import SwiftUI
import UIKit

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

    // Removed shareVideo function as it was commented out and not implemented
    // func shareVideo(_ video: Video, to stream: Stream) async { ... }

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

// MARK: - Extensions

// Add notification name for refreshing InnerCircle members
extension Notification.Name {
    static let refreshInnerCircleMembers = Notification.Name("refreshInnerCircleMembers")
}

// Add showMembersList property to SharedState
extension SharedState {
    // This property is used to control the display of the InnerCircle members list
    var showMembersList: Bool {
        get { getState(forKey: "showMembersList") as? Bool ?? false }
        set { setState(newValue, forKey: "showMembersList") }
    }
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

    // For non-JSON data popup
    @State private var nonJsonBase64Data: String = ""
    @State private var nonJsonDataSize: Int = 0
    @State private var nonJsonPeerName: String = ""
    @State private var showNonJsonDataPopup: Bool = false
    // Store notification observer token
    @State private var nonJsonObserver: NSObjectProtocol?

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
            .overlay(
                Group {
                    if showNonJsonDataPopup {
                        VStack {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Non-JSON Data Received")
                                        .font(.headline)
                                    Spacer()
                                    Button(action: { showNonJsonDataPopup = false }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }

                                Text("From: \(nonJsonPeerName)")
                                    .font(.subheadline)

                                Text("Size: \(nonJsonDataSize) bytes")
                                    .font(.subheadline)

                                Text("Base64 Data:")
                                    .font(.subheadline)

                                ScrollView {
                                    Text(nonJsonBase64Data)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(4)
                                }
                                .frame(maxHeight: 200)
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 5)
                            .padding()

                            Spacer()
                        }
                        .background(Color.black.opacity(0.3).edgesIgnoringSafeArea(.all))
                        .onTapGesture {
                            // Dismiss when tapping background
                            showNonJsonDataPopup = false
                        }
                    }
                }
            )
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
        .sheet(isPresented: $sharedState.showMembersList) {
            if let stream = viewModel.selectedStream {
                NavigationView {
                    InnerCircleView(stream: stream, peerManager: peerManager)
                        .navigationTitle("InnerCircle Members")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    sharedState.showMembersList = false
                                }
                            }
                        }
                }
            }
        }
        // Refresh peer profiles when the view appears or peer list changes
        .onAppear {
            Task { await peerManager.refreshKeyStoreStatus() } // Also refreshes profiles

            // Add notification observer for non-JSON data
            // Store the token so we can remove it when the view disappears
            // Debug print notification name to ensure it's correct
            let notificationName = Notification.Name.nonJsonDataReceived
            print("🔔 Setting up observer for notification: \(notificationName.rawValue)")

            nonJsonObserver = NotificationCenter.default.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { notification in
                print("🔥 NOTIFICATION RECEIVED in GroupView: nonJsonDataReceived")

                guard let userInfo = notification.userInfo else {
                    print("❌ Notification has no userInfo")
                    return
                }

                print("📄 Notification userInfo: \(userInfo)")

                guard let base64Data = userInfo["data"] as? String else {
                    print("❌ No base64Data in notification")
                    return
                }

                guard let dataSize = userInfo["dataSize"] as? Int else {
                    print("❌ No dataSize in notification")
                    return
                }

                guard let peerName = userInfo["peerName"] as? String else {
                    print("❌ No peerName in notification")
                    return
                }

                print("✅ Received non-JSON data notification: \(dataSize) bytes from \(peerName)")

                // Update on main thread to ensure UI updates properly
                DispatchQueue.main.async { [self] in
                    print("🔄 Updating UI state for popup")
                    nonJsonBase64Data = base64Data
                    nonJsonDataSize = dataSize
                    nonJsonPeerName = peerName
                    showNonJsonDataPopup = true
                    print("🎯 showNonJsonDataPopup set to true")

                    // Auto-hide after 10 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                        print("⏱️ Auto-hiding popup after 10 seconds")
                        showNonJsonDataPopup = false
                    }
                }
            }

            print("Added non-JSON data notification observer")
        }
        .onDisappear {
            // Remove observer when view disappears
            if let observer = nonJsonObserver {
                NotificationCenter.default.removeObserver(observer)
                nonJsonObserver = nil
                print("Removed non-JSON data notification observer")
            }
        }
        .onChange(of: peerManager.connectedPeers) { _, _ in
            Task { await peerManager.refreshKeyStoreStatus() } // Refresh profiles when peers change
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
                VStack(spacing: 0) {
                    // Members button
                    Button(action: {
                        viewModel.selectedStream = stream
                        sharedState.showMembersList = true
                    }) {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.blue)

                            Text("InnerCircle Members")
                                .font(.subheadline)
                                .foregroundColor(.blue)

                            Spacer()

                            // Member count badge
                            let onlineCount = peerManager.connectedPeers.count
                            Text("\(onlineCount)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue))

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Peer discovery UI
                    innerCirclePeerDiscoveryUI(for: stream)
                }
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

                            Text(isPeerSearchActive ? "Broadcasting your presence" : "Find other devices nearby")
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

            // Connected peers list and OT-TDF views when active
            if isPeerSearchActive, viewModel.selectedStream == stream {
                VStack(spacing: 12) {
                    connectedPeersView

                    // Always show OT-TDF views when search is active
                    Divider().padding(.horizontal)

                    KeyStoreStatusView(
                        localInfo: peerManager.localKeyStoreInfo,
                        isRegenerating: peerManager.isRegeneratingKeys,
                        regenerateAction: {
                            Task {
                                await peerManager.regenerateLocalKeys()
                            }
                        }
                    )
                    .padding(.horizontal)

                    Divider().padding(.horizontal)
                }
                .padding(.bottom, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .transition(.opacity.combined(with: .move(edge: .top))) // Add transition
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isPeerSearchActive) // Animate the whole section
        .animation(.easeInOut(duration: 0.3), value: peerManager.connectedPeers) // Animate peer list changes
        .animation(.easeInOut(duration: 0.3), value: peerManager.localKeyStoreInfo?.count) // Animate key count changes
        .animation(.easeInOut(duration: 0.3), value: peerManager.connectedPeerProfiles) // Animate profile changes
    }

    // Toggle peer search state
    private func togglePeerSearch(for stream: Stream) async {
        isPeerSearchActive.toggle()

        if isPeerSearchActive {
            do {
                // Select this stream and start searching
                peerManager.selectedStream = stream
                try await peerManager.setupMultipeerConnectivity(for: stream)
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
        VStack(spacing: 8) {
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
            .padding(.top, 6)
            .padding(.horizontal, 4)

            // Show search status banner when active
            if case .searching = connectionStatus {
                HStack {
                    Text("Broadcasting and listening...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    ProgressView().scaleEffect(0.7)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
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
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            // Divider if we have peers or specific states
            if peerCount > 0 || connectionStatus == .searching || connectionStatus == .connecting {
                Divider().padding(.vertical, 4)
            }

            if peerCount > 0 {
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
                    // Use peerManager.connectedPeerProfiles which holds the Profile data
                    ForEach(peerManager.connectedPeers, id: \.self) { peer in
                        // Pass the peer and the profile (if available) to peerRow
                        peerRow(peer: peer, profile: peerManager.connectedPeerProfiles[peer])
                    }
                }

                // Add a browse button for finding more peers
                Button(action: { presentBrowserController() }) {
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
                emptyStateView() // Not searching and no peers
            } else if isPeerSearchActive {
                searchingStateView() // Searching or connecting but no peers yet
            }
        }
        .padding(.horizontal)
        // Removed bottom padding to let parent control spacing
        // .padding(.bottom, 8)
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
            .frame(width: 8, height: 8)

            Text(statusText(for: status))
                .font(.caption)
                .foregroundColor(statusColor(for: status))
        }
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
        VStack(spacing: 8) {
            Spacer().frame(height: 20)
            Image(systemName: "person.2.slash").font(.largeTitle).foregroundColor(.secondary.opacity(0.5))
            Text("Not Searching").font(.callout).foregroundColor(.secondary)
            Text("Toggle the search button to find nearby devices.").font(.caption2).foregroundColor(.secondary.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal)
            Button(action: {
                if let stream = viewModel.selectedStream { Task { await togglePeerSearch(for: stream) } }
            }) { Text("Start Searching").padding(.horizontal, 16).padding(.vertical, 8) }
                .buttonStyle(.bordered).padding(.top, 8)
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
            SignalPulseView().frame(width: 50, height: 50)
            Text("Scanning for Devices...").font(.callout).foregroundColor(.secondary)
            Text("Ensure other devices are also searching.").font(.caption2).foregroundColor(.secondary.opacity(0.8))
            Button(action: { presentBrowserController() }) {
                Text("Browse Manually").padding(.horizontal, 16).padding(.vertical, 8)
            }
            .buttonStyle(.bordered).padding(.top, 8)
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, 8)
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

    // Individual peer row - Updated to accept Profile
    private func peerRow(peer: MCPeerID, profile: Profile?) -> some View {
        HStack {
            // Use PeerProfileView if profile exists, otherwise fallback
            if let profile {
                PeerProfileView(profile: profile, connectionTime: peerManager.peerConnectionTimes[peer])
            } else {
                // Fallback view when profile is not yet available
                HStack {
                    Image(systemName: "person.circle.fill").foregroundColor(.gray).font(.title3) // Placeholder avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(peer.displayName).font(.subheadline).fontWeight(.medium).foregroundColor(.secondary) // Indicate loading/fallback
                        Text("Connecting...").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    ProgressView().scaleEffect(0.5) // Indicate loading state
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
        .padding(.horizontal, 4) // Add horizontal padding for spacing between rows
    }

    // Format the connection time
    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 { return "just now" }
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
    let peerManager: PeerDiscoveryManager
    @EnvironmentObject var sharedState: SharedState
    @State private var showOfflineMembers: Bool = true
    @State private var searchText: String = ""
    @State private var innerCircleProfiles: [Profile] = [] // All profiles belonging to this InnerCircle
    @State private var showStatusMessage = false
    @State private var statusMessage = ""

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
            Task {
                await loadInnerCircleProfiles()
            }

            // Listen for notifications to refresh the member list
            NotificationCenter.default.addObserver(
                forName: .refreshInnerCircleMembers,
                object: nil,
                queue: .main
            ) { _ in
                Task {
                    await loadInnerCircleProfiles()
                }
            }

            // Check for status messages
            if let message = sharedState.getState(forKey: "statusMessage") as? String {
                statusMessage = message
                showStatusMessage = true
                // Clear the message after display
                sharedState.setState("", forKey: "statusMessage")
            }
        }
        .overlay(statusMessageOverlay)
    }

    // MARK: - Computed Properties (Refactored for Simplicity)

    // All currently connected online profiles from peer manager
    private var onlineProfiles: [Profile] {
        Array(peerManager.connectedPeerProfiles.values)
    }

    // All offline profiles (in InnerCircle but not currently connected)
    private var offlineProfiles: [Profile] {
        // Get IDs of online profiles for efficient lookup
        let onlineProfileIDs = Set(onlineProfiles.map { $0.id })
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

    // Load all InnerCircle profiles from persistence
    private func loadInnerCircleProfiles() async {
        do {
            // Fetch all profiles that belong to the InnerCircle stream
            // This would ideally use a relationship query in the real implementation
            // For now, assume 'innerCircleProfiles' holds the relevant members
            // We might need a way to fetch profiles specifically associated with 'stream'
            let allProfiles = try await PersistenceController.shared.fetchAllProfiles()

            // Filter to include only profiles that have been added to InnerCircle
            // In real implementation, this would use a proper relationship query
            // For now, just filter out the current user
            let currentUserID = ViewModelFactory.shared.getCurrentProfile()?.id
            innerCircleProfiles = allProfiles.filter { profile in
                profile.id != currentUserID
                // Add logic here if 'stream' has a list of member IDs/profiles
                // e.g., stream.memberIDs.contains(profile.id)
            }

            // Save updated lastSeen times (if applicable, though lastSeen was removed)
            // try await PersistenceController.shared.saveChanges()

        } catch {
            print("Error loading InnerCircle profiles: \(error)")
            innerCircleProfiles = []
        }
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
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                    await peerManager.refreshKeyStoreStatus()
                }
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                        .padding(.horizontal)
                        .padding(.vertical, 4)
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
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .environmentObject(sharedState)
                    }
                }

                // Empty state
                if onlineToShow.isEmpty, (offlineToShow.isEmpty || !showOfflineMembers) {
                    emptyStateView
                }
            }
            .padding(.vertical, 8)
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
        .padding(.horizontal)
        .padding(.vertical, 4)
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
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // Status message overlay
    @ViewBuilder
    private var statusMessageOverlay: some View {
        if showStatusMessage {
            VStack {
                Text(statusMessage)
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(10)
                    .padding()
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
    let peerManager: PeerDiscoveryManager // Added peerManager property
    @State private var showRemoveConfirmation = false
    @Environment(\.modelContext) private var modelContext

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
                } else {
                    // Removed lastSeen display
                    Text("Offline") // Simple offline indicator
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator
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
                    .padding(8)
                    .background(Circle().fill(isOnline ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .disabled(!isOnline)

            // Remove member button
            Button(action: {
                showRemoveConfirmation = true
            }) {
                Image(systemName: "person.fill.xmark")
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(8)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // Open direct chat with this member
    private func openDirectChat() {
        // Set the InnerCircle stream as selected
        sharedState.selectedStreamPublicID = stream.publicID

        // Close members list
        sharedState.showMembersList = false

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

        if timeInterval < 60 { return "just now" }
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

    // Generates a simple avatar based on the profile name
    private var avatarView: some View {
        let initials = profile.name.prefix(2).uppercased()
        let color = avatarColor(for: profile.publicID) // Use publicID for consistent color

        return ZStack {
            Circle()
                .fill(color)
            Text(initials)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
    }

    // Generates a consistent color based on profile data (e.g., publicID)
    private func avatarColor(for data: Data) -> Color {
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

        if timeInterval < 60 { return "just now" }
        if timeInterval < 3600 { let minutes = Int(timeInterval / 60); return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        if timeInterval < 86400 { let hours = Int(timeInterval / 3600); return "\(hours) hour\(hours == 1 ? "" : "s") ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - One-Time TDF Views

// View for displaying local KeyStore status
struct KeyStoreStatusView: View {
    let localInfo: (count: Int, capacity: Int)?
    let isRegenerating: Bool
    let regenerateAction: () -> Void

    private var percentage: Double {
        guard let info = localInfo else { return 0 }
        // Use hardcoded capacity of 8192
        return Double(info.count) / 8192.0
    }

    private var gaugeColor: Color {
        switch percentage {
        case let p where p < 0.1: .red
        case let p where p < 0.5: .orange
        default: .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Local KeyStore Status")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                if isRegenerating {
                    ProgressView().scaleEffect(0.7)
                }
            }

            if let info = localInfo {
                HStack {
                    Text("Keys:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    // Use hardcoded capacity of 8192
                    Text("\(info.count) / 8192")
                        .font(.caption2.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Text(String(format: "%.0f%%", percentage * 100))
                        .font(.caption2)
                        .foregroundColor(gaugeColor)
                }

                ProgressView(value: percentage)
                    .progressViewStyle(LinearProgressViewStyle(tint: gaugeColor))
                    .animation(.easeInOut, value: percentage)

                Button(action: regenerateAction) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                        Text("Regenerate Keys")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isRegenerating)
                .padding(.top, 4)

            } else {
                Text("KeyStore information not available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8) // Add vertical padding
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
