import ArkavoSocial
import SwiftUI

// MARK: - Patreon Memberships View

/// Displays a list of Patreon creators the user supports
struct PatreonMembershipsView: View {
    @StateObject private var viewModel = PatreonMembershipsViewModel()
    @State private var selectedMembership: PatreonMembership?

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
            await viewModel.loadMemberships()
        }
        .refreshable {
            await viewModel.loadMemberships()
        }
        .sheet(item: $selectedMembership) { membership in
            NavigationStack {
                PatreonMemberContentView(membership: membership)
            }
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
            Button("Retry") {
                Task {
                    await viewModel.loadMemberships()
                }
            }
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred")
        }
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
                MembershipRow(membership: membership)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedMembership = membership
                    }
            }
        } header: {
            Text("Active Memberships")
                .font(.caption)
                .textCase(.uppercase)
        } footer: {
            if viewModel.isLoading {
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

    var body: some View {
        HStack(spacing: 16) {
            // Creator Avatar
            CreatorAvatar(url: membership.creatorAvatarURL, name: membership.creatorName)

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
