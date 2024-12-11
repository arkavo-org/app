import AVKit
import SwiftUI

struct Video: Identifiable {
    let id: UUID = .init()
    let url: URL
    let creatorName: String
    let description: String
    var likes: Int
    var comments: Int
    var shares: Int
}

struct TikTokFeedView: View {
    @State private var currentIndex = 0
    @State private var showComments = false

    // Sample videos - replace with your actual data
    @State private var videos: [Video] = [
        Video(
            url: URL(string: "https://example.com/video1.mp4")!,
            creatorName: "creator1",
            description: "First video",
            likes: 100,
            comments: 50,
            shares: 25
        ),
        Video(
            url: URL(string: "https://example.com/video2.mp4")!,
            creatorName: "creator2",
            description: "Second video",
            likes: 200,
            comments: 75,
            shares: 30
        ),
        Video(
            url: URL(string: "https://example.com/video3.mp4")!,
            creatorName: "creator3",
            description: "Third video",
            likes: 150,
            comments: 60,
            shares: 40
        ),
        Video(
            url: URL(string: "https://example.com/video3.mp4")!,
            creatorName: "creator4",
            description: "video",
            likes: 2,
            comments: 3,
            shares: 4
        ),
    ]

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(videos.indices, id: \.self) { index in
                            VideoPlayerView(
                                video: videos[index],
                                showComments: $showComments,
                                index: index
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(index)
                            .simultaneousGesture(
                                DragGesture()
                                    .onEnded { value in
                                        let verticalMovement = value.translation.height
                                        let threshold: CGFloat = 50 // Adjust for sensitivity

                                        if abs(verticalMovement) > threshold {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                if verticalMovement > 0, currentIndex > 0 {
                                                    currentIndex -= 1
                                                } else if verticalMovement < 0, currentIndex < videos.count - 1 {
                                                    currentIndex += 1
                                                }
                                                proxy.scrollTo(currentIndex, anchor: .center)
                                            }
                                        }
                                    }
                            )
                        }
                    }
                }
                .scrollDisabled(true) // Disable native scroll for custom handling
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showComments) {
            CommentsView(showComments: $showComments)
        }
    }
}

struct VideoPlayerView: View {
    let video: Video
    @Binding var showComments: Bool
    let index: Int

    @State private var scale = 1.0
    @State private var rotation = 0.0
    @State private var bounce = false
    @State private var isLiked = false
    @State private var likesCount: Int

    init(video: Video, showComments: Binding<Bool>, index: Int) {
        self.video = video
        _showComments = showComments
        self.index = index
        _likesCount = State(initialValue: video.likes)
    }

    var body: some View {
        ZStack {
            Color.black // Placeholder for video
                .overlay(
                    Text("Video \(index + 1)")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                        .scaleEffect(scale)
                        .rotationEffect(.degrees(rotation))
                        .offset(y: bounce ? -20 : 0)
                        .onAppear {
                            withAnimation(
                                .easeInOut(duration: 2)
                                    .repeatForever(autoreverses: true)
                            ) {
                                scale = 1.3
                            }

                            withAnimation(
                                .linear(duration: 4)
                                    .repeatForever(autoreverses: false)
                            ) {
                                rotation = 360
                            }

                            withAnimation(
                                .spring(response: 0.5, dampingFraction: 0.5)
                                    .repeatForever(autoreverses: true)
                            ) {
                                bounce = true
                            }
                        }
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
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                isLiked.toggle()
                                likesCount += isLiked ? 1 : -1
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.title)
                                    .foregroundColor(isLiked ? .red : .white)
                                Text("\(likesCount)")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }

                        ActionButton(
                            icon: "message",
                            count: video.comments,
                            action: { showComments = true }
                        )

                        ActionButton(
                            icon: "square.and.arrow.up",
                            count: video.shares,
                            action: {}
                        )
                    }
                    .padding(.trailing)
                }
                .padding(.bottom, 30)
            }
        }
        // Enable double-tap to like
        .onTapGesture(count: 2) {
            if !isLiked {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isLiked = true
                    likesCount += 1
                }
            }
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

#Preview {
    TikTokFeedView()
}
