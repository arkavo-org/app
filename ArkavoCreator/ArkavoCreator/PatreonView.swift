import ArkavoSocial
import AuthenticationServices
import SwiftUI
@preconcurrency import WebKit

struct PatreonRootView: View {
    @ObservedObject var patreonClient: PatreonClient
    @State private var isCreator: Bool = false

    var body: some View {
        Group {
            if patreonClient.isAuthenticated {
                UserIdentityView(patreonClient: patreonClient)
                    .padding(.horizontal)
                if isCreator {
                    CampaignView(patreonClient: patreonClient)
                        .padding(.horizontal)
                    PatronView(patreonClient: patreonClient)
                }
            } else {
                PatreonLoginView(patreonClient: patreonClient)
            }
        }
        .task {
            if patreonClient.isAuthenticated {
                isCreator = await patreonClient.isCreator()
            }
        }
        .onChange(of: patreonClient.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task {
                    isCreator = await patreonClient.isCreator()
                }
            } else {
                isCreator = false
            }
        }
    }
}

struct PatreonLoginView: View {
    @ObservedObject var patreonClient: PatreonClient
    @StateObject private var authManager = RedditClient(clientId: Secrets.redditClientId)
    @StateObject private var webViewPresenter = WebViewPresenter()
    @StateObject private var windowAccessor = WindowAccessor.shared
    @State private var showingError = false

    var body: some View {
        VStack(spacing: 16) {
            if patreonClient.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = patreonClient.error {
                VStack(spacing: 16) {
                    Text("Authentication Error")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Button("Login with Patreon") {
                        webViewPresenter.present(
                            url: patreonClient.authURL,
                            handleCallback: { url in
                                Task {
                                    do {
                                        try await patreonClient.handleCallback(url)
                                        webViewPresenter.dismiss()
                                    } catch {
                                        print("Patreon OAuth error: \(error)")
                                        // Keep the window open on error to show any error pages
                                    }
                                }
                            }
                        )
                    }
                    Button("Login with Reddit") {
                        webViewPresenter.present(
                            url: authManager.authURL,
                            handleCallback: { url in
                                authManager.handleCallback(url)
                                webViewPresenter.dismiss()
                            }
                        )
                    }
                }
            }
        }
        .frame(height: 600)
        .alert("Authentication Error",
               isPresented: $showingError,
               actions: {
                   Button("OK", role: .cancel) {}
               },
               message: {
                   Text("Could not start authentication. Please try again.")
               })
    }
}

// MARK: - Window Environment Key

private struct WindowKey: EnvironmentKey {
    static let defaultValue: NSWindow? = nil
}

extension EnvironmentValues {
    var window: NSWindow? {
        get { self[WindowKey.self] }
        set { self[WindowKey.self] = newValue }
    }
}

// MARK: - Window Environment Modifier

struct WindowEnvironmentModifier: ViewModifier {
    let window: NSWindow?

    func body(content: Content) -> some View {
        content.environment(\.window, window)
    }
}

extension View {
    func provideWindow(_ window: NSWindow?) -> some View {
        modifier(WindowEnvironmentModifier(window: window))
    }
}

// MARK: - ASWebAuthenticationSession Presenter

extension NSWindow: @retroactive ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        self
    }
}

public enum PatronFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case inactive = "Inactive"
    case new = "New"
}

struct PatronView: View {
    let patreonClient: PatreonClient
    @State private var searchText = ""
    @State private var selectedFilter: PatronFilter = .all
    @State private var showingMessageComposer = false
    @State private var selectedPatron: Patron?
    @State private var patrons: [Patron] = []
    @State private var isLoading = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 0) {
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
                    Spacer()
                    Button("Sign out") {
                        patreonClient.logout()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        PatronStatsView(
                            totalCount: patrons.count,
                            activeCount: patrons.filter { $0.status == .active }.count,
                            newCount: patrons.filter { $0.status == .new }.count
                        )

                        ForEach(filteredPatrons) { patron in
                            PatronCard(patron: patron) {
                                selectedPatron = patron
                            }
                            .transition(.opacity)
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await loadPatrons()
                }
            }
        }
        .navigationTitle("Patrons")
        #if !os(visionOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingMessageComposer = true }) {
                        Image(systemName: "envelope")
                    }
                }
            }
        #endif
            .sheet(isPresented: $showingMessageComposer) {
                MessageComposerView(patreonClient: patreonClient)
            }
            .sheet(item: $selectedPatron) { patron in
                PatronDetailView(patron: patron, patreonClient: patreonClient)
            }
            .task {
                await loadPatrons()
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

        // First attempt
        do {
            patrons = try await patreonClient.getMembers()
            isLoading = false
            return
        } catch PatreonError.missingCampaignId {
            // If we failed due to missing campaign ID, wait and retry once
            try? await Task.sleep(for: .seconds(1))

            // Second attempt
            do {
                patrons = try await patreonClient.getMembers()
            } catch {
                self.error = error
            }
        } catch {
            self.error = error
        }

        isLoading = false
    }
}

struct PatronDetailView: View {
    let patron: Patron
    let patreonClient: PatreonClient
    @Environment(\.dismiss) var dismiss
    @State private var showingMessageComposer = false

    var body: some View {
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
            MessageComposerView(patreonClient: patreonClient)
        }
    }
}

// MARK: - PatronStatsView

struct PatronStatsView: View {
    let totalCount: Int
    let activeCount: Int
    let newCount: Int

    var body: some View {
        VStack(spacing: 16) {
            Text("Patron Overview")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 16) {
                StatBox(title: "Total", value: "\(totalCount)")
                StatBox(title: "Active", value: "\(activeCount)")
                StatBox(title: "New", value: "\(newCount)")
            }
        }
        .padding()
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct PatronSearchBar: View {
    @Binding var searchText: String
    @Binding var selectedFilter: PatronFilter

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search patrons...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PatronFilter.allCases, id: \.self) { filter in
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
                    if let email = patron.email {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("$\(patron.tierAmount, specifier: "%.2f")/month")
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

                    Text("Since \(patron.joinDate.formatted(.dateTime.month().day().year()))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Total: $\(patron.lifetimeSupport, specifier: "%.2f")")
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
                .background(Color.gray.opacity(0.1))
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

// MARK: - Patron Model

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
                    .foregroundColor(.white)
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

struct Campaign: Identifiable, Hashable {
    let id: String
    let createdAt: Date
    let creationName: String
    let isMonthly: Bool
    let isNSFW: Bool
    let patronCount: Int
    let publishedAt: Date?
    let summary: String?
    var tiers: [PatronTier]

    // Implementing Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(createdAt)
        hasher.combine(creationName)
        hasher.combine(isMonthly)
        hasher.combine(isNSFW)
        hasher.combine(patronCount)
        hasher.combine(publishedAt)
        hasher.combine(summary)
        hasher.combine(tiers)
    }

    // Implementing Equatable
    static func == (lhs: Campaign, rhs: Campaign) -> Bool {
        lhs.id == rhs.id &&
            lhs.createdAt == rhs.createdAt &&
            lhs.creationName == rhs.creationName &&
            lhs.isMonthly == rhs.isMonthly &&
            lhs.isNSFW == rhs.isNSFW &&
            lhs.patronCount == rhs.patronCount &&
            lhs.publishedAt == rhs.publishedAt &&
            lhs.summary == rhs.summary &&
            lhs.tiers == rhs.tiers
    }
}

enum PatronStatus: String, CaseIterable {
    case active = "Active"
    case inactive = "Inactive"
    case pending = "Pending"
}

struct PatronTier: Identifiable, Hashable {
    let id: String
    var name: String
    var price: Double
    var benefits: [String]
    var patronCount: Int
    var color: Color
    var description: String

    // Implementing Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // Implementing Equatable
    static func == (lhs: PatronTier, rhs: PatronTier) -> Bool {
        lhs.id == rhs.id
    }
}

struct CampaignView: View {
    let patreonClient: PatreonClient
    @State private var campaigns: [Campaign] = []
    @State private var isLoading = false
    @State private var error: PatreonError?

    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)

                    Text("Failed to load campaigns")
                        .font(.headline)

                    Text(error.localizedDescription)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let recoverySuggestion = error.recoverySuggestion {
                        Text(recoverySuggestion)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }

                    if case let .apiError(apiError) = error {
                        Text("Error Code: \(apiError.code_name)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }

                    Button("Retry") {
                        Task {
                            await loadCampaigns()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .multilineTextAlignment(.center)
                .padding()
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            } else {
                ForEach(campaigns) { campaign in
                    CampaignCard(campaign: campaign)
                }
            }
        }
        .task {
            await loadCampaigns()
        }
    }

    private func loadCampaigns() async {
        isLoading = true
        error = nil

        do {
            let response = try await patreonClient.getCampaigns()
            if KeychainManager.getCampaignId() == nil,
               let firstCampaignId = response.data.first?.id
            {
                try KeychainManager.saveCampaignId(firstCampaignId)
            }
            campaigns = response.data.map { campaignData in
                let dateFormatter = ISO8601DateFormatter()
                return Campaign(
                    id: campaignData.id,
                    createdAt: dateFormatter.date(from: campaignData.attributes.created_at) ?? Date(),
                    creationName: campaignData.attributes.creation_name ?? "",
                    isMonthly: campaignData.attributes.is_monthly,
                    isNSFW: campaignData.attributes.is_nsfw,
                    patronCount: campaignData.attributes.patron_count,
                    publishedAt: campaignData.attributes.published_at.flatMap { dateFormatter.date(from: $0) },
                    summary: campaignData.attributes.summary,
                    tiers: []
                )
            }
        } catch {
            self.error = error as? PatreonError ?? .decodingError(error)
        }

        isLoading = false
    }
}

struct CampaignCard: View {
    let campaign: Campaign

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(campaign.id)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 16) {
                        StatLabel(
                            icon: "person.2",
                            value: "\(campaign.patronCount)",
                            label: "Patrons"
                        )

                        StatLabel(
                            icon: "calendar",
                            value: campaign.createdAt.formatted(.dateTime.month().year()),
                            label: "Created"
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

struct StatLabel: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(value)
                    .fontWeight(.medium)
            }
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct MessageComposerView: View {
    var recipient: Patron?
    let patreonClient: PatreonClient
    @Environment(\.dismiss) private var dismiss

    // Message content
    @State private var subject = ""
    @State private var messageText = ""

    // Advanced options
    @State private var isShowingAdvancedOptions = false
    @State private var scheduledDate = Date()
    @State private var selectedTier: PatronTier?

    // Template state
    @State private var isShowingTemplates = false
    @State private var isShowingPreview = false

    // Loading states
    @State private var tiers: [PatronTier] = []
    @State private var isLoadingTiers = false
    @State private var tiersError: Error?

    // Message templates
    enum MessageTemplate: String, CaseIterable, Identifiable {
        case welcome = "Welcome Message"
        case announcement = "New Content"
        case thanks = "Thank You"
        case update = "Status Update"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                // Recipients section
                if recipient == nil {
                    Section("To") {
                        recipientPicker

                        if let error = tiersError {
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Message content
                Section("Message") {
                    TextField("Subject", text: $subject)

                    TextEditor(text: $messageText)
                        .frame(minHeight: 150)
                        .overlay {
                            if messageText.isEmpty {
                                HStack {
                                    Text("Write your message...")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                            }
                        }
                }

                // Advanced options
                Section("Options") {
                    DisclosureGroup("Scheduling Options", isExpanded: $isShowingAdvancedOptions) {
                        Toggle("Schedule for Later", isOn: .init(
                            get: { scheduledDate > Date() },
                            set: { if $0 { scheduledDate = Date() + 3600 } else { scheduledDate = Date() } }
                        ))

                        if scheduledDate > Date() {
                            DatePicker(
                                "Send Date",
                                selection: $scheduledDate,
                                in: Date()...,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        }
                    }
                }
            }
            .navigationTitle(recipient != nil ? "Message to \(recipient!.name)" : "New Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("Send") {
                        sendMessage()
                    }
                    .disabled(subject.isEmpty || messageText.isEmpty)
                }

                ToolbarItemGroup {
                    Button {
                        isShowingTemplates.toggle()
                    } label: {
                        Label("Templates", systemImage: "doc.text")
                    }

                    Button {
                        isShowingPreview.toggle()
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                }
            }
            .sheet(isPresented: $isShowingTemplates) {
                NavigationStack {
                    List(MessageTemplate.allCases) { template in
                        Button {
                            applyTemplate(template)
                            isShowingTemplates = false
                        } label: {
                            Text(template.rawValue)
                        }
                    }
                    .navigationTitle("Message Templates")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isShowingTemplates = false
                            }
                        }
                    }
                }
                .frame(width: 300, height: 400)
            }
            .sheet(isPresented: $isShowingPreview) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(subject)
                                .font(.headline)

                            Text(messageText)
                                .font(.body)
                        }
                        .padding()
                    }
                    .navigationTitle("Message Preview")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isShowingPreview = false
                            }
                        }
                    }
                }
                .frame(width: 400, height: 400)
            }
        }
        .frame(width: 600, height: 500)
        .task {
            await loadTiers()
        }
    }

    private var recipientPicker: some View {
        Group {
            if isLoadingTiers {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading tiers...")
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Recipients", selection: $selectedTier) {
                    Text("All Patrons")
                        .tag(nil as PatronTier?)
                    ForEach(tiers) { tier in
                        Text("\(tier.name) ($\(String(format: "%.2f", tier.price)))")
                            .tag(tier as PatronTier?)
                    }
                }
            }
        }
    }

    private func loadTiers() async {
        isLoadingTiers = true
        tiersError = nil

        do {
            let patreonTiers = try await patreonClient.getTiers()
            // Convert PatreonTier to PatronTier
            tiers = patreonTiers.map { tier in
                PatronTier(
                    id: tier.id,
                    name: tier.name,
                    price: tier.amount,
                    benefits: [],
                    patronCount: tier.patronCount ?? 0,
                    color: .blue,
                    description: tier.description ?? ""
                )
            }
        } catch {
            tiersError = error
        }

        isLoadingTiers = false
    }

    private func applyTemplate(_ template: MessageTemplate) {
        switch template {
        case .welcome:
            subject = "Welcome to My Patreon!"
            messageText = "Thank you for becoming a patron! Here's what you can expect..."
        case .announcement:
            subject = "New Content Available"
            messageText = "I've just released new exclusive content..."
        case .thanks:
            subject = "Thank You for Your Support"
            messageText = "I wanted to take a moment to thank you..."
        case .update:
            subject = "Project Status Update"
            messageText = "Here's the latest update on..."
        }
    }

    private func sendMessage() {
        // Implement message sending logic
        dismiss()
    }
}
