import ArkavoSocial
import SwiftUI

struct PatreonView: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var creators: [Creator] = []
    @State private var messages: [Message] = Message.sampleMessages
    @State private var exclusiveContent: [CreatorPost] = CreatorPost.samplePosts

    var body: some View {
        NavigationStack {
            if let creator = sharedState.selectedCreator, !sharedState.showCreateView {
                CreatorDetailView(
                    creator: creator
                )
            } else {
                CreatorListView(creators: creators) { creator in
                    sharedState.selectedCreator = creator
                }
            }
        }
        .sheet(isPresented: $sharedState.showCreateView) {
            if let creator = sharedState.selectedCreator {
                PatreonSupportView(creator: creator) {
                    sharedState.showCreateView = false
                }
            }
        }
    }
}

struct CreatorSearchView: View {
    let creators: [Creator]
    let onCreatorSelected: (Creator) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    // Featured creator (could be randomized or selected based on criteria)
    private let featuredCreator = Creator(
        id: "featured",
        name: "Featured Artist",
        imageURL: "https://example.com/featured",
        latestUpdate: "Special collaboration event this weekend! 🎨",
        tier: "Premium",
        socialLinks: [
            SocialLink(id: "1", platform: .twitter, username: "@featuredartist", url: "https://twitter.com/featuredartist"),
            SocialLink(id: "2", platform: .instagram, username: "featuredartist", url: "https://instagram.com/featuredartist"),
        ],
        notificationCount: 1,
        bio: "Award-winning digital artist specializing in concept art and character design. Join me for weekly live sessions!"
    )

    var filteredCreators: [Creator] {
        if searchText.isEmpty {
            return creators
        }
        return creators.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.bio.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Featured Creator Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Featured Creator")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)

                        Button {
                            onCreatorSelected(featuredCreator)
                        } label: {
                            CreatorCard(creator: featuredCreator)
                                .padding(.horizontal)
                        }
                    }

                    // Search Results
                    if !searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Search Results")
                                .font(.title2)
                                .bold()
                                .padding(.horizontal)

                            ForEach(filteredCreators) { creator in
                                Button {
                                    onCreatorSelected(creator)
                                } label: {
                                    CreatorCard(creator: creator)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }

                    // Recently Active Creators
                    if searchText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recently Active")
                                .font(.title2)
                                .bold()
                                .padding(.horizontal)

                            ForEach(creators.prefix(3)) { creator in
                                Button {
                                    onCreatorSelected(creator)
                                } label: {
                                    CreatorCard(creator: creator)
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical)
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer,
                prompt: "Search creators..."
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Creator List View
struct CreatorListView: View {
    let creators: [Creator]
    let onCreatorSelected: (Creator) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(creators) { creator in
                    Button {
                        onCreatorSelected(creator)
                    } label: {
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

                    Text(creator.tier)
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

struct CreatorDetailView: View {
    @EnvironmentObject var sharedState: SharedState
    let creator: Creator
    @State private var selectedSection: DetailSection = .about

    enum DetailSection {
        case about, media, posts, schedule

        var title: String {
            switch self {
            case .about: "About"
            case .media: "Media"
            case .posts: "Posts"
            case .schedule: "Schedule"
            }
        }
    }

    private let mediaItems: [MediaItem] = [
        MediaItem(id: "1", type: .video, title: "Behind the Scenes", thumbnailURL: "video1.jpg", duration: 180, views: 1500),
        MediaItem(id: "2", type: .image, title: "Latest Artwork", thumbnailURL: "image1.jpg", likes: 250),
        MediaItem(id: "3", type: .video, title: "Tutorial - Digital Art", thumbnailURL: "video2.jpg", duration: 900, views: 3200),
        MediaItem(id: "4", type: .audio, title: "Podcast Episode 1", thumbnailURL: "audio1.jpg", duration: 1800, plays: 800),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CreatorHeaderView(creator: creator) {
                    sharedState.showCreateView = true
                }

                Picker("Section", selection: $selectedSection) {
                    ForEach([DetailSection.about, .media, .posts, .schedule], id: \.self) { section in
                        Text(section.title)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedSection {
                case .about:
                    CreatorAboutSection(creator: creator)
                case .media:
                    CreatorMediaSection(creator: creator)
                case .posts:
                    CreatorPostsSection(posts: CreatorPost.samplePosts)
                case .schedule:
                    CreatorScheduleSection(creator: creator)
                }
            }
        }
        .navigationTitle(creator.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreatorHeaderView: View {
    let creator: Creator
    let onSupport: () -> Void
    @State private var isSupporting = false
    @State private var isProtecting = false

    private let profileImageSize: CGFloat = 80
    private let statsSpacing: CGFloat = 32
    private let buttonHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: profileImageSize, height: profileImageSize)
                    .foregroundColor(.blue)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Circle())

                HStack(spacing: statsSpacing) {
                    StatView(title: "Posts", value: "324")
                    StatView(title: "Followers", value: "15.2K")
                    StatView(title: "Rating", value: "4.9")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Button {
                    onSupport()
                } label: {
                    Text("Support")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(isSupporting ? Color.gray.opacity(0.2) : Color.blue)
                        .cornerRadius(8)
                }

                Button {
                    isProtecting.toggle()
                } label: {
                    Text(isProtecting ? "Protecting" : "Protect")
                        .font(.headline)
                        .foregroundColor(isSupporting ? .secondary : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                        .background(isProtecting ? Color.gray.opacity(0.2) : Color.blue)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

struct StatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .bold()
        }
    }
}

struct CreatorAboutSection: View {
    let creator: Creator

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Bio
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .font(.headline)
                Text(creator.bio)
                    .font(.body)
            }
            .padding()

            // Social Links
            VStack(alignment: .leading, spacing: 8) {
                Text("Social Media")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(creator.socialLinks) { link in
                    HStack {
                        Image(systemName: link.platform.icon)
                        Text(link.username)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
        }
    }
}

struct CreatorMediaSection: View {
    let viewModel = ViewModelFactory.shared.makePatreonViewModel()
    let creator: Creator
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            ForEach(viewModel.videoThoughts, id: \.id) { thought in
                VideoThoughtView(thought: thought)
                    .onTapGesture {
                        // FIXME: Handle video selection
                        print("send thought")
                    }
            }
        }
        .padding()
    }
}

struct VideoThoughtView: View {
    let thought: Thought

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: geometry.size.width)
                        .cornerRadius(8)
                        .clipped()

                    Image(systemName: "play.rectangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(thought.metadata.summary)
                    .font(.subheadline)
                    .lineLimit(2)

                Text(thought.metadata.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct MediaItemView: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(width: geometry.size.width)
                        .cornerRadius(8)
                        .clipped()

                    Image(systemName: item.type.icon)
                        .font(.largeTitle)
                        .foregroundColor(.white)

                    if item.type != .image, let duration = item.duration {
                        VStack {
                            Spacer()
                            HStack {
                                Text(duration.formattedDuration)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .cornerRadius(4)
                                Spacer()
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .lineLimit(2)

                HStack {
                    switch item.type {
                    case .video:
                        Image(systemName: "eye")
                        Text("\(item.views ?? 0) views")
                    case .audio:
                        Image(systemName: "play")
                        Text("\(item.plays ?? 0) plays")
                    case .image:
                        Image(systemName: "heart")
                        Text("\(item.likes ?? 0) likes")
                    case .text:
                        Image(systemName: "doc")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
}

struct CreatorPostsSection: View {
    let posts: [CreatorPost]

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(posts) { post in
                CreatorPostCard(post: post)
            }
        }
        .padding()
    }
}

struct CreatorPostCard: View {
    let post: CreatorPost

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if post.mediaURL != nil {
                // Media Preview
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 200)
                    .cornerRadius(8)
            }

            Text(post.content)
                .font(.body)

            HStack {
                Text(post.timestamp, style: .relative)
                Text("•")
                Text(post.tierAccess.rawValue)
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct CreatorScheduleSection: View {
    let creator: Creator
    let schedule = [
        ScheduleEvent(day: "Monday", title: "Live Drawing Session", time: "2 PM EST"),
        ScheduleEvent(day: "Wednesday", title: "Tutorial Release", time: "11 AM EST"),
        ScheduleEvent(day: "Friday", title: "Q&A Session", time: "4 PM EST"),
        ScheduleEvent(day: "Saturday", title: "Behind the Scenes", time: "1 PM EST"),
    ]

    var body: some View {
        VStack(spacing: 16) {
            ForEach(schedule) { event in
                HStack {
                    VStack(alignment: .leading) {
                        Text(event.day)
                            .font(.headline)
                        Text(event.title)
                            .font(.subheadline)
                        Text(event.time)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "bell")
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

// Additional Models
struct MediaItem: Identifiable {
    let id: String
    let type: MediaType
    let title: String
    let thumbnailURL: String
    var duration: Int?
    var views: Int?
    var plays: Int?
    var likes: Int?

    var formattedDuration: String {
        guard let duration else { return "" }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum MediaType: String, Codable {
    case text, video, audio, image

    var icon: String {
        switch self {
        case .video: "play.rectangle.fill"
        case .audio: "waveform"
        case .image: "photo.fill"
        case .text: "doc.fill"
        }
    }
}

struct ScheduleEvent: Identifiable {
    let id = UUID()
    let day: String
    let title: String
    let time: String
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

// Models
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

// Helper Extensions
extension Int {
    var formattedDuration: String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
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

@MainActor
final class PatreonViewModel: ObservableObject {
    private let client: ArkavoClient
    private let account: Account
    private let profile: Profile

    // Published properties
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var creators: [Creator] = []
    @Published private(set) var videoThoughts: [Thought] = []
    @Published private(set) var supportedCreators: [Creator] = []
    @Published private(set) var messages: [Message] = []

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        loadVideoThoughts()
    }

    // MARK: - Public Methods

    func loadCreators() async {}

    func loadVideoThoughts() {
        let videoStream = account.streams.first(where: { stream in
            stream.sources.first?.metadata.mediaType == .video
        })
        if videoStream != nil {
            videoThoughts = videoStream!.thoughts
        }
    }

    func loadSupportedCreators() async {}

    func loadMessages(for _: Creator) async {}

    func supportCreator(_: Creator, tier _: CreatorTier) async {}

    func cancelSupport(for _: Creator) async {}

    // MARK: - Creator Status Methods

    func isSupporting(_ creator: Creator) -> Bool {
        supportedCreators.contains { $0.id == creator.id }
    }

    func currentTier(for _: Creator) -> CreatorTier? {
        CreatorTier.premium
    }

    // MARK: - Helper Methods

    private func handleError(_ error: Error) {
        self.error = error
        isLoading = false
    }
}
