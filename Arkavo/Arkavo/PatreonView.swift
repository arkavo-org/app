import SwiftUI

// Models
struct Creator: Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String
    let latestUpdate: String
    let tier: CreatorTier
    let socialLinks: [SocialLink]
    let notificationCount: Int
    let bio: String
}

struct SocialLink: Identifiable, Hashable {
    let id: String
    let platform: SocialPlatform
    let username: String
    let url: String
}

enum SocialPlatform: String {
    case twitter = "Twitter"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"

    var icon: String {
        switch self {
        case .twitter: "bubble.left.and.bubble.right"
        case .instagram: "camera"
        case .youtube: "play.rectangle"
        case .tiktok: "music.note"
        }
    }
}

struct CreatorPost: Identifiable {
    let id: String
    let content: String
    let mediaURL: String?
    let timestamp: Date
    let tierAccess: CreatorTier
}

enum CreatorTier: String, CaseIterable {
    case basic = "Basic"
    case premium = "Premium"
    case exclusive = "Exclusive"
}

struct Message: Identifiable {
    let id: String
    let creatorId: String
    let content: String
    let timestamp: Date
    var isPinned: Bool = false
}

// Sample Data
extension Creator {
    static let sampleCreators = [
        Creator(
            id: "1",
            name: "Digital Art Master",
            imageURL: "https://example.com/creator1",
            latestUpdate: "Just posted a new digital painting tutorial!",
            tier: .premium,
            socialLinks: [
                SocialLink(id: "1", platform: .twitter, username: "@digitalartist", url: "https://twitter.com/digitalartist"),
                SocialLink(id: "2", platform: .instagram, username: "digitalartmaster", url: "https://instagram.com/digitalartmaster"),
            ],
            notificationCount: 3,
            bio: "Professional digital artist with 10+ years of experience. Specializing in character design and concept art."
        ),
        Creator(
            id: "2",
            name: "Music Producer Pro",
            imageURL: "https://example.com/creator2",
            latestUpdate: "New beat pack dropping this weekend 🎵",
            tier: .exclusive,
            socialLinks: [
                SocialLink(id: "1", platform: .twitter, username: "@digitalartist", url: "https://twitter.com/digitalartist"),
                SocialLink(id: "2", platform: .instagram, username: "digitalartmaster", url: "https://instagram.com/digitalartmaster"),
            ],
            notificationCount: 3,
            bio: "Professional digital artist with 10+ years of experience. Specializing in character design and concept art."
        ),
        Creator(
            id: "3",
            name: "Cooking with Chef Sarah",
            imageURL: "https://example.com/creator3",
            latestUpdate: "Exclusive recipe: Gourmet pasta carbonara",
            tier: .basic,
            socialLinks: [
                SocialLink(id: "1", platform: .twitter, username: "@digitalartist", url: "https://twitter.com/digitalartist"),
                SocialLink(id: "2", platform: .instagram, username: "digitalartmaster", url: "https://instagram.com/digitalartmaster"),
            ],
            notificationCount: 3,
            bio: "Professional digital artist with 10+ years of experience. Specializing in character design and concept art."
        ),
        Creator(
            id: "4",
            name: "Tech Insights Daily",
            imageURL: "https://example.com/creator4",
            latestUpdate: "Early access to my latest iOS development course",
            tier: .premium,
            socialLinks: [
                SocialLink(id: "1", platform: .twitter, username: "@digitalartist", url: "https://twitter.com/digitalartist"),
                SocialLink(id: "2", platform: .instagram, username: "digitalartmaster", url: "https://instagram.com/digitalartmaster"),
            ],
            notificationCount: 3,
            bio: "Professional digital artist with 10+ years of experience. Specializing in character design and concept art."
        ),
    ]
}

extension CreatorPost {
    static let samplePosts = [
        CreatorPost(
            id: "1",
            content: "🎨 New Digital Art Tutorial: Master Character Design",
            mediaURL: "https://example.com/tutorial1.jpg",
            timestamp: Date().addingTimeInterval(-3600),
            tierAccess: .basic
        ),
        CreatorPost(
            id: "2",
            content: "🎵 Exclusive Behind-the-Scenes: Studio Session",
            mediaURL: "https://example.com/studio.jpg",
            timestamp: Date().addingTimeInterval(-7200),
            tierAccess: .premium
        ),
        CreatorPost(
            id: "3",
            content: "🍳 Premium Recipe Collection: Spring Edition",
            mediaURL: "https://example.com/recipes.jpg",
            timestamp: Date().addingTimeInterval(-10800),
            tierAccess: .exclusive
        ),
        CreatorPost(
            id: "4",
            content: "💻 Early Access: SwiftUI Advanced Techniques",
            mediaURL: "https://example.com/swiftui.jpg",
            timestamp: Date().addingTimeInterval(-14400),
            tierAccess: .premium
        ),
    ]
}

extension Message {
    static let sampleMessages = [
        Message(
            id: "1",
            creatorId: "1",
            content: "🎉 New tutorial dropping tomorrow! Get ready for an in-depth look at digital painting techniques.",
            timestamp: Date().addingTimeInterval(-1800),
            isPinned: true
        ),
        Message(
            id: "2",
            creatorId: "2",
            content: "Thanks for your amazing support! Working on something special for my premium supporters.",
            timestamp: Date().addingTimeInterval(-3600),
            isPinned: false
        ),
        Message(
            id: "3",
            creatorId: "3",
            content: "Just finished filming next week's cooking masterclass. You're going to love this recipe!",
            timestamp: Date().addingTimeInterval(-7200),
            isPinned: false
        ),
        Message(
            id: "4",
            creatorId: "4",
            content: "📱 Quick update: The iOS development course is now 80% complete. Early access coming soon!",
            timestamp: Date().addingTimeInterval(-10800),
            isPinned: true
        ),
    ]
}

// Main View
struct PatreonView: View {
    @State private var selectedTab = 0
    @State private var creators: [Creator] = Creator.sampleCreators
    @State private var messages: [Message] = Message.sampleMessages
    @State private var exclusiveContent: [CreatorPost] = CreatorPost.samplePosts

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                ExclusiveContentView(posts: exclusiveContent)
                    .tabItem {
                        Label("Exclusives", systemImage: "star.fill")
                    }
                    .tag(0)
                Spacer()
                CreatorListView(creators: creators)
                    .tabItem {
                        Label("Creators", systemImage: "person.2.fill")
                    }
                    .tag(1)
            }
            .navigationTitle(navigationTitle)
        }
    }

    var navigationTitle: String {
        switch selectedTab {
        case 0: "Exclusives"
        case 1: "Creators"
        default: ""
        }
    }
}

// Creator List View
struct CreatorListView: View {
    let creators: [Creator]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(creators) { creator in
                    NavigationLink(destination: ChatView(creator: creator)) {
                        CreatorCard(creator: creator)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding()
        }
    }
}

struct CreatorCard: View {
    let creator: Creator
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Profile Image
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .foregroundColor(.blue)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(creator.name)
                            .font(.title2)
                            .bold()

                        if creator.notificationCount > 0 {
                            Text("\(creator.notificationCount)")
                                .font(.caption)
                                .padding(6)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Circle())
                        }
                    }

                    Text(creator.tier.rawValue)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .cornerRadius(8)
                }

                Spacer()

                Button {
                    withAnimation(.spring()) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundColor(.secondary)
                }
            }
            .padding()

            // Expandable Content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Bio
                    Text(creator.bio)
                        .font(.body)
                        .padding(.horizontal)

                    // Latest Update
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Update")
                            .font(.headline)
                        Text(creator.latestUpdate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

                    // Social Links
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Social Media")
                            .font(.headline)

                        ForEach(creator.socialLinks) { link in
                            HStack {
                                Image(systemName: link.platform.icon)
                                Text(link.username)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct CreatorChatButton: View {
    let creator: Creator
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                        .frame(width: 50, height: 50)

                    Text(creator.name.prefix(1))
                        .font(.title3.bold())
                        .foregroundColor(isSelected ? .white : .primary)
                }

                Text(creator.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
    }
}

// Exclusive Content View
struct ExclusiveContentView: View {
    let posts: [CreatorPost]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                ForEach(posts) { post in
                    ExclusivePostCard(post: post)
                }
            }
            .padding()
        }
    }
}

struct ExclusivePostCard: View {
    let post: CreatorPost

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Using color rectangle as placeholder since URLs won't load in preview
            Rectangle()
                .fill(Color.blue.opacity(0.1))
                .overlay(
                    Image(systemName: "photo.fill")
                        .foregroundColor(.blue)
                        .font(.largeTitle)
                )
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(post.content)
                .font(.subheadline)
                .lineLimit(3)

            HStack {
                Text(post.tierAccess.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(8)

                Spacer()

                Text(post.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

// Preview
#Preview {
    PatreonView()
}

// Dark Mode Preview
#Preview {
    PatreonView()
        .preferredColorScheme(.dark)
}
