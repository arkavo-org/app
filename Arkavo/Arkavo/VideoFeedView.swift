import ArkavoSocial
import AVFoundation
import Foundation
import SwiftData
import SwiftUI

// MARK: - Main View

struct VideoContentView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject private var feedViewModel: VideoFeedViewModel

    init() {
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
    let client: ArkavoClient
    let contributors: [Contributor]
    @State private var showAllContributors = false
    @State private var profile: ArkavoProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let mainContributor = contributors.first {
                ContributorProfileButton(
                    contributor: mainContributor,
                    profile: profile,
                    sharedState: sharedState,
                    size: .large,
                    showRole: false
                )
                .task {
                    do {
                        profile = try await client.fetchProfile(forPublicID: mainContributor.profilePublicID)
                    } catch {
                        print("Error fetching profile: \(error)")
                    }
                }
            }

            if contributors.count > 1 {
                if showAllContributors {
                    ForEach(contributors.dropFirst()) { contributor in
                        ContributorProfileButton(
                            contributor: contributor,
                            profile: profile,
                            sharedState: sharedState,
                            size: .small,
                            showRole: true
                        )
                        .padding(.leading, 8)
                        .task {
                            do {
                                profile = try await client.fetchProfile(forPublicID: contributor.profilePublicID)
                            } catch {
                                print("Error fetching profile: \(error)")
                            }
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

private struct ContributorProfileButton: View {
    let contributor: Contributor
    let profile: ArkavoProfile?
    let sharedState: SharedState

    enum Size {
        case large
        case small
    }

    let size: Size
    let showRole: Bool

    var body: some View {
        Button {
            sharedState.selectedCreatorPublicID = contributor.profilePublicID
            sharedState.selectedTab = .profile
            sharedState.showCreateView = false
        } label: {
            HStack(spacing: 8) {
                if let profile {
                    AsyncImage(url: URL(string: profile.avatarUrl)) { image in
                        image
                            .resizable()
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.blue)
                    }
                    .frame(width: size == .large ? 32 : 24,
                           height: size == .large ? 32 : 24)

                    VStack(alignment: .leading) {
                        Text(profile.displayName)
                            .font(size == .large ? .headline : .subheadline)
                        HStack {
                            Text(profile.handle)
                            if showRole {
                                Text("• \(contributor.role)")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: size == .large ? 32 : 24,
                               height: size == .large ? 32 : 24)
                        .clipShape(Circle())
                        .foregroundColor(.blue)
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    @EnvironmentObject var sharedState: SharedState
    @ObservedObject var viewModel: VideoFeedViewModel
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
        servers = viewModel.streams()
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
                            streams: servers
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
                            client: viewModel.client,
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
                    .onEnded { gesture in
                        let verticalMovement = gesture.translation.height
                        if abs(verticalMovement) > swipeThreshold {
                            Task {
                                if verticalMovement < 0 {
                                    await viewModel.handleSwipe(.up)
                                } else {
                                    await viewModel.handleSwipe(.down)
                                }
                            }
                        }
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
    let streams: [Stream]
    @State private var isCollapsed = true
    @State private var showMenuButton = true

    // Timer to auto-collapse after 4 seconds
    let collapseTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .trailing) {
            if !isCollapsed {
                // Expanded view with all buttons
                VStack(spacing: 20) { // Even spacing between all items
                    ForEach(streams) { stream in
                        Button {
                            sharedState.selectedVideo = currentVideo
                            sharedState.selectedThought = currentThought
                            sharedState.selectedStreamPublicID = stream.publicID
                            sharedState.showChatOverlay = true
                        } label: {
                            Image(systemName: iconForStream(stream))
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .frame(width: 44, height: 44)
                        }
                    }

                    // Comment button integrated into the list
                    Button {
                        sharedState.selectedVideo = currentVideo
                        sharedState.selectedStreamPublicID = currentVideo?.streamPublicID
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
