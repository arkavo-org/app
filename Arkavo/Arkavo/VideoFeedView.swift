import ArkavoSocial
import AVFoundation
import Foundation
import SwiftData
import SwiftUI

// MARK: - Models

struct Video: Identifiable {
    let id: String
    let url: URL
    let contributors: [Contributor]
    let description: String

    static func from(uploadResult: UploadResult, contributors: [Contributor]) -> Video {
        Video(
            id: uploadResult.id,
            url: URL(string: uploadResult.playbackURL)!,
            contributors: contributors,
            description: "Just recorded!"
        )
    }

    static func from(thought: Thought) -> Video? {
        let url = URL(string: "nano://\(thought.publicID.base58EncodedString)/")!
        return Video(
            id: thought.id.uuidString,
            url: url,
            contributors: thought.metadata.contributors,
            description: thought.metadata.summary
        )
    }
}

// MARK: - Main View

struct VideoContentView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var feedViewModel: VideoFeedViewModel

    init() {
        // Initialize with an empty view model, it will be properly configured in onAppear
        _feedViewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeVideoFeedViewModel())
    }

    var body: some View {
        ZStack {
            if sharedState.showCreateView {
                VideoCreateView(feedViewModel: feedViewModel)
            } else {
                VideoFeedView()
            }
        }
        .animation(.spring, value: sharedState.showCreateView)
    }
}

struct VideoFeedView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var viewModel: VideoFeedViewModel

    init() {
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeVideoFeedViewModel())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main feed content
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.videos) { video in
                                VideoPlayerView(
                                    video: video,
                                    viewModel: viewModel,
                                    size: geometry.size
                                )
                                .id(video.id)
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .onChange(of: viewModel.currentVideoIndex) { _, newIndex in
                        withAnimation {
                            proxy.scrollTo(viewModel.videos[newIndex].id, anchor: .center)
                        }
                    }
                }

                // Loading state
                if viewModel.videos.isEmpty {
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

                // Reusable chat overlay
                if sharedState.showChatOverlay {
                    ChatOverlay()
                }
            }
        }
        .ignoresSafeArea()
        .task {
            viewModel.cleanupOldCacheFiles()
        }
    }
}

struct ContributorsView: View {
    @EnvironmentObject var sharedState: SharedState
    let contributors: [Contributor]
    @State private var showAllContributors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Main creator
            if let mainContributor = contributors.first {
                Button {
                    sharedState.selectedCreator = mainContributor.creator
                    // FIXME: creators
                    sharedState.selectedTab = .profile
                    sharedState.showCreateView = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                            .foregroundColor(.blue)

                        VStack(alignment: .leading) {
                            Text(mainContributor.creator.name)
                                .font(.headline)

                            Text(mainContributor.role)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // Other contributors (collapsed by default)
            if contributors.count > 1 {
                if showAllContributors {
                    ForEach(contributors.dropFirst()) { contributor in
                        Button {
                            sharedState.selectedCreator = contributor.creator
                            // FIXME: creators
                            sharedState.selectedTab = .profile
                            sharedState.showCreateView = false
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .clipShape(Circle())
                                    .foregroundColor(.blue.opacity(0.7))
                                VStack(alignment: .leading) {
                                    Text(contributor.creator.name)
                                        .font(.subheadline)

                                    Text(contributor.role)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }
                } else {
                    Button {
                        withAnimation(.spring()) {
                            showAllContributors.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Contributors")
                                .font(.caption)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .rotationEffect(.degrees(showAllContributors ? 90 : 0))
                        }
                        .foregroundColor(.gray)
                    }
                }
            }
        }
        .foregroundColor(.white)
    }
}

struct VideoPlayerView: View {
    @EnvironmentObject var sharedState: SharedState
    @ObservedObject var viewModel: VideoFeedViewModel
    @State private var dragOffset = CGSize.zero
    let video: Video
    let size: CGSize
    private let swipeThreshold: CGFloat = 50
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16
    private let servers: [Stream]

    init(video: Video,
         viewModel: VideoFeedViewModel,
         size: CGSize)
    {
        self.video = video
        self.viewModel = viewModel
        self.size = size
        servers = viewModel.servers()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                PlayerContainerView(
                    url: video.url,
                    playerManager: viewModel.playerManager,
                    size: size,
                    isCurrentVideo: viewModel.videos[viewModel.currentVideoIndex].id == video.id
                )

                // Content overlay
                HStack(spacing: 0) {
                    // Left side - Vertically centered description text
                    ZStack(alignment: .center) {
                        GeometryReader { metrics in
                            VerticalText(text: video.description)
                                .frame(width: metrics.size.height, height: systemMargin)
                                .rotationEffect(.degrees(-90), anchor: .center)
                                .position(
                                    x: systemMargin + geometry.safeAreaInsets.leading,
                                    y: metrics.size.height / 2
                                )
                        }
                    }
                    .frame(width: systemMargin * 2.75) // 44pt for touch target

                    Spacer()

                    // Right side - Action buttons
                    VStack(alignment: .trailing) {
                        Spacer()

                        GroupChatIconList(
                            currentVideo: video,
                            currentThought: nil,
                            servers: servers
                        )
                        .padding(.trailing, systemMargin + geometry.safeAreaInsets.trailing)
                        .padding(.bottom, systemMargin * 6.25)
                    }
                }

                // Contributors section - Positioned at bottom
                VStack {
                    Spacer()
                    HStack {
                        ContributorsView(
                            contributors: video.contributors
                        )
                        .padding(.horizontal, systemMargin)
                        .padding(.bottom, systemMargin * 8)
                        Spacer()
                    }
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        dragOffset = gesture.translation
                    }
                    .onEnded { gesture in
                        let verticalMovement = gesture.translation.height
                        if abs(verticalMovement) > swipeThreshold {
                            if verticalMovement > 0, viewModel.currentVideoIndex > 0 {
                                withAnimation {
                                    viewModel.currentVideoIndex -= 1
                                }
                            } else if verticalMovement < 0, viewModel.currentVideoIndex < viewModel.videos.count - 1 {
                                withAnimation {
                                    viewModel.currentVideoIndex += 1
                                }
                            }
                        }
                        dragOffset = .zero
                    }
            )
        }
        .frame(width: size.width, height: size.height)
        .ignoresSafeArea()
    }
}

struct GroupChatIconList: View {
    @EnvironmentObject var sharedState: SharedState
    let currentVideo: Video?
    let currentThought: Thought?
    let servers: [Stream]
    @State private var isCollapsed = true
    @State private var showMenuButton = true

    // Timer to auto-collapse after 4 seconds
    let collapseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .trailing) {
            if !isCollapsed {
                // Expanded view with all buttons
                VStack(spacing: 20) { // Even spacing between all items
                    ForEach(servers) { server in
                        Button {
                            sharedState.selectedVideo = currentVideo
                            sharedState.selectedThought = currentThought
                            sharedState.selectedStream = server
                            sharedState.selectedTab = .communities
                        } label: {
                            Image(systemName: iconForStream(server))
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                    }

                    // Comment button integrated into the list
                    Button {
                        sharedState.showChatOverlay = true
                        withAnimation(.spring()) {
                            isCollapsed = true
                            showMenuButton = true
                        }
                    } label: {
                        Image(systemName: "bubble.right")
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.vertical, 16)
                .frame(width: 60) // Fixed width container
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .transition(AnyTransition.asymmetric(
                    insertion: .scale(scale: 0.1, anchor: .trailing)
                        .combined(with: .opacity),
                    removal: .scale(scale: 0.1, anchor: .trailing)
                        .combined(with: .opacity)
                ))
            }

            // Collapsed state
            if showMenuButton, isCollapsed {
                Button {
                    expandMenu()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.title3)
                    }
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onReceive(collapseTimer) { _ in
            if !isCollapsed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring()) {
                        isCollapsed = true
                        showMenuButton = true
                    }
                }
            }
        }
    }

    private func expandMenu() {
        withAnimation(.easeOut(duration: 0.1)) {
            showMenuButton = false
        }

        withAnimation(.spring(response: 0.1, dampingFraction: 0.8)) {
            isCollapsed = false
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

// MARK: - Server Button Component

struct VerticalText: View {
    let text: String
    let fontSize: CGFloat = 16

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .foregroundColor(.white)
            .fontWeight(.medium)
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Player Container View

struct PlayerContainerView: UIViewRepresentable {
    let url: URL
    let playerManager: VideoPlayerManager
    let size: CGSize
    let isCurrentVideo: Bool

    func makeUIView(context _: Context) -> UIView {
//        print("📊 Making video view: \(url)")
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .black
        // Configure for full screen video
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        playerManager.setupPlayer(in: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
//        print("📊 Updating video view: \(url)")
        // Ensure view fills its parent
        uiView.frame = CGRect(origin: .zero, size: size)
        if isCurrentVideo {
            playerManager.playVideo(url: url)
        }
    }
}

enum VideoStreamError: Error {
    case noVideoStream
    case invalidStream
}

@MainActor
final class VideoFeedViewModel: ObservableObject, VideoFeedUpdating {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var videos: [Video] = []
    @Published var currentVideoIndex = 0
    @Published var isLoading = false
    @Published var error: Error?
    @Published var connectionState: ArkavoClientState = .disconnected
    let playerManager = VideoPlayerManager()
    private var notificationObservers: [NSObjectProtocol] = []

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        setupNotifications()
        // Load initial videos
        Task {
            await loadVideos()
        }
    }

    private func setupNotifications() {
        print("VideoFeedViewModel: setupNotifications")
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
                self?.connectionState = state
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

    private func loadVideos() async {
        isLoading = true
        defer { isLoading = false }

        // First try to load from stream
        if let videoStream = try? await getOrCreateVideoStream() {
            // Load any cached messages first
            let cacheManager = ViewModelFactory.shared.serviceLocator.resolve() as MessageCacheManager
            let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
            let cachedMessages = cacheManager.getCachedMessages(forStream: videoStream.publicID)

            // Process cached messages
            for (messageId, message) in cachedMessages {
                do {
                    try await router.processMessage(message.data, messageId: messageId)
                } catch {
                    print("Failed to process cached message: \(error)")
                }
            }

            // If still no videos, load from stream's thoughts
            if videos.isEmpty {
                for thought in videoStream.thoughts {
                    // Convert thought to Video
                    if let video = Video.from(thought: thought) {
                        videos.append(video)
                    }
                }
            }
            // Wait for a limited time if we still have no videos
            let maxAttempts = 10 // 1 second total wait
            var attempts = 0
            while videos.isEmpty, attempts < maxAttempts {
                try? await Task.sleep(nanoseconds: 100_000_000)
                attempts += 1
            }
        }
    }

    deinit {
        // Clean up observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleDecryptedMessage(data: Data, policy: ArkavoPolicy) async {
        do {
            print("\nHandling decrypted video message:")
            print("- Data size: \(data.count)")
            print("- Policy type: \(policy.type)")

            // Verify this is a video message based on policy
            guard policy.type == .videoFrame else {
                print("❌ Incorrect policy type")
                return
            }

            // Create a temporary file URL in the cache directory for the video data
            let fileManager = FileManager.default
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let videoFileName = UUID().uuidString + ".mp4" // Or appropriate extension
            let videoFileURL = cacheDir.appendingPathComponent(videoFileName)

            // Write the video data to the cache file
            try data.write(to: videoFileURL)
            print("✅ Wrote video data to cache: \(videoFileURL)")

            // Analyze the video file after writing
            let asset = AVURLAsset(url: videoFileURL)
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let naturalSize = try await videoTrack.load(.naturalSize)
                let transform = try await videoTrack.load(.preferredTransform)
                let videoAngle = atan2(transform.b, transform.a)

                print("\n📼 Decrypted Video Analysis:")
                print("- File size: \(data.count) bytes")
                print("- Natural size: \(naturalSize)")
                print("- Aspect ratio: \(naturalSize.width / naturalSize.height)")
                print("- Transform angle: \(videoAngle * 180 / .pi)°")
                print("- Transform matrix: \(transform)")
            }

            // Create new video object using the cached file URL
            // FIXME: use ArkavoPolicy.Metadata
            let video = Video(
                id: UUID().uuidString,
                url: videoFileURL,
                contributors: [], // Add contributors if available in policy
                description: policy.type.rawValue
            )

            // Update UI
            await MainActor.run {
                print("Adding video to feed")
                videos.insert(video, at: 0)
                if videos.count == 1 {
                    print("Preloading first video")
                    preloadVideo(url: video.url)
                }
            }

        } catch {
            print("❌ Error processing video: \(error)")
            await MainActor.run {
                self.error = error
            }
        }
    }

    func servers() -> [Stream] {
        let servers = account.streams
        return servers
    }

    func cleanupOldCacheFiles() {
        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }

        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )

            // Keep only the 20 most recent videos
            let oldFiles = cacheContents
                .filter { $0.pathExtension == "mp4" }
                .sorted { url1, url2 -> Bool in
                    let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1! > date2!
                }
                .dropFirst(20)

            for fileURL in oldFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Error cleaning cache: \(error)")
        }
    }

    func addNewVideo(from uploadResult: UploadResult, contributors: [Contributor]) {
        Task {
            do {
                // Get or create video stream
                let videoStream = try await getOrCreateVideoStream()

                // Create new video
                let newVideo = Video.from(uploadResult: uploadResult, contributors: contributors)

                // Create thought for the video
                let metadata = Thought.Metadata(
                    creator: profile.id,
                    streamPublicID: videoStream.publicID,
                    mediaType: .video,
                    createdAt: Date(),
                    summary: newVideo.description,
                    contributors: contributors
                )

                // Convert video URL to data for storage
                let videoData = newVideo.url.absoluteString.data(using: .utf8) ?? Data()
                let thought = Thought(nano: videoData, metadata: metadata)

                // Add thought to stream
                videoStream.thoughts.append(thought)

                // Save changes to persistence
                try await PersistenceController.shared.saveChanges()

                // Update UI
                await MainActor.run {
                    videos.insert(newVideo, at: 0)
                    currentVideoIndex = 0
                }

                // Preload video
                try? await playerManager.preloadVideo(url: newVideo.url)

            } catch VideoStreamError.noVideoStream {
                print("No video stream exists and couldn't create one")
                self.error = VideoStreamError.noVideoStream
            } catch {
                print("Error adding video: \(error)")
                self.error = error
            }
        }
    }

    func getOrCreateVideoStream() async throws -> Stream {
        // First check for existing video stream
        if let existingStream = account.streams.first(where: { stream in
            stream.source?.metadata.mediaType == .video
        }) {
            return existingStream
        }
        throw VideoStreamError.noVideoStream
    }

    func preloadVideo(url: URL) {
        Task {
            do {
                try await playerManager.preloadVideo(url: url)
            } catch {
                self.error = error
            }
        }
    }
}

@MainActor
protocol VideoFeedUpdating: AnyObject {
    func addNewVideo(from result: UploadResult, contributors: [Contributor])
    func preloadVideo(url: URL)
}

// Extension to provide default implementation
@MainActor
extension VideoFeedUpdating {
    func preloadVideo(url _: URL) {
        // Optional default implementation
    }
}
