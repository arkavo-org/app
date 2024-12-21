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
            tier: "Premium",
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
}

// MARK: - BlueskyView

struct BlueskyView: View {
    @StateObject private var viewModel = BlueskyFeedViewModel()
    @State private var currentIndex = 0

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(viewModel.posts) { _ in
//                                ImmersivePostCard(
//                                    post: post,
//                                    size: geometry.size,
//                                    isCurrentPost: post.id == viewModel.posts[viewModel.currentPostIndex].id
//                                )
//                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .onChange(of: viewModel.currentPostIndex) { _, newIndex in
//                        print("📱 Index changed to: \(newIndex)")
                        withAnimation {
                            proxy.scrollTo(viewModel.posts[newIndex].id, anchor: .center)
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onEnded { gesture in
                                let verticalMovement = gesture.translation.height
                                let swipeThreshold: CGFloat = 50
//                                print("📊 Swipe ended: \(verticalMovement)")

                                if abs(verticalMovement) > swipeThreshold {
                                    withAnimation {
                                        if verticalMovement > 0, viewModel.currentPostIndex > 0 {
//                                            print("📊 Moving to previous post")
                                            viewModel.currentPostIndex -= 1
                                        } else if verticalMovement < 0, viewModel.currentPostIndex < viewModel.posts.count - 1 {
//                                            print("📊 Moving to next post")
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
    @ObservedObject var groupViewModel: DiscordViewModel
    let post: Post
    let size: CGSize
    let isCurrentPost: Bool

    // Standard system margin from HIG, matching TikTokView
    private let systemMargin: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background with fixed frame
                if let firstImage = post.images?.first {
                    AsyncImage(url: URL(string: firstImage)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                                .frame(width: size.width, height: size.height)
                        case let .success(image):
                            image
                                .resizable()
                                .aspectFill()
                                .frame(width: size.width, height: size.height)
                        case .failure:
                            Color.black
                                .frame(width: size.width, height: size.height)
                        @unknown default:
                            Color.black
                                .frame(width: size.width, height: size.height)
                        }
                    }
                } else {
                    Color.black
                        .frame(width: size.width, height: size.height)
                }

                // Content overlay
                HStack(spacing: systemMargin * 1.25) {
                    ZStack(alignment: .center) {
                        Text(post.content)
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    .padding(systemMargin * 2)
                    Spacer()

                    // Right side - Action buttons
                    VStack(alignment: .trailing, spacing: systemMargin * 1.25) { // 20pt
                        Spacer()

                        VStack(spacing: systemMargin * 1.25) { // 20pt
//                            TikTokServersList(
//                                currentVideo: Video(
//                                    id: post.id,
//                                    url: URL(string: "placeholder")!,
//                                    contributors: [
//                                        Contributor(
//                                            id: post.author.id,
//                                            creator: post.author.asCreator(),
//                                            role: "Author"
//                                        ),
//                                    ],
//                                    description: post.content,
//                                    likes: post.likes,
//                                    comments: post.replyCount,
//                                    shares: post.reposts
//                                )
//                            )
//                            .padding(.trailing, systemMargin)
//                            .padding(.vertical, systemMargin * 2)
//                            .background(
//                                RoundedRectangle(cornerRadius: 24)
//                                    .fill(.ultraThinMaterial.opacity(0.4))
//                                    .padding(.trailing, systemMargin / 2)
//                            )

                            Button {
                                // Handle comments
                            } label: {
                                VStack(spacing: systemMargin * 0.25) { // 4pt
                                    Image(systemName: "bubble.right")
                                        .font(.system(size: systemMargin * 1.625)) // 26pt
                                    Text("\(post.replyCount)")
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
//                        ContributorsView(
//                            contributors: [
//                                Contributor(
//                                    id: post.author.id,
//                                    creator: post.author.asCreator(),
//                                    role: "Author"
//                                ),
//                            ]
//                        )
//                        .padding(.horizontal, systemMargin)
//                        .padding(.bottom, systemMargin * 8)
                        Spacer()
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
