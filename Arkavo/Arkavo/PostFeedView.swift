import ArkavoSocial
import CryptoKit
import Foundation
import SwiftUI
#if os(iOS)
    import UIKit
#endif
import FlatBuffers

// MARK: - View Models

@MainActor
class PostFeedViewModel: ObservableObject {
    private let client: ArkavoClient
    private let account: Account
    private let profile: Profile
    private var notificationObservers: [Any] = []
    @Published var thoughts: [Thought] = []
    @Published var currentThoughtIndex = 0
    @Published var isLoading = false
    @Published var error: Error?

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile

        // Load initial thoughts
        Task {
            await loadThoughts()
        }
        setupNotifications()
    }

    private func setupNotifications() {
        print("PostFeedViewModel: setupNotifications")
        // Clean up any existing observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        // Connection state changes
        let stateObserver = NotificationCenter.default.addObserver(
            forName: .arkavoClientStateChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let state = notification.userInfo?["state"] as? ArkavoClientState else { return }
            Task { @MainActor [weak self] in
                self?.handleConnectionStateChange(state)
            }
        }
        notificationObservers.append(stateObserver)

        // Decrypted message handling
        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy else { return }

            Task { @MainActor [weak self] in
                await self?.handleDecryptedMessage(data: data, policy: policy)
            }
        }
        notificationObservers.append(messageObserver)

        // Error handling
        let errorObserver = NotificationCenter.default.addObserver(
            forName: .messageHandlingError,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let error = notification.userInfo?["error"] as? Error else { return }
            Task { @MainActor [weak self] in
                self?.error = error
            }
        }
        notificationObservers.append(errorObserver)
    }

    private func handleConnectionStateChange(_: ArkavoClientState) {
        // Handle connection state changes if needed
    }

    private func handleDecryptedMessage(data: Data, policy _: ArkavoPolicy) async {
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: data)

            // Create thought metadata
            let thoughtMetadata = Thought.Metadata(
                creator: UUID(), // This should be derived from creator public ID
                streamPublicID: thoughtModel.streamPublicID,
                mediaType: thoughtModel.mediaType,
                createdAt: Date(),
                summary: String(data: thoughtModel.content, encoding: .utf8) ?? "",
                contributors: []
            )

            // Create and save thought
            let thought = Thought(
                nano: data, // Store the encrypted data
                metadata: thoughtMetadata
            )

            // Save thought
            _ = try PersistenceController.shared.saveThought(thought)
            try await PersistenceController.shared.saveChanges()

            // Update UI
            thoughts.insert(thought, at: 0)
        } catch {
            self.error = error
        }
    }

    private func handleReceivedThought(_ thought: Thought) {
        thoughts.insert(thought, at: 0)
    }

    deinit {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func streams() -> [Stream] {
        let streams = account.streams.dropFirst(2)
        return Array(streams)
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

    func getPostStream() -> Stream? {
        // Find the stream that's marked as a post stream (has a text source thought)
        account.streams.first { stream in
            stream.source?.metadata.mediaType == .text
        }
    }

    private func loadThoughts() async {
        isLoading = true
        defer { isLoading = false }

        // First try to load from stream
        if let postStream = getPostStream() {
            // Load any cached messages first
            let cacheManager = ViewModelFactory.shared.serviceLocator.resolve() as MessageCacheManager
            let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
            let cachedMessages = cacheManager.getCachedMessages(forStream: postStream.publicID)

            // Process cached messages
            for (messageId, message) in cachedMessages {
                do {
                    try await router.processMessage(message.data, messageId: messageId)
                } catch {
                    print("Failed to process cached message: \(error)")
                }
            }

            // If still no thoughts, load from stream
            if thoughts.isEmpty {
                thoughts = postStream.thoughts.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
            }
        }

        // Wait until we have some thoughts to show
        while thoughts.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    func getCurrentCreator() -> Creator {
        let tier = if account.identityAssuranceLevel == .ial1 || profile.hasHighIdentityAssurance {
            "Verified"
        } else if profile.hasHighEncryption {
            "Premium"
        } else {
            "Basic"
        }

        let bio = [
            profile.blurb,
            !profile.interests.isEmpty ? "Interests: \(profile.interests)" : nil,
            !profile.location.isEmpty ? "📍 \(profile.location)" : nil,
        ]
        .compactMap(\.self)
        .joined(separator: "\n")

        return Creator(
            id: profile.publicID.base58EncodedString,
            name: profile.name,
            imageURL: "",
            latestUpdate: profile.blurb ?? "",
            tier: tier,
            socialLinks: [],
            notificationCount: 0,
            bio: bio
        )
    }

    private func createFlatBuffersPolicy(for thoughtModel: ThoughtServiceModel) throws -> Data {
        var builder = FlatBufferBuilder()

        // Create format info
        let formatVersionString = builder.create(string: "1.0")
        let formatProfileString = builder.create(string: "standard")
        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
            &builder,
            type: .plain,
            versionOffset: formatVersionString,
            profileOffset: formatProfileString
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: thoughtModel.mediaType == .image ? .image : .text,
            dataEncoding: .utf8,
            formatOffset: formatInfo
        )

        // Create rating
        let rating = Arkavo_Rating.createRating(
            &builder,
            violent: .none_,
            sexual: .none_,
            profane: .none_,
            substance: .none_,
            hate: .none_,
            harm: .none_,
            mature: .none_,
            bully: .none_
        )

        // Create purpose
        let purpose = Arkavo_Purpose.createPurpose(
            &builder,
            educational: 0.2,
            entertainment: 0.8,
            news: 0.0,
            promotional: 0.0,
            personal: 0.8,
            opinion: 0.2,
            transactional: 0.0,
            harmful: 0.0,
            confidence: 0.9
        )

        // Create ID and related vectors
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: Data())

        // Create topics vector
        let topics: [UInt32] = [1, 2, 3]
        let topicsVector = builder.createVector(topics)

        // Create metadata root
        let metadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat
        )

        builder.finish(offset: metadata)

        // Verify FlatBuffer
        var buffer = builder.sizedBuffer
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

        // Return the final binary policy data
        return Data(
            bytes: buffer.memory.advanced(by: buffer.reader),
            count: Int(buffer.size)
        )
    }

    func createAndSendThought(content: String) async throws {
        // Create message data
        let messageData = content.data(using: .utf8) ?? Data()

        // Create thought service model
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: Data(), // No specific stream for feed posts
            mediaType: .text,
            content: messageData
        )

        // Create and encrypt policy data
        let policyData = try createFlatBuffersPolicy(for: thoughtModel)
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData
        )

        let thoughtMetadata = Thought.Metadata(
            creator: profile.id,
            streamPublicID: Data(), // No specific stream for feed posts
            mediaType: .text,
            createdAt: Date(),
            summary: content,
            contributors: []
        )

        let thought = Thought(
            id: UUID(),
            nano: nanoData,
            metadata: thoughtMetadata
        )

        // Save thought
        _ = try PersistenceController.shared.saveThought(thought)
        try await PersistenceController.shared.saveChanges()

        if let postStream = getPostStream() {
            postStream.addThought(thought)
            try await PersistenceController.shared.saveChanges()
        }
    }

    func handleSelectedImage(_ image: UIImage) async throws {
        // Convert image to HEIF format with compression
        guard let imageData = image.heifData() else {
            throw ArkavoError.messageError("Failed to convert image to HEIF data")
        }

        // Create thought service model for image
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: Data(), // No specific stream for now
            mediaType: .image,
            content: imageData
        )

        // Create and encrypt policy data
        let policyData = try createFlatBuffersPolicy(for: thoughtModel)
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData
        )

        let thoughtMetadata = Thought.Metadata(
            creator: profile.id,
            streamPublicID: Data(), // No specific stream for feed posts
            mediaType: .image,
            createdAt: Date(),
            summary: "image",
            contributors: []
        )

        // Create thought with encrypted data
        let thought = Thought(
            nano: nanoData,
            metadata: thoughtMetadata
        )

        // Save thought
        _ = try PersistenceController.shared.saveThought(thought)
        try await PersistenceController.shared.saveChanges()

        // Update UI
        await MainActor.run {
            thoughts.insert(thought, at: 0)
        }
    }
}

// MARK: - PostFeedView

struct PostFeedView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel = ViewModelFactory.shared.makePostFeedViewModel()
    @State private var currentIndex = 0

    var body: some View {
        ZStack {
            if sharedState.showCreateView {
                PostCreateView(viewModel: viewModel)
                    .transition(.move(edge: .bottom))
            } else {
                mainFeedView
            }
        }
        .animation(.spring(), value: sharedState.showCreateView)
    }

    private var mainFeedView: some View {
        GeometryReader { geometry in
            ZStack {
                if viewModel.thoughts.isEmpty {
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
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.thoughts) { thought in
                                    ImmersiveThoughtCard(
                                        viewModel: viewModel,
                                        thought: thought,
                                        size: geometry.size
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .onChange(of: viewModel.currentThoughtIndex) { _, newIndex in
                            withAnimation {
                                proxy.scrollTo(viewModel.thoughts[newIndex].id, anchor: .center)
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onEnded { gesture in
                                    let verticalMovement = gesture.translation.height
                                    let swipeThreshold: CGFloat = 50

                                    if abs(verticalMovement) > swipeThreshold {
                                        withAnimation {
                                            if verticalMovement > 0, viewModel.currentThoughtIndex > 0 {
                                                viewModel.currentThoughtIndex -= 1
                                            } else if verticalMovement < 0, viewModel.currentThoughtIndex < viewModel.thoughts.count - 1 {
                                                viewModel.currentThoughtIndex += 1
                                            }
                                        }
                                    }
                                }
                        )
                    }
                }
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - PostCreateView

struct PostCreateView: View {
    @EnvironmentObject var sharedState: SharedState
    @ObservedObject var viewModel: PostFeedViewModel
    @State private var thoughtText = ""
    @State private var selectedImages: [UIImage] = []
    @State private var isShowingImagePicker = false
    @State private var error: Error?
    @State private var showError = false
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .ignoresSafeArea()

                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        if thoughtText.isEmpty {
                            Text("Share your thought...")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        TextEditor(text: $thoughtText)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                    .padding(systemMargin * 2)

                    Spacer()

                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) {
                        Button("Cancel") {
                            sharedState.showCreateView = false
                        }
                        .foregroundColor(.white)
                        .padding()

                        Spacer()

                        Button(action: {
                            isShowingImagePicker = true
                        }) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                        }
                        .padding()

                        Button {
                            Task {
                                do {
                                    try await viewModel.createAndSendThought(content: thoughtText)
                                    sharedState.showCreateView = false
                                } catch {
                                    self.error = error
                                    showError = true
                                }
                            }
                        } label: {
                            Text("Post")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(thoughtText.isEmpty ? Color.gray : Color.blue)
                                .cornerRadius(20)
                        }
                        .disabled(thoughtText.isEmpty)
                        .padding()
                    }
                    .padding(.trailing, systemMargin)
                }

                if !selectedImages.isEmpty {
                    VStack {
                        Spacer()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(selectedImages, id: \.self) { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                            .padding()
                        }
                        .background(Color.black.opacity(0.5))
                    }
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(sourceType: .photoLibrary) { image in
                Task {
                    try await viewModel.handleSelectedImage(image)
                }
            }
        }
        #endif
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "An unknown error occurred")
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - ImmersiveThoughtCard

struct ImmersiveThoughtCard: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: PostFeedViewModel
    let thought: Thought
    let size: CGSize
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                    .frame(width: size.width, height: size.height)

                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        Text(thought.metadata.summary)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(systemMargin * 2)
                    Spacer()
                }
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GroupChatIconList(
                            currentVideo: nil,
                            currentThought: thought,
                            streams: viewModel.streams()
                        )
                        .padding(.trailing, systemMargin)
                        .padding(.bottom, systemMargin * 8)
                    }
                }
                // Contributors section - Positioned at bottom-left
                VStack {
                    Spacer()
                    HStack {
                        ContributorsView(contributors: thought.metadata.contributors)
                            .padding(.horizontal, systemMargin)
                            .padding(.bottom, systemMargin * 8)
                        Spacer()
                    }
                }

                // Chat overlay
                if sharedState.showChatOverlay {
                    ChatOverlay()
                        .onAppear {
                            sharedState.selectedThought = thought
                            sharedState.selectedStream = viewModel.getPostStream()
                        }
                }
            }
        }
    }
}
