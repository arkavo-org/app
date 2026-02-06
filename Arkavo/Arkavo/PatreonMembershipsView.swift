import ArkavoSocial
import SwiftData
import SwiftUI

// MARK: - Patreon Memberships View

/// Displays a list of Patreon creators the user supports
struct PatreonMembershipsView: View {
    @StateObject private var viewModel = PatreonMembershipsViewModel()
    @StateObject private var store: PatreonMembershipStore
    @State private var selectedMembership: PatreonMembership?
    @Environment(\.modelContext) private var modelContext

    init() {
        // Store will be properly initialized with modelContext in onAppear
        _store = StateObject(wrappedValue: PatreonMembershipStore())
    }

    var body: some View {
        List {
            if viewModel.memberships.isEmpty && !viewModel.isLoading {
                emptyStateSection
            } else {
                membershipsSection
            }
        }
        .listStyle(.plain)
        .navigationTitle("Supported Creators")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(item: $selectedMembership) { membership in
            NavigationStack {
                PatreonMemberContentView(
                    membership: membership,
                    store: store
                )
            }
        }
        .onAppear {
            // Refresh data when view appears
            Task {
                await loadData()
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
            Button("Retry") {
                Task {
                    await loadData()
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            // Reinitialize store with proper context if needed
            if store.totalUnreadCount == 0 && !viewModel.memberships.isEmpty {
                Task {
                    await store.refreshUnreadCounts(for: viewModel.memberships)
                }
            }
        }
    }

    private func loadData() async {
        await viewModel.loadMemberships()
        await store.refreshUnreadCounts(for: viewModel.memberships)
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "heart.slash")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)

                Text("No Active Memberships")
                    .font(.headline)

                Text("You don't have any active Patreon memberships. Support creators on Patreon to see their exclusive content here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Link(destination: URL(string: "https://www.patreon.com")!) {
                    Label("Browse Creators on Patreon", systemImage: "arrow.up.right.square")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
    }

    private var membershipsSection: some View {
        Section {
            ForEach(viewModel.memberships) { membership in
                MembershipRow(
                    membership: membership,
                    unreadCount: store.unreadCount(for: membership.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedMembership = membership
                }
            }
        } header: {
            HStack {
                Text("Active Memberships")
                    .font(.caption)
                    .textCase(.uppercase)

                Spacer()

                if store.hasUnreadContent {
                    HStack(spacing: 4) {
                        UnreadDot()
                        Text("\(store.totalUnreadCount) new")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } footer: {
            if viewModel.isLoading || store.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }
}

// MARK: - Membership Row

private struct MembershipRow: View {
    let membership: PatreonMembership
    let unreadCount: Int

    var body: some View {
        HStack(spacing: 16) {
            // Creator Avatar with badge overlay
            ZStack(alignment: .topTrailing) {
                CreatorAvatar(url: membership.creatorAvatarURL, name: membership.creatorName)

                if unreadCount > 0 {
                    UnreadBadge(count: unreadCount)
                        .offset(x: 6, y: -6)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(membership.creatorName)
                        .font(.headline)
                        .lineLimit(1)

                    if membership.isActive {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    if unreadCount > 0 {
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Label(membership.tierName ?? "Supporter", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(membership.tierAmount, format: .currency(code: "USD"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    Text(membership.status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private var statusColor: Color {
        switch membership.status.lowercased() {
        case "active patron":
            .green
        case "declined patron":
            .red
        default:
            .orange
        }
    }
}

// MARK: - Creator Avatar

private struct CreatorAvatar: View {
    let url: URL?
    let name: String

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarGradient)
                .frame(width: 56, height: 56)

            if let url {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderContent
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
            } else {
                placeholderContent
            }
        }
    }

    private var placeholderContent: some View {
        Text(String(name.prefix(1).uppercased()))
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(.white)
    }

    private var avatarGradient: LinearGradient {
        let colors: [Color] = [.orange, .red]
        return LinearGradient(
            colors: colors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - View Model

@MainActor
final class PatreonMembershipsViewModel: ObservableObject {
    @Published private(set) var memberships: [PatreonMembership] = []
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published var errorMessage: String?

    private let client: PatreonClient

    init() {
        client = PatreonClient(
            clientId: Secrets.patreonClientId,
            clientSecret: Secrets.patreonClientSecret
        )
    }

    func loadMemberships() async {
        isLoading = true
        defer { isLoading = false }

        do {
            memberships = try await client.getMyMemberships()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PatreonMembershipsView()
    }
}
