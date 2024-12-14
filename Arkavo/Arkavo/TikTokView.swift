import AVFoundation
import SwiftUI

// MARK: - Models

struct Video: Identifiable {
    let id: String
    let url: URL
    let creatorName: String
    let description: String
    var likes: Int
    var comments: Int
    var shares: Int

    static func from(uploadResult: UploadResult, creatorName: String = "me") -> Video {
        Video(
            id: uploadResult.id,
            url: URL(string: uploadResult.playbackURL)!,
            creatorName: creatorName,
            description: "Just recorded!",
            likes: 0,
            comments: 0,
            shares: 0
        )
    }
}

// MARK: - Main View

struct TikTokFeedView: View {
    @ObservedObject var viewModel: TikTokFeedViewModel
    @Binding var showRecordingView: Bool

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
                                    size: geometry.size,
                                    showRecordingView: $showRecordingView
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
    }
}

// MARK: - ViewModel

@MainActor
class TikTokFeedViewModel: ObservableObject {
    @Published var videos: [Video]
    @Published var currentVideoIndex = 0

    let playerManager = VideoPlayerManager()

    init() {
        // Initialize with sample videos
        videos = [
            Video(
                id: "1",
                url: URL(string: "https://example.com/video1.mp4")!,
                creatorName: "creator1",
                description: "First video",
                likes: 100,
                comments: 50,
                shares: 25
            ),
            Video(
                id: "2",
                url: URL(string: "https://example.com/video1.mp4")!,
                creatorName: "2222",
                description: "2222 video",
                likes: 100,
                comments: 50,
                shares: 25
            ),
            Video(
                id: "3",
                url: URL(string: "https://example.com/video1.mp4")!,
                creatorName: "3333",
                description: "3333 video",
                likes: 100,
                comments: 50,
                shares: 25
            ),
        ]
    }

    func addNewVideo(from uploadResult: UploadResult) {
        let newVideo = Video.from(uploadResult: uploadResult)
        videos.insert(newVideo, at: 0)
        currentVideoIndex = 0
        print("📊 New video added: \(newVideo)")
        Task {
            try? await playerManager.preloadVideo(url: newVideo.url)
        }
    }

    func preloadVideo(url _: URL) {}
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let video: Video
    @ObservedObject var viewModel: TikTokFeedViewModel
    @Binding var showRecordingView: Bool
    let size: CGSize

    @State private var isLiked = false
    @State private var showComments = false
    @State private var likesCount: Int

    init(video: Video, viewModel: TikTokFeedViewModel, size: CGSize, showRecordingView: Binding<Bool>) {
        self.video = video
        self.viewModel = viewModel
        self.size = size
        _showRecordingView = showRecordingView
        _likesCount = State(initialValue: video.likes)
    }

    var body: some View {
        ZStack {
            // Video player
            PlayerContainerView(
                url: video.url,
                playerManager: viewModel.playerManager,
                size: size,
                isCurrentVideo: viewModel.videos[viewModel.currentVideoIndex].id == video.id
            )

            // Overlay controls
            VStack {
                Spacer()
                HStack {
                    // Video info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("@\(video.creatorName)")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(video.description)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()

                    Spacer()

                    // Action buttons
                    VStack(spacing: 20) {
                        // Create button
                        Button {
                            showRecordingView = true
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "camera.circle.fill")
                                    .font(.title)
                                Text("Create")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        }

                        LikeButton(isLiked: $isLiked, count: $likesCount)

                        CommentButton(count: video.comments) {
                            showComments = true
                        }
                    }
                    .padding(.trailing)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .onAppear {
            viewModel.preloadVideo(url: video.url)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    handleSwipe(translation: value.translation)
                }
        )
        .sheet(isPresented: $showComments) {
            CommentsView(showComments: $showComments)
        }
    }

    private func handleSwipe(translation: CGSize) {
        let threshold: CGFloat = 50
        if abs(translation.height) > threshold {
            if translation.height > 0, viewModel.currentVideoIndex > 0 {
                viewModel.currentVideoIndex -= 1
            } else if translation.height < 0, viewModel.currentVideoIndex < viewModel.videos.count - 1 {
                viewModel.currentVideoIndex += 1
            }
        }
    }
}

// MARK: - Player Container View

struct PlayerContainerView: UIViewRepresentable {
    let url: URL
    let playerManager: VideoPlayerManager
    let size: CGSize
    let isCurrentVideo: Bool

    func makeUIView(context _: Context) -> UIView {
        print("📊 Making video view: \(url)")
        let view = UIView(frame: CGRect(origin: .zero, size: size))
        view.backgroundColor = .black
        playerManager.setupPlayer(in: view)
        return view
    }

    func updateUIView(_: UIView, context _: Context) {
        print("📊 Updating video view: \(url)")
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
