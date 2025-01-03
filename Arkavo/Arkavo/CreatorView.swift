import ArkavoSocial
import SwiftUI

struct CreatorView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel
    @State private var creators: [Creator] = []
    @State private var messages: [Message] = Message.sampleMessages
    @State private var exclusiveContent: [CreatorPost] = CreatorPost.samplePosts

    init() {
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makePatreonViewModel())
    }

    var body: some View {
        NavigationStack {
            if let creator = sharedState.selectedCreator {
                CreatorDetailView(viewModel: viewModel, creator: creator)
            } else {
                CreatorListView(creators: creators) { creator in
                    sharedState.selectedCreator = creator
                }
            }
        }
        .onDisappear {
            sharedState.selectedCreator = nil
        }
        // TODO: after Patreon Support added
//        .sheet(isPresented: $sharedState.showCreateView) {
//            if let creator = sharedState.selectedCreator {
//                CreatorSupportView(creator: creator) {
//                    sharedState.showCreateView = false
//                }
//            }
//        }
    }
}

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
            HStack(spacing: 12) {
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

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text(creator.bio)
                        .font(.body)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest Update")
                            .font(.headline)
                        Text(creator.latestUpdate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)

//                    VStack(alignment: .leading, spacing: 8) {
//                        Text("Social Media")
//                            .font(.headline)
//
//                        ForEach(creator.socialLinks) { link in
//                            HStack {
//                                Image(systemName: link.platform.icon)
//                                Text(link.username)
//                                Spacer()
//                                Image(systemName: "arrow.up.right")
//                                    .font(.caption)
//                            }
//                            .foregroundColor(.blue)
//                        }
//                    }
//                    .padding(.horizontal)
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
    @StateObject var viewModel: CreatorViewModel
    let creator: Creator
    @State private var selectedSection: DetailSection = .about

    enum DetailSection {
        case about, videos, posts

        var title: String {
            switch self {
            case .about: "About"
            case .videos: "Videos"
            case .posts: "Posts"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                CreatorHeaderView(viewModel: viewModel, creator: creator) {
                    // onSupport callback
                }

                Picker("Section", selection: $selectedSection) {
                    ForEach([DetailSection.about, .videos, .posts], id: \.self) { section in
                        Text(section.title)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedSection {
                case .about:
                    CreatorAboutSection(viewModel: viewModel)
                case .videos:
                    CreatorVideosSection(viewModel: viewModel)
                case .posts:
                    CreatorPostsSection(viewModel: viewModel)
                }
            }
        }
        .navigationTitle(creator.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreatorHeaderView: View {
    @StateObject var viewModel: CreatorViewModel
    let creator: Creator
    let onSupport: () -> Void

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
                    StatView(title: "Posts", value: "\(viewModel.postThoughts.count)")
                    StatView(title: "Videos", value: "\(viewModel.videoThoughts.count)")
                    StatView(title: "Supporters", value: "--")
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Button {
                    // Support action
                } label: {
                    Text("Support")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .opacity(0.5)

                Button {
                    // Protect action
                } label: {
                    Text("Protect")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(.bordered)
                .disabled(true)
                .opacity(0.5)
            }
            .padding(.horizontal)
            // Coming Soon Notice
            Label("Support and Protect features will be available in an upcoming update.", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
        .background(Color(uiColor: .systemBackground))
    }
}

struct StatView: View {
    let title: String
    let value: String

    var body: some View {
        VStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
        }
    }
}

struct CreatorAboutSection: View {
    @StateObject var viewModel: CreatorViewModel
    @EnvironmentObject var sharedState: SharedState
    @State private var editedBio: String = ""
    @State private var isSubmitting = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bio")
                    .font(.headline)

                if sharedState.showCreateView {
                    TextEditor(text: $editedBio)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                    Button(action: {
                        Task {
                            await submitBlurb()
                        }
                    }) {
                        Text("Update")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(isSubmitting)
                } else {
                    Text(viewModel.bio)
                        .font(.body)
                }
            }
            .padding()

//            VStack(alignment: .leading, spacing: 8) {
//                Text("Social Media")
//                    .font(.headline)
//                    .padding(.horizontal)
//
//                ForEach(creator.socialLinks) { link in
//                    HStack {
//                        Image(systemName: link.platform.icon)
//                        Text(link.username)
//                        Spacer()
//                        Image(systemName: "arrow.up.right")
//                            .font(.caption)
//                    }
//                    .padding(.horizontal)
//                    .padding(.vertical, 8)
//                    .background(Color(.systemBackground))
//                    .cornerRadius(8)
//                }
//            }
//            .padding(.horizontal)
        }
        .onAppear {
            editedBio = viewModel.bio // Initialize editableBio with the current bio
        }
    }

    private func submitBlurb() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await viewModel.saveBio(editedBio)
        sharedState.showCreateView = false
    }
}

struct CreatorVideosSection: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            ForEach(viewModel.videoThoughts) { thought in
                VideoThoughtView(thought: thought)
                    .onTapGesture {
                        // Set selected video and switch to video tab
                        sharedState.selectedVideo = Video(
                            id: thought.id.uuidString,
                            url: URL(string: "pending-decryption://\(thought.id)")!, // Placeholder URL
                            contributors: thought.metadata.contributors,
                            description: thought.metadata.summary,
                            likes: 0,
                            comments: 0,
                            shares: 0
                        )
                        sharedState.selectedTab = .home
                        let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
                        Task {
                            try await router.processMessage(thought.nano)
                        }
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

                    Image(systemName: "paperplane.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(thought.metadata.summary)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundColor(.primary)

                Text(thought.metadata.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct CreatorPostsSection: View {
    @StateObject var viewModel: CreatorViewModel
    @EnvironmentObject var sharedState: SharedState

    var body: some View {
        LazyVStack(spacing: 16) {
            ForEach(viewModel.postThoughts) { thought in
                CreatorPostCard(post: CreatorPost(
                    id: thought.id.uuidString,
                    content: thought.metadata.summary,
                    mediaURL: nil,
                    timestamp: thought.metadata.createdAt,
                    tierAccess: .basic
                ))
                .onTapGesture {
                    // Set selected post and switch to social tab
                    sharedState.selectedThought = thought
                    sharedState.selectedTab = .social
                    let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
                    Task {
                        try await router.processMessage(thought.nano)
                    }
                }
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

// Models Extensions
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
    ]
}

// Models

@MainActor
final class CreatorViewModel: ObservableObject {
    private let client: ArkavoClient
    private let account: Account
    private let profile: Profile

    // Published properties
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var creators: [Creator] = []
    @Published private(set) var videoThoughts: [Thought] = []
    @Published private(set) var postThoughts: [Thought] = []
    @Published private(set) var supportedCreators: [Creator] = []
    @Published private(set) var messages: [Message] = []

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        loadVideoThoughts()
        loadPostThoughts()
    }

    // MARK: - Public Methods

    func loadCreators() async {
//        isLoading = true
//        do {
//            // Implementation pending
//            isLoading = false
//        } catch {
//            handleError(error)
//        }
    }

    var bio: String {
        profile.blurb ?? "No bio available"
    }

    func saveBio(_ newBio: String) async {
        isLoading = true
        defer { isLoading = false }

        profile.blurb = newBio
        do {
            try await PersistenceController.shared.saveChanges()
        } catch {
            handleError(error)
        }
    }

    func loadVideoThoughts() {
        let videoStream = account.streams.first(where: { stream in
            stream.source?.metadata.mediaType == .video
        })
        if videoStream != nil {
            videoThoughts = videoStream!.thoughts.sorted { thought1, thought2 in
                thought1.metadata.createdAt > thought2.metadata.createdAt
            }
        }
    }

    func loadSupportedCreators() async {
//        isLoading = true
//        do {
//            // Implementation pending
//            isLoading = false
//        } catch {
//            handleError(error)
//        }
    }

    func loadPostThoughts() {
        let postStream = account.streams.first(where: { stream in
            stream.source?.metadata.mediaType == .text
        })
        if postStream != nil {
            postThoughts = postStream!.thoughts.sorted { thought1, thought2 in
                thought1.metadata.createdAt > thought2.metadata.createdAt
            }
        }
    }

    func supportCreator(_: Creator, tier _: CreatorTier) async {
//        isLoading = true
//        do {
//            // Implementation pending
//            isLoading = false
//        } catch {
//            handleError(error)
//        }
    }

    func cancelSupport(for _: Creator) async {
//        isLoading = true
//        do {
//            // Implementation pending
//            isLoading = false
//        } catch {
//            handleError(error)
//        }
    }

    // MARK: - Creator Status Methods

    func isSupporting(_ creator: Creator) -> Bool {
        supportedCreators.contains { $0.id == creator.id }
    }

    func currentTier(for _: Creator) -> CreatorTier? {
        // Hardcoded for now
        CreatorTier.premium
    }

    // MARK: - Helper Methods

    private func handleError(_ error: Error) {
        self.error = error
        isLoading = false
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

// Helper Extensions
extension Int {
    var formattedDuration: String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
