import SwiftUI

// MARK: - Models

struct Post: Identifiable {
    let id: String
    let author: DIDUser
    let content: String
    let timestamp: Date
    var likes: Int
    var reposts: Int
    var isLiked: Bool = false
    var isReposted: Bool = false
    var images: [String]?
    var replyCount: Int
}

struct DIDUser: Identifiable {
    let id: String // DID identifier (did:plc:...)
    let handle: String // user.bsky.social
    let displayName: String
    let avatarURL: String
    let isVerified: Bool
    var isFollowing: Bool = false
    let did: String // Decentralized identifier
    var description: String?
    var followers: Int
    var following: Int
    var postsCount: Int
    var serviceEndpoint: String // AT Protocol service endpoint
}

// Helper extensions for model conversion
extension DIDUser {
    func asCreator() -> Creator {
        Creator(
            id: id,
            name: displayName,
            imageURL: avatarURL,
            latestUpdate: description ?? "",
            tier: .premium,
            socialLinks: [],
            notificationCount: 0,
            bio: description ?? ""
        )
    }
}

extension Creator {
    func asDIDUser() -> DIDUser {
        DIDUser(
            id: id,
            handle: "",
            displayName: name,
            avatarURL: imageURL,
            isVerified: false,
            did: "did:plc:\(id)",
            description: bio,
            followers: 0,
            following: 0,
            postsCount: 0,
            serviceEndpoint: "https://bsky.social/xrpc"
        )
    }
}

// MARK: - Models and Sample Data

enum SampleData {
    static let user = DIDUser(
        id: "1",
        handle: "alice.bsky.social",
        displayName: "Alice Johnson 🌟",
        avatarURL: "https://images.unsplash.com/photo-1494790108377-be9c29b29330",
        isVerified: true,
        did: "did:plc:7iza6de2dwqk7ep3kg3h3toy",
        description: "Product Designer @Mozilla | Web3 & decentralization enthusiast 🔮 | Building the future of social media | she/her | bay area 🌉",
        followers: 12849,
        following: 1423,
        postsCount: 3267,
        serviceEndpoint: "https://bsky.social/xrpc"
    )

    static let recentPosts = [
        Post(
            id: "1",
            author: user,
            content: "Just finished a deep dive into ActivityPub and AT Protocol integration. The future of social media is decentralized! 🚀 What are your thoughts on federated networks?",
            timestamp: Date().addingTimeInterval(-3600),
            likes: 142,
            reposts: 23,
            replyCount: 18
        ),
        Post(
            id: "2",
            author: user,
            content: "Speaking at @DecentralizedWeb Summit next month about design patterns in federated social networks. Who else is going to be there? Let's connect! 🎯",
            timestamp: Date().addingTimeInterval(-7200),
            likes: 89,
            reposts: 12,
            replyCount: 8
        ),
        Post(
            id: "3",
            author: user,
            content: "New blog post: 'Designing for Decentralization - A UX Perspective' 📝\n\nExploring how we can make decentralized social networks more intuitive and user-friendly while maintaining privacy and data sovereignty.",
            timestamp: Date().addingTimeInterval(-86400),
            likes: 256,
            reposts: 45,
            images: ["https://images.unsplash.com/photo-1558655146-9f40138edfeb"], replyCount: 32
        ),
        Post(
            id: "4",
            author: user,
            content: "Old blog post: 'Designing for Decentralization - A UI Perspective' \n\nExploring how we can make centralized social networks more intuitive.",
            timestamp: Date().addingTimeInterval(-86400),
            likes: 256,
            reposts: 45,
            images: ["https://images.unsplash.com/photo-1558655146-9f40138edfeb"], replyCount: 32
        ),
    ]

    static let feedFilters = ["Posts", "Replies", "Media", "Likes"]

    static let connections = [
        DIDUser(
            id: "2",
            handle: "bob.bsky.social",
            displayName: "Bob Smith",
            avatarURL: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e",
            isVerified: true,
            did: "did:plc:4563gth789iop",
            description: "Blockchain Developer | Web3 Explorer",
            followers: 8923,
            following: 745,
            postsCount: 1532,
            serviceEndpoint: "https://bsky.social/xrpc"
        ),
        DIDUser(
            id: "3",
            handle: "carol.bsky.social",
            displayName: "Carol Williams",
            avatarURL: "https://images.unsplash.com/photo-1573496359142-b8d87734a5a2",
            isVerified: false,
            did: "did:plc:789klm456nop",
            description: "Open Source Advocate | Privacy First",
            followers: 5621,
            following: 892,
            postsCount: 2341,
            serviceEndpoint: "https://bsky.social/xrpc"
        ),
        DIDUser(
            id: "4",
            handle: "david.bsky.social",
            displayName: "David Chen",
            avatarURL: "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e",
            isVerified: true,
            did: "did:plc:123qwe456rty",
            description: "Tech Lead @Decentralized Systems",
            followers: 15234,
            following: 943,
            postsCount: 4521,
            serviceEndpoint: "https://bsky.social/xrpc"
        ),
    ]

    static let activityHighlights = [
        ActivityItem(
            id: "1",
            type: .mention,
            content: "@alice.bsky.social Great talk at the Web3 conference!",
            timestamp: Date().addingTimeInterval(-1800),
            user: connections[0]
        ),
        ActivityItem(
            id: "2",
            type: .like,
            content: "Liked your post about decentralized systems",
            timestamp: Date().addingTimeInterval(-3600),
            user: connections[1]
        ),
        ActivityItem(
            id: "3",
            type: .repost,
            content: "Reposted your blog announcement",
            timestamp: Date().addingTimeInterval(-7200),
            user: connections[2]
        ),
    ]

    static let preferences = UserPreferences(
        notificationsEnabled: true,
        privateAccount: false,
        autoplayVideos: true,
        contentLanguages: ["en", "es"],
        contentWarnings: true,
        threadMuting: true
    )
}

// Additional Models
struct ActivityItem: Identifiable {
    let id: String
    let type: ActivityType
    let content: String
    let timestamp: Date
    let user: DIDUser

    enum ActivityType {
        case mention, like, repost, reply
    }
}

struct UserPreferences {
    var notificationsEnabled: Bool
    var privateAccount: Bool
    var autoplayVideos: Bool
    var contentLanguages: [String]
    var contentWarnings: Bool
    var threadMuting: Bool
}

@MainActor
class BlueskyFeedViewModel: ObservableObject {
    @Published var posts: [Post] = SampleData.recentPosts
    @Published var currentPostIndex = 0
    @Published var isLoading = false
    @Published var error: Error?

    init() {
        print("📊 BlueskyFeedViewModel initialized")
    }
}

// MARK: - BlueskyView

struct BlueskyView: View {
    @StateObject private var viewModel = BlueskyFeedViewModel()
    @ObservedObject var groupViewModel: DiscordViewModel
    @State private var currentIndex = 0
    @Binding var showCreateView: Bool
    @Binding var selectedCreator: Creator?
    @Binding var selectedServer: Server?
    @Binding var selectedTab: Tab

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.posts) { post in
                                ImmersivePostCard(
                                    post: post,
                                    groupViewModel: groupViewModel,
                                    size: geometry.size,
                                    showCreateView: $showCreateView,
                                    selectedCreator: $selectedCreator,
                                    selectedServer: $selectedServer,
                                    selectedTab: $selectedTab,
                                    isCurrentPost: post.id == viewModel.posts[viewModel.currentPostIndex].id
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .onChange(of: viewModel.currentPostIndex) { _, newIndex in
                        print("📱 Index changed to: \(newIndex)")
                        withAnimation {
                            proxy.scrollTo(viewModel.posts[newIndex].id, anchor: .center)
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                print("📊 Drag distance: \(gesture.translation.height)")
                            }
                            .onEnded { gesture in
                                let verticalMovement = gesture.translation.height
                                let swipeThreshold: CGFloat = 50
                                print("📊 Swipe ended: \(verticalMovement)")

                                if abs(verticalMovement) > swipeThreshold {
                                    withAnimation {
                                        if verticalMovement > 0, viewModel.currentPostIndex > 0 {
                                            print("📊 Moving to previous post")
                                            viewModel.currentPostIndex -= 1
                                        } else if verticalMovement < 0, viewModel.currentPostIndex < viewModel.posts.count - 1 {
                                            print("📊 Moving to next post")
                                            viewModel.currentPostIndex += 1
                                        }
                                    }
                                }
                            }
                    )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            print("📱 BlueskyView appeared")
            print("📱 Initial index: \(currentIndex)")
            print("📱 Total posts available: \(SampleData.recentPosts.count)")
        }
    }
}

// MARK: - NewPostView Update

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var postText = ""
    @State private var selectedImages: [UIImage] = []
    @Binding var selectedUser: Creator?

    // Function to detect mentions in text
    private func detectMentions(_ text: String) -> [(String, Range<String.Index>)] {
        var mentions: [(String, Range<String.Index>)] = []
        let pattern = "@[\\w\\.]+"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(text.startIndex..., in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match,
                  let range = Range(match.range, in: text) else { return }
            mentions.append((String(text[range]), range))
        }

        return mentions
    }

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $postText)
                    .frame(height: 100)
                    .padding()
                    .onChange(of: postText) { _, newValue in
                        // Process mentions as user types
                        let _ = detectMentions(newValue)
                    }

                if !selectedImages.isEmpty {
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
                }

                Spacer()
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Post") {
                        dismiss()
                    }
                    .disabled(postText.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button(action: {}) {
                            Image(systemName: "photo.on.rectangle")
                        }
                        Spacer()
                    }
                }
            }
        }
    }
}

struct ImmersivePostCard: View {
    let post: Post
    @ObservedObject var groupViewModel: DiscordViewModel
    let size: CGSize
    @Binding var showCreateView: Bool
    @Binding var selectedCreator: Creator?
    @Binding var selectedServer: Server?
    @Binding var selectedTab: Tab
    let isCurrentPost: Bool

    @State private var dragOffset = CGSize.zero
    private let swipeThreshold: CGFloat = 50
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background Image
                if let firstImage = post.images?.first {
                    AsyncImage(url: URL(string: firstImage)) { image in
                        image
                            .resizable()
                            .aspectFill()
                            .frame(width: size.width, height: size.height)
                    } placeholder: {
                        Color.black
                    }
                } else {
                    Color.black
                }

                // Gradient overlay
                LinearGradient(
                    colors: [
                        .black.opacity(0.6),
                        .black.opacity(0.3),
                        .clear,
                        .black.opacity(0.3),
                        .black.opacity(0.6),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Content overlay
                HStack(spacing: 0) {
                    // Left side - Prominent content text
                    ZStack(alignment: .center) {
                        GeometryReader { metrics in
                            Text(post.content)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: metrics.size.height * 0.6)
                                .position(
                                    x: systemMargin + geometry.safeAreaInsets.leading,
                                    y: metrics.size.height / 2
                                )
                        }
                    }
                    .frame(width: systemMargin * 2.75)

                    Spacer()

                    // Right side - Action buttons and contributors
                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) {
                        Spacer()

                        // TikTokServersList
                        TikTokServersList(
                            groupViewModel: groupViewModel,
                            selectedServer: $selectedServer,
                            selectedTab: $selectedTab,
                            currentVideo: Video(
                                id: post.id,
                                url: URL(string: "placeholder")!,
                                contributors: [
                                    Contributor(
                                        id: post.author.id,
                                        creator: post.author.asCreator(),
                                        role: "Author"
                                    ),
                                ],
                                description: post.content,
                                likes: post.likes,
                                comments: post.replyCount,
                                shares: post.reposts
                            )
                        ) { _, _ in
                            // Handle share action
                        }
                        .padding(.trailing, systemMargin)
                        .padding(.vertical, systemMargin * 2)
                        .background(
                            RoundedRectangle(cornerRadius: 24)
                                .fill(.ultraThinMaterial.opacity(0.4))
                                .padding(.trailing, systemMargin / 2)
                        )

                        // Comment button
                        Button {
                            // Handle comments
                        } label: {
                            VStack(spacing: systemMargin * 0.25) {
                                Image(systemName: "bubble.right")
                                    .font(.system(size: systemMargin * 1.625))
                                Text("\(post.replyCount)")
                                    .font(.caption)
                            }
                            .foregroundColor(.white)
                        }

                        Spacer()
                            .frame(height: systemMargin * 4)
                    }
                    .padding(.trailing, systemMargin + geometry.safeAreaInsets.trailing)
                }

                // Contributors section at bottom
                VStack {
                    Spacer()
                    HStack {
                        ContributorsView(
                            contributors: [
                                Contributor(
                                    id: post.author.id,
                                    creator: post.author.asCreator(),
                                    role: "Author"
                                ),
                            ],
                            showCreateView: $showCreateView,
                            selectedCreator: $selectedCreator,
                            selectedTab: $selectedTab
                        )
                        .padding(.horizontal, systemMargin)
                        .padding(.bottom, systemMargin * 8)
                        Spacer()
                    }
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

// Helper View for Creators List (similar to ContributorsView in TikTokView)
struct CreatorsList: View {
    let creators: [Creator]
    @Binding var showCreateView: Bool
    @Binding var selectedCreator: DIDUser?
    @State private var showAllCreators = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let mainCreator = creators.first {
                Button {
                    selectedCreator = DIDUser(
                        id: mainCreator.id,
                        handle: mainCreator.name,
                        displayName: mainCreator.name,
                        avatarURL: mainCreator.imageURL,
                        isVerified: true,
                        did: "did:plc:\(mainCreator.id)",
                        description: nil,
                        followers: 0,
                        following: 0,
                        postsCount: 0,
                        serviceEndpoint: "https://bsky.social/xrpc"
                    )
                } label: {
                    HStack(spacing: 8) {
                        AsyncImage(url: URL(string: "https://images.unsplash.com/photo-1472099645785-5658abf4ff4e")) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())

                        VStack(alignment: .leading) {
                            Text(mainCreator.name)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text("@\(mainCreator.name)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func aspectFill() -> some View {
        scaledToFill()
            .clipped()
    }
}
