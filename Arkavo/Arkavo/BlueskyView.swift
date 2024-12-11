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

// MARK: - Main View

struct BlueskyView: View {
    @State private var searchText = ""
    @State private var selectedTab: Tab = .forYou
    @State private var showNewPostSheet = false
    @State private var showProfile = false
    @State private var selectedUser: DIDUser?

    enum Tab {
        case forYou, following
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Feed Selector
                Picker("Feed", selection: $selectedTab) {
                    Text("For You").tag(Tab.forYou)
                    Text("Following").tag(Tab.following)
                }
                .pickerStyle(.segmented)
                .padding()

                // Main Feed
                FeedView(tab: selectedTab)
                    .refreshable {
                        // Implement pull-to-refresh
                    }
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewPostSheet.toggle() }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search Bluesky")
            .sheet(isPresented: $showNewPostSheet) {
                NewPostView()
            }
            .sheet(isPresented: $showProfile) {
                ProfileView()
            }
        }
    }
}

// MARK: - Feed View

struct FeedView: View {
    let tab: BlueskyView.Tab
    @State private var posts: [Post] = [] // In real app, use @StateObject with view model

    var body: some View {
        List {
            ForEach(posts) { post in
                PostCard(post: post)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author Info
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

                Button(action: { showActions.toggle() }) {
                    Image(systemName: "ellipsis")
                        .foregroundColor(.gray)
                }
            }

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

// MARK: - New Post View

struct NewPostView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var postText = ""
    @State private var selectedImages: [UIImage] = []

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $postText)
                    .frame(height: 100)
                    .padding()

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
                        // Implement post creation
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

#Preview {
    BlueskyView()
}
