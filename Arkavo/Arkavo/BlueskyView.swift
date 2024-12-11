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

// MARK: - BlueskyView

struct BlueskyView: View {
    @State private var searchText = ""
    @State private var selectedTab: Tab = .forYou
    @State private var selectedUser: DIDUser?
    @State private var searchResults: [DIDUser] = []
    @State private var isSearching = false
    @State private var showNewPost = false

    enum Tab {
        case forYou, following
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSearching {
                SearchResultsView(
                    searchText: $searchText,
                    searchResults: $searchResults,
                    selectedUser: $selectedUser,
                    isSearching: $isSearching
                )
            } else {
                HStack {
                    Button(action: { isSearching = true }) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    Spacer()
                    Button(action: { showNewPost = true }) {
                        Image(systemName: "square.and.pencil")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                FeedView(tab: selectedTab, selectedUser: $selectedUser)
            }
        }
        .sheet(isPresented: $showNewPost) {
            NewPostView(selectedUser: $selectedUser)
        }
    }
}

// Extracted Main Feed Container
struct MainFeedContainer: View {
    @Binding var searchText: String
    @Binding var selectedTab: BlueskyView.Tab
    @Binding var showNewPostSheet: Bool
    @Binding var selectedUser: DIDUser?
    @Binding var searchResults: [DIDUser]
    @Binding var isSearching: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !isSearching {
                SearchBar(searchText: $searchText, isSearching: $isSearching)
                    .padding(.horizontal)
            }

            Picker("Feed", selection: $selectedTab) {
                Text("For You").tag(BlueskyView.Tab.forYou)
                Text("Following").tag(BlueskyView.Tab.following)
            }
            .pickerStyle(.segmented)
            .padding()

            if isSearching {
                SearchResultsView(
                    searchText: $searchText,
                    searchResults: $searchResults,
                    selectedUser: $selectedUser,
                    isSearching: $isSearching
                )
            } else {
                FeedView(tab: selectedTab, selectedUser: $selectedUser)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: { showNewPostSheet.toggle() }) {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                    }
                    .navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// Search Bar remains the same
struct SearchBar: View {
    @Binding var searchText: String
    @Binding var isSearching: Bool

    var body: some View {
        Button(action: {
            isSearching = true
        }) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                Text("Search Bluesky")
                    .foregroundColor(.gray)
                Spacer()
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
    }
}

// MARK: - Feed View

struct FeedView: View {
    let tab: BlueskyView.Tab
    @State private var posts: [Post] = SampleData.recentPosts
    @Binding var selectedUser: DIDUser?

    var body: some View {
        List {
            ForEach(posts) { post in
                PostCard(post: post, selectedUser: $selectedUser)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 8)
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Post Card

struct PostCard: View {
    @State var post: Post
    @State private var showActions = false
    @Binding var selectedUser: DIDUser?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author Info
            Button(action: { selectedUser = post.author }) {
                HStack {
                    AsyncImage(url: URL(string: post.author.avatarURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(post.author.displayName)
                                .font(.headline)
                            if post.author.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        Text("@\(post.author.handle)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Content
            Text(post.content)
                .font(.body)

            // Images if any
            if let images = post.images {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images, id: \.self) { imageURL in
                            AsyncImage(url: URL(string: imageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }

            // Action Buttons
            HStack(spacing: 24) {
                Button(action: {}) {
                    Label("\(post.replyCount)", systemImage: "bubble.left")
                }

                Button(action: { post.isReposted.toggle() }) {
                    Label("\(post.reposts)", systemImage: post.isReposted ? "repeat.circle.fill" : "repeat.circle")
                }
                .foregroundColor(post.isReposted ? .green : .gray)

                Button(action: { post.isLiked.toggle() }) {
                    Label("\(post.likes)", systemImage: post.isLiked ? "heart.fill" : "heart")
                }
                .foregroundColor(post.isLiked ? .red : .gray)

                Button(action: {}) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .font(.subheadline)
            .foregroundColor(.gray)
        }
        .padding(.horizontal)
        .confirmationDialog("Post Actions", isPresented: $showActions) {
            Button("Copy Link", role: .none) {}
            Button("Share Post", role: .none) {}
            Button("Mute User", role: .destructive) {}
            Button("Report Post", role: .destructive) {}
        }
    }
}

// MARK: - NewPostView Update

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var postText = ""
    @State private var selectedImages: [UIImage] = []
    @Binding var selectedUser: DIDUser?

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

struct MediaGridView: View {
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0 ..< 20, id: \.self) { _ in
                Color.gray.opacity(0.3)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }
}

struct SearchResultsView: View {
    @Binding var searchText: String
    @Binding var searchResults: [DIDUser]
    @Binding var selectedUser: DIDUser?
    @Binding var isSearching: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(searchResults) { user in
                    Button(action: {
                        selectedUser = user
                        isSearching = false
                    }) {
                        HStack {
                            AsyncImage(url: URL(string: user.avatarURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(user.displayName)
                                    .font(.headline)
                                Text("@\(user.handle)")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search Bluesky")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isSearching = false
                        searchText = ""
                    }
                }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty {
                searchResults = SampleData.connections.filter {
                    $0.handle.localizedCaseInsensitiveContains(newValue) ||
                        $0.displayName.localizedCaseInsensitiveContains(newValue)
                }
            } else {
                searchResults = []
            }
        }
    }
}

#Preview {
    BlueskyView()
}
