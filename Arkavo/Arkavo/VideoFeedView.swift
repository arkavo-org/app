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
    var likes: Int
    var comments: Int
    var shares: Int

    static func from(uploadResult: UploadResult, contributors: [Contributor]) -> Video {
        Video(
            id: uploadResult.id,
            url: URL(string: uploadResult.playbackURL)!,
            contributors: contributors,
            description: "Just recorded!",
            likes: 0,
            comments: 0,
            shares: 0
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
                VideoFeedView(viewModel: feedViewModel)
            }
        }
        .animation(.spring, value: sharedState.showCreateView)
    }
}

struct VideoFeedView: View {
    @EnvironmentObject var sharedState: SharedState
    @ObservedObject var viewModel: VideoFeedViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
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
    @State private var showChat = false
    @State private var dragOffset = CGSize.zero
    let video: Video
    let size: CGSize
    private let swipeThreshold: CGFloat = 50
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16

    init(video: Video,
         viewModel: VideoFeedViewModel,
         size: CGSize)
    {
        self.video = video
        self.viewModel = viewModel
        self.size = size
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
                            servers: viewModel.servers(),
                            comments: video.comments,
                            showChat: $showChat
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
        .sheet(isPresented: $showChat) {
            if let stream = viewModel.account.streams.first {
                let viewModel = ViewModelFactory.shared.makeChatViewModel(stream: stream)
                ChatView(
                    viewModel: viewModel
                )
            }
        }
    }
}

struct GroupChatIconList: View {
    @EnvironmentObject var sharedState: SharedState
    let currentVideo: Video?
    let currentThought: Thought?
    let servers: [Server]
    let comments: Int
    @State private var isCollapsed = true
    @State private var showMenuButton = true
    @Binding var showChat: Bool

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
                            sharedState.selectedServer = server
                            sharedState.selectedTab = .communities
                        } label: {
                            Image(systemName: server.icon)
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                    }

                    // Comment button integrated into the list
                    Button {
                        showChat = true
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
    }

    private func setupNotifications() {
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
            let video = Video(
                id: UUID().uuidString,
                url: videoFileURL,
                contributors: [], // Add contributors if available in policy
                description: "New video",
                likes: 0,
                comments: 0,
                shares: 0
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

    func loadMoreVideosIfNeeded(currentIndex: Int) {
        // Load more videos when user reaches near the end
        if currentIndex >= videos.count - 2 {
            loadMoreVideos()
        }
    }

    private func loadMoreVideos() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

                // In a real app, this would be an API call
                let newVideos = [
                    Video(
                        id: UUID().uuidString,
                        url: URL(string: "https://example.com/video4.mp4")!,
                        contributors: [],
                        description: "Tech tutorial collab 💻",
                        likes: 950,
                        comments: 85,
                        shares: 40
                    ),
                ]

                await MainActor.run {
                    videos.append(contentsOf: newVideos)
                    isLoading = false
                }

                // Preload new videos
                for video in newVideos {
                    preloadVideo(url: video.url)
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isLoading = false
                }
            }
        }
    }

    func servers() -> [Server] {
        let allStreams = account.streams
        let streams = allStreams.filter { stream in
            stream.isGroupChatStream
        }
        let servers = streams.map { stream in
            Server(
                id: stream.id.uuidString,
                name: stream.profile.name,
                imageURL: nil,
                icon: iconForStream(stream),
                unreadCount: stream.thoughts.count,
                hasNotification: !stream.thoughts.isEmpty,
                description: "description",
                policies: StreamPolicies(
                    agePolicy: .onlyKids,
                    admissionPolicy: .open,
                    interactionPolicy: .open
                )
            )
        }
        return servers
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
