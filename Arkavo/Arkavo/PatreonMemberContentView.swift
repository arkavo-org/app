import ArkavoSocial
import SwiftUI

// MARK: - Patreon Member Content View

/// Displays exclusive member-only posts from a Patreon creator
struct PatreonMemberContentView: View {
    let membership: PatreonMembership
    @StateObject private var viewModel: PatreonMemberContentViewModel
    @Environment(\.dismiss) private var dismiss

    init(membership: PatreonMembership) {
        self.membership = membership
        _viewModel = StateObject(wrappedValue: PatreonMemberContentViewModel(membership: membership))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                membershipHeader

                if viewModel.isLoading && viewModel.posts.isEmpty {
                    loadingSection
                } else if viewModel.posts.isEmpty {
                    emptyPostsSection
                } else {
                    postsSection
                }
            }
            .padding(.vertical)
        }
        .navigationTitle(membership.creatorName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Link(destination: membership.campaignURL ?? URL(string: "https://www.patreon.com")!) {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        }
        .task {
            await viewModel.loadPosts()
        }
        .refreshable {
            await viewModel.loadPosts()
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "Failed to load posts")
        }
    }

    private var membershipHeader: some View {
        VStack(spacing: 12) {
            // Creator Avatar
            ZStack {
                Circle()
                    .fill(avatarGradient)
                    .frame(width: 80, height: 80)

                if let avatarURL = membership.creatorAvatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(String(membership.creatorName.prefix(1).uppercased()))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                } else {
                    Text(String(membership.creatorName.prefix(1).uppercased()))
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
            }

            VStack(spacing: 4) {
                Text(membership.creatorName)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Label(membership.tierName ?? "Supporter", systemImage: "star.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    Text("•")
                        .foregroundStyle(.secondary)

                    Text(membership.tierAmount, format: .currency(code: "USD"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(membership.isActive ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)

                    Text(membership.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
        .padding(.horizontal)
    }

    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading exclusive content...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 60)
    }

    private var emptyPostsSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.rectangle.stack")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Exclusive Content Yet")
                .font(.headline)

            Text("This creator hasn't posted any member-only content yet. Check back later!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 60)
    }

    private var postsSection: some View {
        VStack(spacing: 16) {
            ForEach(viewModel.posts) { post in
                PostCard(post: post, userTierAmount: membership.tierAmount)
            }
        }
        .padding(.horizontal)
    }

    private var avatarGradient: LinearGradient {
        LinearGradient(
            colors: [.orange, .red],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Post Card

private struct PostCard: View {
    let post: PatreonPost
    let userTierAmount: Double
    @State private var isExpanded = false
    @State private var showingShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Post Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if !post.isPublic {
                            Label("Members Only", systemImage: "lock.fill")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                        }

                        if let minTier = post.minTierAmount {
                            Label("\(minTier, format: .currency(code: "USD"))+", systemImage: "star.fill")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(userTierAmount >= minTier ? .green : .red)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    (userTierAmount >= minTier ? Color.green : Color.red)
                                        .opacity(0.15)
                                )
                                .cornerRadius(4)
                        }
                    }

                    Text(post.publishedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    if let url = post.url {
                        Button {
                            showingShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }

                        Link(destination: url) {
                            Label("Open in Patreon", systemImage: "arrow.up.right.square")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
            }

            // Post Title
            Text(post.title)
                .font(.headline)
                .lineLimit(isExpanded ? nil : 2)

            // Post Image (if available)
            if let imageURL = post.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay(ProgressView())
                    case let .success(image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipped()
                            .cornerRadius(12)
                    case .failure:
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Post Content
            if let content = post.content, !content.isEmpty {
                Text(content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 3)
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }
            }

            // Post Stats
            HStack(spacing: 16) {
                Label("\(post.likeCount)", systemImage: "heart")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label("\(post.commentCount)", systemImage: "bubble.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let url = post.url {
                    Link(destination: url) {
                        Text("View on Patreon")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 2)
        .sheet(isPresented: $showingShareSheet) {
            if let url = post.url {
                ShareSheet(activityItems: [url])
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class PatreonMemberContentViewModel: ObservableObject {
    let membership: PatreonMembership
    @Published private(set) var posts: [PatreonPost] = []
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?

    private let client: PatreonClient

    init(membership: PatreonMembership) {
        self.membership = membership
        client = PatreonClient(
            clientId: Secrets.patreonClientId,
            clientSecret: Secrets.patreonClientSecret
        )
    }

    func loadPosts() async {
        guard !membership.campaignId.isEmpty else {
            errorMessage = "Invalid campaign ID"
            showError = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            posts = try await client.getPosts(campaignId: membership.campaignId)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PatreonMemberContentView(
            membership: PatreonMembership(
                id: "preview",
                creatorName: "Preview Creator",
                creatorAvatarURL: nil,
                campaignId: "campaign123",
                tierName: "Gold Tier",
                tierAmount: 10.0,
                status: "Active Patron",
                pledgeCadence: 1,
                campaignURL: URL(string: "https://patreon.com"),
                isActive: true
            )
        )
    }
}
