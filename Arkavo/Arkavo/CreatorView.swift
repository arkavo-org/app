import ArkavoSocial
import SwiftUI

struct CreatorView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel

    init() {
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeViewModel())
    }

    var body: some View {
        NavigationStack {
            if sharedState.selectedCreatorPublicID != nil {
                CreatorDetailView(viewModel: viewModel)
            } else {
                CreatorListView(viewModel: viewModel)
            }
        }
        .onAppear {
            sharedState.isAwaiting = viewModel.bio.isEmpty
        }
        .onDisappear {
            sharedState.selectedCreatorPublicID = nil
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
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.creators) { creator in
                    Button {
                        sharedState.selectedCreatorPublicID = creator.id.data(using: String.defaultCStringEncoding)
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
            VStack(spacing: 0) {
                CreatorHeaderView(viewModel: viewModel) {
                    // onSupport callback
                }
                .padding(.bottom)

                Picker("Section", selection: $selectedSection) {
                    ForEach([DetailSection.about, .videos, .posts], id: \.self) { section in
                        Text(section.title)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if viewModel.isProfileOwner {
                    BlockedUsersSection(viewModel: viewModel)
                        .padding(.top)
                }

                contentSection
                    .padding(.top)

                // Display Profile Public ID
                Text("Public ID: \(viewModel.profile.publicID.base58EncodedString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, InnerCircleConstants.systemMargin) // Using existing constant for consistency
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var contentSection: some View {
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

struct BlockedUsersSection: View {
    @StateObject var viewModel: CreatorViewModel

    var body: some View {
        if !viewModel.blockedProfiles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Blocked Users")
                    .font(.headline)
                    .padding(.horizontal)

                ForEach(viewModel.blockedProfiles) { blockedProfile in
                    BlockedUserRow(
                        blockedProfile: blockedProfile,
                        onUnblock: {
                            Task {
                                await viewModel.unblockProfile(blockedProfile)
                            }
                        }
                    )
                }
            }
            .padding(.vertical)
        }
    }
}

struct BlockedUserRow: View {
    let blockedProfile: BlockedProfile
    let onUnblock: () -> Void
    @State private var showingUnblockConfirmation = false
    @State private var profile: ArkavoProfile?
    @State private var isLoadingProfile = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label {
                    if let profile {
                        Text(profile.handle)
                            .lineLimit(1)
                    } else if isLoadingProfile {
                        Text("Loading profile...")
                            .foregroundStyle(.secondary)
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(blockedProfile.blockedPublicID.base58EncodedString)
                            .lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "person.slash.fill")
                        .foregroundStyle(.red)
                }

                Spacer()

                Text(blockedProfile.reportTimestamp.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Button(role: .destructive) {
                    showingUnblockConfirmation = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(.blue)
                }
            }

            if let profile {
                Text(profile.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !profile.description.isEmpty {
                    Text(profile.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .confirmationDialog(
            "Unblock User",
            isPresented: $showingUnblockConfirmation
        ) {
            Button("Unblock", role: .destructive, action: onUnblock)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to unblock this user? They will be able to interact with your content again.")
        }
        .task {
            await loadProfile()
        }
    }

    private func loadProfile() async {
        guard !isLoadingProfile else { return }

        isLoadingProfile = true
        defer { isLoadingProfile = false }

        do {
            let client = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoClient
            profile = try await client.fetchProfile(forPublicID: blockedProfile.blockedPublicID)
        } catch ArkavoError.profileNotFound {
            errorMessage = "Profile not found"
        } catch {
            errorMessage = "Error loading profile"
        }
    }
}

struct CreatorHeaderView: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel
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
                        .frame(maxWidth: .infinity)
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
        if editedBio == viewModel.bio { return }
        await viewModel.saveBio(editedBio)
        sharedState.showCreateView = false
        sharedState.isAwaiting = editedBio.isEmpty
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
                VideoThoughtView(
                    thought: thought,
                    isOwner: viewModel.isProfileOwner,
                    onView: {
                        // Set selected video and switch to video tab
                        sharedState.selectedVideo = Video.from(thought: thought)
                        sharedState.selectedTab = .home
                        let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
                        Task {
                            try await router.processMessage(thought.nano, messageId: thought.id)
                        }
                    },
                    onSend: {
                        Task {
                            await viewModel.sendVideo(thought)
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deleteVideo(thought)
                        }
                    }
                )
            }
        }
        .padding()
    }
}

struct VideoThoughtView: View {
    let thought: Thought
    let isOwner: Bool
    let onView: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

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

                    Image(systemName: "play.circle.fill") // Changed from paperplane.fill
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .onTapGesture {
                    onView()
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(thought.metadata.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isOwner {
                    HStack {
                        Button(action: onSend) {
                            Label("Broadcast", systemImage: "megaphone")
                                .font(.caption)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .confirmationDialog(
                            "Delete Video",
                            isPresented: $showingDeleteConfirmation,
                            presenting: thought
                        ) { _ in
                            Button("Delete", role: .destructive, action: onDelete)
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("Are you sure you want to delete this video? This action cannot be undone.")
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct CreatorPostsSection: View {
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: CreatorViewModel

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
        ], spacing: 16) {
            ForEach(viewModel.postThoughts) { thought in
                PostThoughtView(
                    thought: thought,
                    isOwner: viewModel.isProfileOwner,
                    onView: {
                        sharedState.selectedThought = thought
                        sharedState.selectedTab = .social
                        let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter
                        Task {
                            try await router.processMessage(thought.nano, messageId: thought.id)
                        }
                    },
                    onSend: {
                        Task {
                            await viewModel.sendPost(thought)
                        }
                    },
                    onDelete: {
                        Task {
                            await viewModel.deletePost(thought)
                        }
                    }
                )
            }
        }
        .padding()
    }
}

struct PostThoughtView: View {
    let thought: Thought
    let isOwner: Bool
    let onView: () -> Void
    let onSend: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

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

                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .onTapGesture {
                    onView()
                }
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 4) {
                Text(thought.metadata.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isOwner {
                    HStack {
                        Button(action: onSend) {
                            Label("Broadcast", systemImage: "megaphone")
                                .font(.caption)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .confirmationDialog(
                            "Delete Post",
                            isPresented: $showingDeleteConfirmation,
                            presenting: thought
                        ) { _ in
                            Button("Delete", role: .destructive, action: onDelete)
                            Button("Cancel", role: .cancel) {}
                        } message: { _ in
                            Text("Are you sure you want to delete this post? This action cannot be undone.")
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
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
final class CreatorViewModel: ViewModel, ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile

    // Published properties
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var creators: [Creator] = []
    // TODO: update to Video - the decrypted form
    @Published private(set) var videoThoughts: [Thought] = []
    // TODO: update to Post - the decrypted form
    @Published private(set) var postThoughts: [Thought] = []
    @Published private(set) var supportedCreators: [Creator] = []
    @Published private(set) var messages: [Message] = []
    @Published private(set) var blockedProfiles: [BlockedProfile] = []

    var isProfileOwner: Bool {
        if let accountProfile = account.profile {
            return profile.publicID == accountProfile.publicID
        }
        return false
    }

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        loadVideoThoughts()
        loadPostThoughts()
        Task {
            await loadBlockedProfiles()
        }
    }

    func loadBlockedProfiles() async {
        do {
            let profiles = try await PersistenceController.shared.fetchBlockedProfiles()
            blockedProfiles = profiles
        } catch {
            print("Error loading blocked profiles: \(error)")
            blockedProfiles = []
        }
    }

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
        profile.blurb ?? ""
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

    func deleteVideo(_ thought: Thought) async {
        isLoading = true
        if let videoStream = account.streams.first(where: { $0.source?.metadata.mediaType == .video }) {
            videoStream.removeThought(thought)
            // Update the UI
            loadVideoThoughts()
        }
        isLoading = false
    }

    func sendVideo(_ thought: Thought) async {
        isLoading = true
        do {
            try await client.sendMessage(thought.nano)
            isLoading = false
        } catch {
            handleError(error)
        }
    }

    func deletePost(_ thought: Thought) async {
        isLoading = true
        if let postStream = account.streams.first(where: { $0.source?.metadata.mediaType == .post }) {
            postStream.removeThought(thought)
            // Update the UI
            loadPostThoughts()
        }
        isLoading = false
    }

    func sendPost(_ thought: Thought) async {
        isLoading = true
        do {
            try await client.sendMessage(thought.nano)
            isLoading = false
        } catch {
            handleError(error)
        }
    }

    func unblockProfile(_ blockedProfile: BlockedProfile) async {
        isLoading = true
        do {
            // Remove from Core Data
            let context = PersistenceController.shared.container.mainContext
            context.delete(blockedProfile)
            try await PersistenceController.shared.saveChanges()

            // Refresh the blocked profiles list
            await loadBlockedProfiles()
        } catch {
            handleError(error)
        }
        isLoading = false
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
            stream.source?.metadata.mediaType == .post
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

// MARK: - Creator

// @available(*, deprecated, message: "The `Creator` struct is deprecated. Use `Profile` instead")
struct Creator: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let imageURL: String
    let latestUpdate: String
    let tier: String
    let socialLinks: [SocialLink]
    let notificationCount: Int
    let bio: String
}

// MARK: - SocialLink

struct SocialLink: Codable, Identifiable, Hashable {
    let id: String
    let platform: SocialPlatform
    let username: String
    let url: String
}

// MARK: - SocialPlatform

enum SocialPlatform: String, Codable {
    case twitter = "Twitter"
    case instagram = "Instagram"
    case youtube = "YouTube"
    case tiktok = "TikTok"
}
