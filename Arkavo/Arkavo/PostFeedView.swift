import ArkavoSocial
import CryptoKit
import FlatBuffers
import Foundation
import OpenTDFKit
import SwiftUI
import UIKit

// MARK: - Model

struct Post: Identifiable, Hashable {
    let id: String
    let streamPublicID: Data // Thought.publicID
    let url: URL? // Optional since not all posts may have images
    let contributors: [Contributor]
    let description: String
    let createdAt: Date
    let mediaType: MediaType // To distinguish between text and image posts
    let creatorPublicID: Data
    let thought: Thought

    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Implement Equatable
    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - View Models

@MainActor
class PostFeedViewModel: ViewModel, ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    private var notificationObservers: [Any] = []
    @Published var posts: [Post] = []
    @Published var thoughts: [Thought] = []
    @Published var currentThoughtIndex = 0
    @Published var isLoading = false
    @Published var error: Error?
    @Published var postQueue = PostMessageQueue()
    @Published var hasAttemptedLoad = false

    required init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        setupNotifications()
        Task {
            await loadThoughts()
        }
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
            queue: nil,
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
            queue: nil,
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data,
                  let header = notification.userInfo?["header"] as? Header else { return }

            Task { @MainActor [weak self] in
                await self?.handleDecryptedMessage(data: data, header: header)
            }
        }
        notificationObservers.append(messageObserver)

        // Error handling
        let errorObserver = NotificationCenter.default.addObserver(
            forName: .messageHandlingError,
            object: nil,
            queue: nil,
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

    private func handleDecryptedMessage(data: Data, header: Header) async {
        do {
            let thoughtModel = try ThoughtServiceModel.deserialize(from: data)
            guard thoughtModel.mediaType == .post else {
//                print("❌ Incorrect mediaType received \(thoughtModel.mediaType)")
                return
            }
            if let bodyData = header.policy.body?.body {
                // Parse metadata but don't use it anymore (now using new Thought.from API)
                _ = try ArkavoPolicy.parseMetadata(from: bodyData)

                // Create thought
                let thought = try Thought.from(thoughtModel)
                // Create post
                let post = Post(
                    id: thought.id.uuidString,
                    streamPublicID: thought.metadata.streamPublicID,
                    url: nil,
                    contributors: thought.metadata.contributors,
                    description: String(data: thoughtModel.content, encoding: .utf8) ?? "",
                    createdAt: thought.metadata.createdAt,
                    mediaType: thought.metadata.mediaType,
                    creatorPublicID: thought.metadata.creatorPublicID,
                    thought: thought,
                )
//                print("post: \(post) stream: \(post.streamPublicID.base58EncodedString)")
                await MainActor.run {
                    thoughts.insert(thought, at: 0)
                    posts.insert(post, at: 0)
                    postQueue.enqueuePost(thought)
                }
            }
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
        let streams = account.streams.dropFirst(2).filter { $0.source == nil }
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

    func getPostStream() -> Stream {
        // Find the stream that's marked as a post stream (has a text source thought)
        account.streams.first { stream in
            stream.source?.metadata.mediaType == .post
        }!
    }

    private func loadThoughts() async {
        isLoading = true

        // First try to load from stream
        let postStream = getPostStream()

        // Load any cached messages first
        let queueManager = ViewModelFactory.shared.serviceLocator.resolve() as MessageQueueManager
        let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter

        // Try to load multiple messages
        for _ in 0 ..< 10 { // Load up to 10 messages initially
            if let (messageId, message) = queueManager.getNextMessage(
                ofType: 0x05,
                forStream: postStream.publicID,
            ) {
                do {
                    try await router.processMessage(message.data, messageId: messageId)
                    queueManager.removeMessage(messageId)
                } catch {
                    print("Failed to process cached message: \(error)")
                }
            } else {
                break // No more messages available
            }
        }

        // If still no thoughts, load from account post-stream thoughts
        if thoughts.isEmpty {
            let relevantThoughts = postStream.thoughts
                .filter { $0.metadata.mediaType == .post }
                .suffix(10) // Load up to 10 post

            print("PostFeedViewModel: Loading \(relevantThoughts.count) thoughts from post stream")

            for thought in relevantThoughts {
                try? await client.sendMessage(thought.nano)
                try? await router.processMessage(thought.nano, messageId: thought.id)
                postQueue.enqueuePost(thought)
            }
        }

        print("PostFeedViewModel: loadThoughts completed. Posts count: \(posts.count)")

        // Wait a bit for notifications to process
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Now we can consider loading complete
        isLoading = false
        hasAttemptedLoad = true
        print("PostFeedViewModel: After delay. Posts count: \(posts.count)")
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
            profileOffset: formatProfileString,
        )

        // Create content format
        let contentFormat = Arkavo_ContentFormat.createContentFormat(
            &builder,
            mediaType: thoughtModel.mediaType == .image ? .image : .text,
            dataEncoding: .utf8,
            formatOffset: formatInfo,
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
            bully: .none_,
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
            confidence: 0.9,
        )

        // Create ID and related vectors
        let idVector = builder.createVector(bytes: thoughtModel.publicID)
        let relatedVector = builder.createVector(bytes: thoughtModel.streamPublicID)
        let creatorVector = builder.createVector(bytes: thoughtModel.creatorPublicID)

        // Create topics vector
        let topics: [UInt32] = [1, 2, 3]
        let topicsVector = builder.createVector(topics)

        // Create metadata root
        let metadata = Arkavo_Metadata.createMetadata(
            &builder,
            created: Int64(Date().timeIntervalSince1970),
            idVectorOffset: idVector,
            relatedVectorOffset: relatedVector,
            creatorVectorOffset: creatorVector,
            ratingOffset: rating,
            purposeOffset: purpose,
            topicsVectorOffset: topicsVector,
            contentOffset: contentFormat,
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
            count: Int(buffer.size),
        )
    }

    func sendPost(content: String) async throws {
        print("PostFeedViewModel: sendPost")
        // Create message data
        let messageData = content.data(using: .utf8) ?? Data()

        let postStream = getPostStream()

        // Create thought service model
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: postStream.publicID,
            mediaType: .post,
            content: messageData,
        )

        // Create and encrypt policy data
        let policyData = try createFlatBuffersPolicy(for: thoughtModel)
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData,
        )
        let contributors: [Contributor] = [Contributor(profilePublicID: profile.publicID, role: "creator")]
        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: postStream.publicID,
            mediaType: .post,
            createdAt: Date(),
            contributors: contributors,
        )

        let thought = Thought(
            id: UUID(),
            nano: nanoData,
            metadata: thoughtMetadata,
        )

        // Save thought
        _ = try await PersistenceController.shared.saveThought(thought)
        try await PersistenceController.shared.saveChanges()
        // Create new stream For post chat
        let stream = Stream(
            publicID: thought.publicID,
            creatorPublicID: profile.publicID,
            profile: Profile(name: thought.publicID.base58EncodedString),
            policies: Policies(
                admission: .open,
                interaction: .open,
                age: .forAll,
            ),
        )
        stream.source = thought
        _ = try PersistenceController.shared.saveStream(stream)
        postStream.addThought(thought)
        try await PersistenceController.shared.saveChanges()
    }

    func handleSelectedImage(_ image: UIImage) async throws {
        // Convert image to HEIF format with compression
        guard let imageData = image.heifData() else {
            throw ArkavoError.messageError("Failed to convert image to HEIF data")
        }

        let postStream = getPostStream()

        // Create thought service model for image
        let thoughtModel = ThoughtServiceModel(
            creatorPublicID: profile.publicID,
            streamPublicID: postStream.publicID,
            mediaType: .image,
            content: imageData,
        )

        // Create and encrypt policy data
        let policyData = try createFlatBuffersPolicy(for: thoughtModel)
        let payload = try thoughtModel.serialize()

        // Encrypt and send via client
        let nanoData = try await client.encryptAndSendPayload(
            payload: payload,
            policyData: policyData,
        )

        let thoughtMetadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: postStream.publicID,
            mediaType: .image,
            createdAt: Date(),
            contributors: [],
        )

        // Create thought with encrypted data
        let thought = Thought(
            nano: nanoData,
            metadata: thoughtMetadata,
        )

        // Save thought
        _ = try await PersistenceController.shared.saveThought(thought)
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
    @StateObject private var viewModel: PostFeedViewModel = ViewModelFactory.shared.makeViewModel()

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
                if !viewModel.hasAttemptedLoad {
                    // Show loading indicator while initial load hasn't completed
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.posts.isEmpty {
                    WaveEmptyStateView()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.posts) { post in
                                    ImmersiveThoughtCard(
                                        viewModel: viewModel,
                                        post: post,
                                        size: geometry.size,
                                    )
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .onChange(of: viewModel.currentThoughtIndex) { _, newIndex in
                            withAnimation {
                                proxy.scrollTo(viewModel.posts[newIndex].id, anchor: .center)
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
                                            } else if verticalMovement < 0, viewModel.currentThoughtIndex < viewModel.posts.count - 1 {
                                                viewModel.currentThoughtIndex += 1
                                            }
                                        }
                                    }
                                },
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
                                    try await viewModel.sendPost(content: thoughtText)
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
    let post: Post
    let size: CGSize
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                    .frame(width: size.width, height: size.height)

                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        Text(post.description)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(systemMargin * 2)
                    Spacer()
                }

                // Group chat icons (you may need to adjust this to work with post instead of thought)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        GroupChatIconList(
                            currentVideo: nil,
                            currentThought: post.thought,
                            streams: viewModel.streams(),
                            onBroadcast: {
                                Task {
                                    try? await viewModel.client.sendMessage(post.thought.nano)
                                }
                            },
                        )
                        .padding(.trailing, systemMargin)
                        .padding(.bottom, systemMargin * 8)
                    }
                }

                // Contributors section
                VStack {
                    Spacer()
                    HStack {
                        ContributorsView(
                            client: viewModel.client,
                            contributors: post.contributors,
                        )
                        .padding(.horizontal, systemMargin)
                        .padding(.bottom, systemMargin * 8)
                        Spacer()
                    }
                }

                if sharedState.showChatOverlay {
                    ChatOverlay(streamPublicID: post.streamPublicID)
                        .onAppear {
                            sharedState.selectedThought = post.thought
                            sharedState.selectedStreamPublicID = post.streamPublicID
                        }
                }
            }
        }
    }
}

// MARK: - PostFeedViewModel Extension

extension PostFeedViewModel {
    @MainActor
    func handleSwipe(_ direction: SwipeDirection) async {
//        print("Handling swipe: \(direction)")
        switch direction {
        case .up:
            if currentThoughtIndex < thoughts.count - 1 {
                print("Moving to next post")
                currentThoughtIndex += 1
                // Process state change
                postQueue.moveToNext()
                // Check if we need more posts
                if postQueue.needsMorePosts {
                    await loadThoughts()
                }
                await prepareNextPost()
            }
        case .down:
            if currentThoughtIndex > 0 {
                print("Moving to previous post")
                currentThoughtIndex -= 1
                try? postQueue.moveToPrevious()
                await prepareNextPost()
            }
        }
    }

    @MainActor
    func prepareNextPost() async {
        // Prepare the next post if available
        if postQueue.stats.pending > 1 {
            let nextIndex = postQueue.stats.current + 1
            if nextIndex < postQueue.posts.count {
                // Any preparation needed for the next post can go here
            }
        }
    }

    enum SwipeDirection {
        case up
        case down
    }
}

@MainActor
final class PostMessageQueue {
    // MARK: - Constants

    private enum Constants {
        static let maxBufferAhead = 10 // Number of posts to keep ready
        static let maxBufferBehind = 5 // Number of viewed posts to keep
    }

    // MARK: - Types

    enum PostQueueError: Error {
        case invalidIndex
        case postNotFound
        case bufferEmpty
    }

    // MARK: - Properties

    private var viewedPosts: [Thought] = [] // Posts already viewed, limited to maxBufferBehind
    private var pendingPosts: [Thought] = [] // Posts ready to view, limited to maxBufferAhead
    private var currentIndex: Int = 0 // Index in the combined post array

    var posts: [Thought] { viewedPosts + pendingPosts }
    var needsMorePosts: Bool { pendingPosts.count < Constants.maxBufferAhead }

    // MARK: - Public Methods

    /// Add a new post to the pending queue
    func enqueuePost(_ post: Thought) {
        // Only add if we haven't hit the buffer limit
        if pendingPosts.count < Constants.maxBufferAhead {
            pendingPosts.append(post)
        }
    }

    /// Get the current post
    func currentPost() throws -> Thought {
        guard !posts.isEmpty else { throw PostQueueError.bufferEmpty }
        guard currentIndex >= 0, currentIndex < posts.count else {
            throw PostQueueError.invalidIndex
        }
        return posts[currentIndex]
    }

    /// Move to next post and maintain buffers
    func moveToNext() {
        guard currentIndex + 1 < posts.count else {
            return
        }

        // If moving forward, move current post to viewed
        if let currentPost = try? currentPost() {
            viewedPosts.append(currentPost)
            pendingPosts.removeFirst()

            // Maintain viewed buffer size
            while viewedPosts.count > Constants.maxBufferBehind {
                viewedPosts.removeFirst()
            }
        }

        currentIndex = min(currentIndex + 1, posts.count - 1)
    }

    /// Move to previous post
    func moveToPrevious() throws {
        guard currentIndex > 0 else {
            throw PostQueueError.invalidIndex
        }

        currentIndex = max(0, currentIndex - 1)
    }

    /// Clear all posts
    func clear() {
        viewedPosts.removeAll()
        pendingPosts.removeAll()
        currentIndex = 0
    }

    /// Get current queue stats
    var stats: (viewed: Int, pending: Int, current: Int) {
        (viewedPosts.count, pendingPosts.count, currentIndex)
    }
}
