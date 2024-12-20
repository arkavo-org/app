import ArkavoSocial
import Foundation
import SwiftUI

// MARK: - Models

struct Contributor: Identifiable {
    let id: String
    let creator: Creator
    let role: String

    static let sampleContributors = [
        Contributor(id: "1", creator: Creator.sampleCreators[0], role: "Director"),
        Contributor(id: "2", creator: Creator.sampleCreators[1], role: "Music"),
        Contributor(id: "3", creator: Creator.sampleCreators[2], role: "Featured"),
        Contributor(id: "4", creator: Creator.sampleCreators[3], role: "Editor"),
    ]
}

struct Video: Identifiable {
    let id: String
    let url: URL
    let contributors: [Contributor]
    let description: String
    var likes: Int
    var comments: Int
    var shares: Int

    var mainCreator: Creator {
        contributors.first?.creator ?? Creator.sampleCreators[0]
    }

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

struct TikTokFeedView: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var viewModel: TikTokFeedViewModel?

    var body: some View {
        Group {
            if let viewModel {
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
                    }
                }
                .ignoresSafeArea()
            } else {
                Text("Loading...")
                    .onAppear {
                        viewModel = ViewModelFactory.shared.makeTikTokFeedViewModel()
                    }
            }
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
                    sharedState.selectedTab = .creators
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
                            sharedState.selectedTab = .creators
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
    let video: Video
    @ObservedObject var viewModel: TikTokFeedViewModel
    let size: CGSize

    @State private var isLiked = false
    @State private var showComments = false
    @State private var likesCount: Int
    @State private var dragOffset = CGSize.zero

    private let swipeThreshold: CGFloat = 50
    // Standard system margin from HIG
    private let systemMargin: CGFloat = 16

    init(video: Video,
         viewModel: TikTokFeedViewModel,
         size: CGSize)
    {
        self.video = video
        self.viewModel = viewModel
        self.size = size
        _likesCount = State(initialValue: video.likes)
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
                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) { // 20pt
                        Spacer()

                        VStack(spacing: systemMargin * 1.25) { // 20pt
                            TikTokServersList(currentVideo: video)
                                .padding(.trailing, systemMargin)
                                .padding(.vertical, systemMargin * 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 24)
                                        .fill(.ultraThinMaterial.opacity(0.4))
                                        .padding(.trailing, systemMargin / 2)
                                )
//                            Button {
//                                withAnimation(.spring()) {
//                                    isLiked.toggle()
//                                    likesCount += isLiked ? 1 : -1
//                                }
//                            } label: {
//                                VStack(spacing: systemMargin * 0.25) { // 4pt
//                                    Image(systemName: isLiked ? "heart.fill" : "heart")
//                                        .font(.system(size: systemMargin * 1.75)) // 28pt
//                                        .foregroundColor(isLiked ? .red : .white)
//                                    Text("\(likesCount)")
//                                        .font(.caption)
//                                        .foregroundColor(.white)
//                                }
//                            }
                            Button {
                                showComments = true
                            } label: {
                                VStack(spacing: systemMargin * 0.25) { // 4pt
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: systemMargin * 1.625)) // 26pt
                                    Text("\(video.comments)")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.trailing, systemMargin + geometry.safeAreaInsets.trailing)
                        .padding(.bottom, systemMargin * 6.25) // 100pt
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
        .sheet(isPresented: $showComments) {
            CommentsView(showComments: $showComments)
        }
    }
}

struct TikTokServersList: View {
    @EnvironmentObject var sharedState: SharedState
    let currentVideo: Video

    var body: some View {
        VStack(spacing: 16) {
            ForEach(sharedState.servers) { server in
                Button {
                    sharedState.selectedVideo = currentVideo
                    sharedState.selectedServer = server
                    sharedState.selectedTab = .communities
                } label: {
                    ServerButton(server: server, isSelected: false) // selectedServer?.id == server.id
                }
            }
        }
    }
}

// MARK: - Server Button Component

struct ServerButton: View {
    let server: Server
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Background and selection indicator
            Circle()
                .fill(isSelected ? Color.blue.opacity(0.2) : Color.black.opacity(0.3))
                .frame(width: 48, height: 48)

            // Server icon
            Image(systemName: server.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? .blue : .white)
                .symbolEffect(.bounce, value: isSelected)

            // Selection ring
            if isSelected {
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .frame(width: 48, height: 48)
            }
        }
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .contentShape(Circle())
    }
}

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
        playerManager.setupPlayer(in: view)
        return view
    }

    func updateUIView(_: UIView, context _: Context) {
//        print("📊 Updating video view: \(url)")
        if isCurrentVideo {
            playerManager.playVideo(url: url)
        }
    }
}

// MARK: - Action Buttons

struct LikeButton: View {
    @Binding var isLiked: Bool
    @Binding var count: Int

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isLiked.toggle()
                count += isLiked ? 1 : -1
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.title)
                    .foregroundColor(isLiked ? .red : .white)
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }
}

struct CommentButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "message")
                    .font(.title)
                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .foregroundColor(.white)
        }
    }
}

struct ActionButton: View {
    let icon: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title)
                Text("\(count)")
                    .font(.caption)
            }
            .foregroundColor(.white)
        }
    }
}

struct CommentsView: View {
    @Binding var showComments: Bool

    var body: some View {
        NavigationView {
            List {
                ForEach(0 ..< 10) { _ in
                    VStack(alignment: .leading) {
                        Text("User")
                            .font(.headline)
                        Text("Comment text goes here")
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showComments = false
                    }
                }
            }
        }
    }
}

@MainActor
class TikTokFeedViewModel: ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published var videos: [Video] = []
    @Published var currentVideoIndex = 0
    @Published var isLoading = false
    @Published var error: Error?
    let playerManager = VideoPlayerManager()

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        videos = videos
        currentVideoIndex = currentVideoIndex
        isLoading = isLoading
        error = error
        loadInitialVideos()
    }

    private func loadInitialVideos() {
        // In a real app, this would fetch from an API
        videos = [
            Video(
                id: "1",
                url: URL(string: "https://example.com/video1.mp4")!,
                contributors: [
                    Contributor(id: "1", creator: Creator.sampleCreators[0], role: "Director"),
                    Contributor(id: "2", creator: Creator.sampleCreators[1], role: "Music"),
                ],
                description: "Collaborative masterpiece 🎨",
                likes: 1500,
                comments: 120,
                shares: 45
            ),
            Video(
                id: "2",
                url: URL(string: "https://example.com/video2.mp4")!,
                contributors: [
                    Contributor(id: "3", creator: Creator.sampleCreators[1], role: "Artist"),
                ],
                description: "Solo music session 🎵",
                likes: 800,
                comments: 65,
                shares: 30
            ),
            Video(
                id: "3",
                url: URL(string: "https://example.com/video3.mp4")!,
                contributors: [
                    Contributor(id: "4", creator: Creator.sampleCreators[2], role: "Chef"),
                    Contributor(id: "5", creator: Creator.sampleCreators[3], role: "Guest Chef"),
                ],
                description: "Cooking collab! 👩‍🍳",
                likes: 2200,
                comments: 180,
                shares: 95
            ),
            Video(
                id: "4",
                url: URL(string: "https://example.com/video4.mp4")!,
                contributors: [
                    Contributor(id: "6", creator: Creator.sampleCreators[3], role: "Developer"),
                ],
                description: "Rotated Text Mode 💻 Rotated Text Mode 💻 Rotated Text Mode 💻 Rotated Text Mode 💻",
                likes: 950,
                comments: 85,
                shares: 40
            ),
        ]

        // Preload the first video
        if let firstVideoUrl = videos.first?.url {
            preloadVideo(url: firstVideoUrl)
        }
    }

    func addNewVideo(from uploadResult: UploadResult, contributors: [Contributor]) {
        let newVideo = Video.from(uploadResult: uploadResult, contributors: contributors)
        videos.insert(newVideo, at: 0)
        currentVideoIndex = 0

        Task {
            try? await playerManager.preloadVideo(url: newVideo.url)
        }
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

        // Simulate API call with delay
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay

                // In a real app, this would be an API call
                let newVideos = [
                    Video(
                        id: UUID().uuidString,
                        url: URL(string: "https://example.com/video4.mp4")!,
                        contributors: [
                            Contributor(id: "6", creator: Creator.sampleCreators[3], role: "Developer"),
                            Contributor(id: "7", creator: Creator.sampleCreators[0], role: "UI Designer"),
                        ],
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

    // MARK: - Video Interactions

    func handleLike(for _: String) {
        // Handle like interaction
        // In a real app, this would call an API
    }

    func handleComment(for _: String, comment _: String) {
        // Handle comment interaction
        // In a real app, this would call an API
    }

    func handleShare(for _: String) {
        // Handle share interaction
        // In a real app, this would call an API
    }

    func handleVideoView(for _: String) {
        // Track video view
        // In a real app, this would call analytics service
    }
}
