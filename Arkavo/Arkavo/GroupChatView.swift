import ArkavoSocial
import FlatBuffers
import OpenTDFKit
import SwiftUI

// MARK: - Models

@MainActor
class DiscordViewModel: ObservableObject, ArkavoClientDelegate {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var streams: [Stream] = []
    @Published var selectedStream: Stream?
    @Published var connectionState: ArkavoClientState = .disconnected
    // Track pending streams by their ephemeral public key
    private var pendingStreams: [Data: (header: Header, payload: Payload, nano: NanoTDF)] = [:]

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        client.delegate = self
        Task {
            await loadStreams()
        }
    }

    private func loadStreams() async {
        streams = account.streams
    }

    func requestStream(withPublicID publicID: Data) async throws -> Stream? {
        print("Requesting stream with publicID: \(publicID.base58EncodedString)")

        // First check if we already have the stream locally
        if let stream = try await PersistenceController.shared.fetchStream(withPublicID: publicID)?.first {
            print("Found existing stream: \(stream.profile.name)")
            return stream
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
            if let stream = try await PersistenceController.shared.fetchStream(withPublicID: publicID)?.first {
                print("Stream received and saved: \(stream.profile.name)")
                return stream
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        }

        print("No stream found after timeout")
        return nil
    }

    func handleStreamData(_ data: Data) async throws {
        print("Handling stream data")
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
        guard let creatorPublicId = arkStream.creatorPublicId?.id,
              let profile = arkStream.profile,
              let name = profile.name
        else {
            throw ArkavoError.invalidResponse
        }

        // Create and save stream
        let stream = Stream(
            creatorPublicID: Data(creatorPublicId),
            profile: Profile(
                name: name,
                blurb: profile.blurb,
                interests: profile.interests ?? "",
                location: profile.location ?? "",
                hasHighEncryption: profile.encryptionLevel == .el2,
                hasHighIdentityAssurance: profile.identityAssuranceLevel == .ial2
            ),
            policies: Policies(
                admission: .open,
                interaction: .open,
                age: .forAll
            )
        )

        try PersistenceController.shared.saveStream(stream)
        account.streams.append(stream)
        try await PersistenceController.shared.saveChanges()

        // Update local streams array
        if !streams.contains(where: { $0.publicID == stream.publicID }) {
            streams.append(stream)
        }
        print("Stream saved successfully: \(stream.publicID)")
    }

    func sendStreamCacheEvent() async throws {
        // Create Stream using FlatBuffers
        var builder = FlatBufferBuilder(initialSize: 1024)

        // Create nested structures first
        let nameOffset = builder.create(string: profile.name)
        let blurbOffset = builder.create(string: profile.blurb ?? "")
        let interestsOffset = builder.create(string: profile.interests)
        let locationOffset = builder.create(string: profile.location)

        // Create Profile
        let profileOffset = Arkavo_Profile.createProfile(
            &builder,
            nameOffset: nameOffset,
            blurbOffset: blurbOffset,
            interestsOffset: interestsOffset,
            locationOffset: locationOffset,
            locationLevel: .approximate,
            identityAssuranceLevel: profile.hasHighIdentityAssurance ? .ial2 : .ial1,
            encryptionLevel: profile.hasHighEncryption ? .el2 : .el1
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
        let publicIdVector = builder.createVector(bytes: streams[0].publicID)
        let publicIdOffset = Arkavo_PublicId.createPublicId(&builder, idVectorOffset: publicIdVector)
        let creatorPublicIdVector = builder.createVector(bytes: streams[0].creatorPublicID)
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
        let targetIdVector = builder.createVector(bytes: streams[0].publicID)
        let targetPayloadVector = builder.createVector(bytes: targetPayload)

        let cacheEventOffset = Arkavo_CacheEvent.createCacheEvent(
            &builder,
            targetIdVectorOffset: targetIdVector,
            targetPayloadVectorOffset: targetPayloadVector,
            ttl: 3600, // 1 hour TTL
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

    // Convert Stream to Server view model
    func serverFromStream(_ stream: Stream) -> Server {
        Server(
            id: stream.id.uuidString,
            name: stream.profile.name,
            imageURL: nil,
            icon: iconForStream(stream),
            unreadCount: stream.thoughts.count,
            hasNotification: !stream.thoughts.isEmpty,
            description: stream.profile.blurb ?? "No description available",
            policies: StreamPolicies(
                agePolicy: stream.policies.age,
                admissionPolicy: stream.policies.admission,
                interactionPolicy: stream.policies.interaction
            )
        )
    }

    private func iconForStream(_ stream: Stream) -> String {
        switch stream.policies.age {
        case .onlyAdults:
            "person.fill"
        case .onlyKids:
            "figure.child"
        case .forAll:
            "figure.wave"
        case .onlyTeens:
            "person.3.fill"
        }
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

            case 0x05, 0x06: // NATS message/event
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
        print("Message length: \(data.count)")

        guard data.count == 93 else {
            if data.count == 33 {
                let identifier = data
                print("Received DENY for EPK: \(identifier.hexEncodedString())")
                return
            }
            print("Invalid rewrapped key length: \(data.count)")
            return
        }

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
            print("Decrypting rewrapped key...")
            let symmetricKey = try client.decryptRewrappedKey(
                nonce: nonce,
                rewrappedKey: rewrappedKey,
                authTag: authTag
            )
            print("Successfully decrypted rewrapped key")

            // Decrypt the stream data
            print("Decrypting stream data...")
            let decryptedData = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
            print("Successfully decrypted stream data")

            // Now process the decrypted FlatBuffer data
            try await handleStreamData(decryptedData)

        } catch {
            print("❌ Error processing rewrapped key: \(error)")
        }
    }
}

struct StreamPolicies: Hashable, Equatable {
    let agePolicy: AgePolicy
    let admissionPolicy: AdmissionPolicy
    let interactionPolicy: InteractionPolicy

    func hash(into hasher: inout Hasher) {
        hasher.combine(agePolicy)
        hasher.combine(admissionPolicy)
        hasher.combine(interactionPolicy)
    }

    static func == (lhs: StreamPolicies, rhs: StreamPolicies) -> Bool {
        lhs.agePolicy == rhs.agePolicy &&
            lhs.admissionPolicy == rhs.admissionPolicy &&
            lhs.interactionPolicy == rhs.interactionPolicy
    }
}

struct Server: Identifiable, Hashable, Equatable {
    let id: String
    let name: String
    let imageURL: String?
    let icon: String
    var unreadCount: Int
    var hasNotification: Bool
    let description: String
    let policies: StreamPolicies

    static func == (lhs: Server, rhs: Server) -> Bool {
        lhs.id == rhs.id &&
            lhs.name == rhs.name &&
            lhs.imageURL == rhs.imageURL &&
            lhs.icon == rhs.icon &&
            lhs.unreadCount == rhs.unreadCount &&
            lhs.hasNotification == rhs.hasNotification &&
            lhs.description == rhs.description &&
            lhs.policies == rhs.policies
    }
}

// MARK: - Main View

struct GroupChatView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: DiscordViewModel = ViewModelFactory.shared.makeDiscordViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var showCreateServer = false
    @State private var showMembersList = false
    @State private var isShareSheetPresented = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // MARK: - Stream List

                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if viewModel.streams.isEmpty {
                                EmptyStateView()
                            } else {
                                ForEach(viewModel.streams) { stream in
                                    ServerCardView(
                                        server: viewModel.serverFromStream(stream),
                                        stream: stream,
                                        onSelect: {
                                            viewModel.selectedStream = stream
                                            navigationPath.append(stream)
                                        },
                                        onShare: {
                                            viewModel.selectedStream = stream
                                            isShareSheetPresented = true
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 16)
                    }
                    .frame(width: horizontalSizeClass == .regular ? 320 : geometry.size.width)
                    .background(Color(.systemGroupedBackground).ignoresSafeArea())

                    // MARK: - Chat View (iPad/Mac)

                    if horizontalSizeClass == .regular,
                       let selectedStream = viewModel.selectedStream
                    {
                        ChatView(viewModel: ViewModelFactory.shared.makeChatViewModel(stream: selectedStream))
                    }
                }
            }
            .navigationDestination(for: Stream.self) { stream in
                if horizontalSizeClass == .compact {
                    ChatView(viewModel: ViewModelFactory.shared.makeChatViewModel(stream: stream))
                        .navigationTitle(stream.profile.name)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    Task {
                                        do {
                                            try await viewModel.sendStreamCacheEvent()
                                            viewModel.selectedStream = stream
                                            isShareSheetPresented = true
                                        } catch {
                                            print("Error caching stream: \(error)")
                                        }
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                }
            }
            .navigationDestination(for: DeepLinkDestination.self) { destination in
                switch destination {
                case let .stream(publicID):
                    StreamLoadingView(publicID: publicID)
                case .profile:
                    EmptyView()
                }
            }
            .sheet(isPresented: $showCreateServer) {
                NavigationStack {
                    GroupCreateView()
                }
            }
        }
        .sheet(isPresented: $isShareSheetPresented) {
            if let stream = viewModel.selectedStream {
                ShareSheet(
                    activityItems: [URL(string: "https://app.arkavo.com/stream/\(stream.publicID.base58EncodedString)")!],
                    isPresented: $isShareSheetPresented
                )
            }
        }
    }
}

// MARK: - Supporting Views

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Communities Yet")
                .font(.headline)
            Text("Create or join a community to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }
}

// MARK: - Server Card

struct ServerCardView: View {
    let server: Server
    let stream: Stream
    let onSelect: () -> Void
    let onShare: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    // Server Icon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)

                        Image(systemName: server.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }

                    // Server Info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(server.name)
                                .font(.headline)
                                .foregroundColor(.primary)

                            if server.hasNotification {
                                NotificationBadge(count: server.unreadCount)
                            }
                        }

                        Text(server.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Add share button
                    if stream.policies.admission != .closed {
                        Button(action: onShare) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 8)
                    }

                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    PolicyRow(icon: "person.3.fill",
                              title: "Age Policy",
                              value: server.policies.agePolicy.rawValue)
                    PolicyRow(icon: "door.left.hand.open",
                              title: "Admission",
                              value: server.policies.admissionPolicy.rawValue)
                    PolicyRow(icon: "bubble.left.and.bubble.right",
                              title: "Interaction",
                              value: server.policies.interactionPolicy.rawValue)

                    Divider()
                        .padding(.vertical, 8)
                }
                .padding(.horizontal)
                .padding(.bottom, 16)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct NotificationBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red)
            .foregroundColor(.white)
            .clipShape(Capsule())
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
