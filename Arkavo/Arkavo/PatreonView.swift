import SwiftUI

struct PatronManagementView: View {
    let patreonClient: PatreonClient
    @State private var searchText = ""
    @State private var selectedFilter: PatronFilter = .all
    @State private var showingMessageComposer = false
    @State private var selectedPatron: Patron?
    @State private var patrons: [Patron] = []
    @State private var isLoading = false
    @State private var error: Error?

    enum PatronFilter: String, CaseIterable {
        case all = "All"
        case active = "Active"
        case inactive = "Inactive"
        case new = "New"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filter Bar
                PatronSearchBar(searchText: $searchText, selectedFilter: $selectedFilter)
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    VStack {
                        Text("Error loading patrons")
                            .font(.headline)
                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task {
                                await loadPatrons()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Main Content
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            UserIdentityView(patreonClient: patreonClient)
                                .padding(.horizontal)
                            PatronStatsView()

                            ForEach(filteredPatrons) { patron in
                                PatronCard(patron: patron) {
                                    selectedPatron = patron
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Patrons")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingMessageComposer = true }) {
                        Image(systemName: "envelope")
                    }
                }
            }
            .sheet(isPresented: $showingMessageComposer) {
                MessageComposerView()
            }
            .sheet(item: $selectedPatron) { patron in
                PatronDetailView(patron: patron)
            }
            .task {
                await loadPatrons()
            }
        }
    }

    private var filteredPatrons: [Patron] {
        let filtered = patrons.filter { patron in
            if searchText.isEmpty { return true }
            return patron.name.localizedCaseInsensitiveContains(searchText)
        }

        switch selectedFilter {
        case .all:
            return filtered
        case .active:
            return filtered.filter { $0.status == .active }
        case .inactive:
            return filtered.filter { $0.status == .inactive }
        case .new:
            return filtered.filter { $0.status == .new }
        }
    }

    private func loadPatrons() async {
        isLoading = true
        error = nil

//        do {
//            let members = try await patreonClient.getCampaignMembers()
//            patrons = members.map { member in
//                Patron(
//                    id: member.id,
//                    name: member.attributes.fullName,
//                    avatarURL: nil, // Would need to be fetched from included relationships
//                    status: patronStatus(from: member.attributes.patronStatus),
//                    tierAmount: Double(member.attributes.currentlyEntitledAmountCents) / 100.0,
//                    joinDate: ISO8601DateFormatter().date(from: member.attributes.lastChargeDate ?? "") ?? Date()
//                )
//            }
//        } catch {
//            self.error = error
//        }

        isLoading = false
    }

    private func patronStatus(from status: String?) -> Patron.PatronStatus {
        guard let status else { return .inactive }
        switch status.lowercased() {
        case "active_patron": return .active
        case "declined_patron": return .inactive
        case "former_patron": return .inactive
        default: return .new
        }
    }
}

struct PatronSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedFilter: PatronManagementView.PatronFilter

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search patrons...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PatronManagementView.PatronFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            title: filter.rawValue,
                            isSelected: selectedFilter == filter
                        ) {
                            selectedFilter = filter
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PatronStatsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Patron Overview")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                StatBox(title: "Total", value: "1,234")
                StatBox(title: "Active", value: "987")
                StatBox(title: "This Month", value: "+45")
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PatronCard: View {
    let patron: Patron
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                PatronAvatar(url: patron.avatarURL)

                VStack(alignment: .leading, spacing: 4) {
                    Text(patron.name)
                        .font(.headline)
                    Text("$\(patron.tierAmount)/month")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(patron.status.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(patron.status.color.opacity(0.1))
                        .foregroundColor(patron.status.color)
                        .cornerRadius(8)

                    Text("Since \(patron.joinDate, formatter: dateFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()
}

struct PatronDetailView: View {
    let patron: Patron
    @Environment(\.dismiss) var dismiss
    @State private var showingMessageComposer = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    PatronHeaderView(patron: patron)

                    PatronActivityView(patron: patron)

                    PatronEngagementView(patron: patron)
                }
                .padding()
            }
            .navigationTitle("Patron Details")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingMessageComposer = true }) {
                        Image(systemName: "envelope")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingMessageComposer) {
                MessageComposerView(recipient: patron)
            }
        }
    }
}

// Supporting Views and Models

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.arkavoBrand : Color.gray.opacity(0.1))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

struct PatronAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.gray.opacity(0.2)
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }
}

struct MessageComposerView: View {
    var recipient: Patron?
    @Environment(\.dismiss) var dismiss
    @State private var messageText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let recipient {
                    HStack {
                        Text("To:")
                        Text(recipient.name)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                TextEditor(text: $messageText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            .navigationTitle("New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Send") {
                        // Send message logic
                        dismiss()
                    }
                    .disabled(messageText.isEmpty)
                }
            }
        }
    }
}

// Models
struct Patron: Identifiable {
    let id: String
    let name: String
    let avatarURL: URL?
    let status: PatronStatus
    let tierAmount: Double
    let joinDate: Date

    enum PatronStatus: String {
        case active = "Active"
        case inactive = "Inactive"
        case new = "New"

        var color: Color {
            switch self {
            case .active: .green
            case .inactive: .red
            case .new: .blue
            }
        }
    }
}

struct PatronHeaderView: View {
    let patron: Patron

    var body: some View {
        VStack(spacing: 16) {
            PatronAvatar(url: patron.avatarURL)
                .frame(width: 80, height: 80)

            VStack(spacing: 4) {
                Text(patron.name)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("$\(patron.tierAmount, specifier: "%.2f")/month")
                    .font(.headline)
                    .foregroundColor(.arkavoBrand)
            }

            HStack(spacing: 24) {
                StatPill(title: "Months", value: "12")
                StatPill(title: "Total", value: "$240")
                StatPill(title: "Status", value: patron.status.rawValue)
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PatronActivityView: View {
    let patron: Patron
    @State private var selectedTimeRange = 1
    let timeRanges = ["Week", "Month", "Year"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity")
                .font(.headline)

            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(0 ..< timeRanges.count, id: \.self) { index in
                    Text(timeRanges[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 12) {
                PatronActivityRow(date: Date(), action: "Commented", content: "Great work on the latest video!")
                PatronActivityRow(date: Date().addingTimeInterval(-86400), action: "Liked", content: "Behind the scenes photo")
                PatronActivityRow(date: Date().addingTimeInterval(-172_800), action: "Downloaded", content: "Project files")
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct UserIdentityView: View {
    let patreonClient: PatreonClient
    @State private var identity: UserIdentity?
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView()
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load creator profile")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task {
                            await loadIdentity()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else if let identity {
                creatorProfileView(identity: identity)
            }
        }
        .task {
            await loadIdentity()
        }
    }

    private func creatorProfileView(identity: UserIdentity) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                AsyncImage(url: URL(string: identity.data.attributes.imageUrl ?? "")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(identity.data.attributes.fullName)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let email = identity.data.attributes.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let socials = identity.data.attributes.socialConnections {
                socialConnectionsView(socials)
            }

            Divider()

            // Memberships section if needed
            if !identity.data.relationships.memberships.data.isEmpty {
                Text("Active Memberships: \(identity.data.relationships.memberships.data.count)")
                    .font(.headline)
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    private func socialConnectionsView(_ socials: SocialConnections) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)

            HStack(spacing: 16) {
                if let discord = socials.discord {
                    socialButton("discord", URL(string: discord.url ?? ""))
                }
                if let twitter = socials.twitter {
                    socialButton("twitter", URL(string: twitter.url ?? ""))
                }
                if let youtube = socials.youtube {
                    socialButton("youtube", URL(string: youtube.url ?? ""))
                }
                if let twitch = socials.twitch {
                    socialButton("twitch", URL(string: twitch.url ?? ""))
                }
            }
        }
    }

    private func socialButton(_ platform: String, _: URL?) -> some View {
        Image(platform)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .foregroundColor(.secondary)
            .opacity(0.5)
    }

    private func loadIdentity() async {
        isLoading = true
        error = nil
        do {
            // Use the creator access token from the client's config
            identity = try await patreonClient.getUserIdentity()
        } catch {
            self.error = error
        }
        isLoading = false
    }
}

struct PatronEngagementView: View {
    let patron: Patron

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Engagement")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                EngagementCard(title: "Comments", value: "24", trend: "+3")
                EngagementCard(title: "Likes", value: "156", trend: "+12")
                EngagementCard(title: "Downloads", value: "45", trend: "+5")
                EngagementCard(title: "Share Rate", value: "8%", trend: "+2%")
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// Supporting Views

struct StatPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

struct PatronActivityRow: View {
    let date: Date
    let action: String
    let content: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(date, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(action)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct EngagementCard: View {
    let title: String
    let value: String
    let trend: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            HStack {
                Image(systemName: trend.hasPrefix("+") ? "arrow.up.right" : "arrow.down.right")
                Text(trend)
            }
            .font(.caption)
            .foregroundColor(trend.hasPrefix("+") ? .green : .red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }
}

// Preview Providers

struct PatronHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        PatronHeaderView(patron: .previewPatron)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}

struct PatronActivityView_Previews: PreviewProvider {
    static var previews: some View {
        PatronActivityView(patron: .previewPatron)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}

struct PatronEngagementView_Previews: PreviewProvider {
    static var previews: some View {
        PatronEngagementView(patron: .previewPatron)
            .padding()
            .previewLayout(.sizeThatFits)
    }
}

// struct PatronManagementView_Previews: PreviewProvider {
//    static let patreonService = PatreonService()
//    static var previews: some View {
//        VStack(spacing: 20) {
//            PatronManagementView(patreonClient: patreonService.client)
//        }
//        .padding()
//        .background(Color.arkavoBackground)
//    }
// }

// Preview Helper
extension Patron {
    static let previewPatron = Patron(
        id: "1",
        name: "John Doe",
        avatarURL: nil,
        status: .active,
        tierAmount: 25.0,
        joinDate: Date().addingTimeInterval(-30 * 86400)
    )
}
