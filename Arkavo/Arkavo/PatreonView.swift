import SwiftUI
@preconcurrency import WebKit

struct PatreonRootView: View {
    @StateObject private var authViewModel: PatreonAuthViewModel
    let client: PatreonClient

    init(client: PatreonClient, config: PatreonConfig) {
        self.client = client
        _authViewModel = StateObject(wrappedValue: PatreonAuthViewModel(client: client, config: config))
    }

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                PatronManagementView(patreonClient: client)
            } else {
                PatreonLoginView(viewModel: authViewModel)
            }
        }
    }
}

// MARK: - WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    var parent: WebView
    var viewModel: PatreonAuthViewModel

    init(_ parent: WebView, viewModel: PatreonAuthViewModel) {
        self.parent = parent
        self.viewModel = viewModel
    }

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           url.scheme == "arkavo",
           let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
           .queryItems?
           .first(where: { $0.name == "code" })?
           .value
        {
            // Handle the OAuth callback
            Task {
                await viewModel.handleAuthCode(code)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - WebView Representative

struct WebView: NSViewRepresentable {
    let viewModel: PatreonAuthViewModel
    let url: URL

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(self, viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}

// MARK: - Patreon Login View

struct PatreonLoginView: View {
    @StateObject var viewModel: PatreonAuthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Text("Authentication Error")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        viewModel.startOAuthFlow()
                    }
                }
                .padding()
            } else if let url = viewModel.authURL {
                WebView(viewModel: viewModel, url: url)
            } else {
                VStack(spacing: 16) {
                    Text("Connect with Patreon")
                        .font(.title2)
                    Button("Start Authentication") {
                        viewModel.startOAuthFlow()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(width: 800, height: 600)
        .onChange(of: viewModel.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                dismiss()
            }
        }
    }
}

// struct PatreonLoginView: View {
//    @ObservedObject var viewModel: PatreonAuthViewModel
//
//    var body: some View {
//        VStack(spacing: 24) {
//            Text("Manage Your Patrons")
//                .font(.title)
//                .fontWeight(.bold)
//
//            Text("Connect your Patreon account to get started")
//                .font(.subheadline)
//                .foregroundColor(.secondary)
//
//            if viewModel.isLoading {
//                ProgressView()
//            } else {
//                Button(action: {
//                    viewModel.startOAuthFlow()
//                }) {
//                    HStack {
//                        Image(systemName: "lock.shield")
//                        Text("Login with Patreon")
//                    }
//                    .frame(width: 200)
//                }
//                .buttonStyle(.borderedProminent)
//                .tint(.arkavoBrand)
//            }
//
//            if let error = viewModel.error {
//                Text(error.localizedDescription)
//                    .font(.caption)
//                    .foregroundColor(.red)
//                    .multilineTextAlignment(.center)
//                    .frame(maxWidth: 300)
//            }
//        }
//        .padding()
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
//    }
// }

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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        UserIdentityView(patreonClient: patreonClient)
                            .padding(.horizontal)

                        CampaignView(patreonClient: patreonClient)
                            .padding(.horizontal)

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingMessageComposer = true }) {
                    Image(systemName: "envelope")
                }
            }
        }
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

        do {
            patrons = try await patreonClient.getMembers()
        } catch {
            self.error = error
        }

        isLoading = false
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
        .background(Color(.textBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
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

// MARK: - Patron Model

struct Patron: Identifiable {
    let id: String
    let name: String
    let email: String?
    let avatarURL: URL?
    let status: PatronStatus
    let tierAmount: Double
    let lifetimeSupport: Double
    let joinDate: Date
    let url: URL?

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

struct PatronManagementView_Previews: PreviewProvider {
    static let patreonService = PatreonService()
    static var previews: some View {
        VStack(spacing: 20) {
            PatronManagementView(patreonClient: patreonService.client)
        }
        .padding()
        .background(Color.arkavoBackground)
    }
}

// Preview Helper
extension Patron {
    static let previewPatron = Patron(
        id: "1",
        name: "John Doe",
        email: "a@a.co", avatarURL: nil,
        status: .active,
        tierAmount: 25.0,
        lifetimeSupport: 1.1, joinDate: Date().addingTimeInterval(-30 * 86400),
        url: nil
    )
}

struct Campaign: Identifiable {
    let id: String
    let createdAt: Date
    let creationName: String
    let isMonthly: Bool
    let isNSFW: Bool
    let patronCount: Int
    let publishedAt: Date?
    let summary: String?
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
                    summary: campaignData.attributes.summary
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
    @Environment(\.dismiss) var dismiss

    @State private var subject = ""
    @State private var messageText = ""
    @State private var selectedTemplate: MessageTemplate?
    @State private var showingTemplates = false
    @State private var showingPreview = false
    @State private var isScheduling = false
    @State private var scheduledDate: Date = .init()
    @State private var selectedTier: PatreonTier?

    // States for data loading
    @State private var tiers: [PatreonTier] = []
    @State private var isLoadingTiers = false
    @State private var tiersError: Error?

    enum MessageTemplate: String, CaseIterable {
        case welcome = "Welcome Message"
        case announcement = "New Content"
        case thanks = "Thank You"
        case update = "Status Update"
    }

    var body: some View {
        Form {
            // Recipient Section
            if recipient == nil {
                Section("Recipients") {
                    HStack {
                        Text("To:")
                            .foregroundColor(.secondary)
                        Text(selectedTier?.name ?? "All Patrons")
                            .fontWeight(.medium)
                    }

                    if isLoadingTiers {
                        ProgressView("Loading tiers...")
                    } else if let error = tiersError {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Failed to load tiers")
                                .foregroundColor(.red)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Retry") {
                                Task {
                                    await loadTiers()
                                }
                            }
                        }
                    } else {
                        Menu {
                            Button("All Patrons") {
                                selectedTier = nil
                            }
                            ForEach(tiers) { tier in
                                Button("\(tier.name) ($\(String(format: "%.2f", tier.amount)))") {
                                    selectedTier = tier
                                }
                            }
                        } label: {
                            Label("Filter by Tier", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
            }

            // Message Content Section
            Section("Message") {
                TextField("Subject", text: $subject)

                ZStack(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text("Write your message...")
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                    }
                    TextEditor(text: $messageText)
                        .frame(minHeight: 100)
                }

                HStack {
                    Button {
                        showingTemplates.toggle()
                    } label: {
                        Label("Templates", systemImage: "doc.text")
                    }

                    Spacer()

                    Button {
                        showingPreview.toggle()
                    } label: {
                        Label("Preview", systemImage: "eye")
                    }
                }
            }

            // Scheduling Section
            Section {
                Toggle("Schedule Message", isOn: $isScheduling)

                if isScheduling {
                    DatePicker(
                        "Send Date",
                        selection: $scheduledDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }
            }

            // Action Buttons Section
            Section {
                HStack {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                    }

                    Button {
                        sendMessage()
                    } label: {
                        Text(isScheduling ? "Schedule" : "Send")
                            .frame(maxWidth: .infinity)
                            .bold()
                    }
                    .disabled(subject.isEmpty || messageText.isEmpty)
                }
            }
        }
        .navigationTitle(recipient != nil ? "Message to \(recipient!.name)" : "New Message")
        .task {
            await loadTiers()
        }
    }

    private func loadTiers() async {
        isLoadingTiers = true
        tiersError = nil

        do {
            tiers = try await patreonClient.getTiers()
        } catch {
            tiersError = error
        }

        isLoadingTiers = false
    }

    private func sendMessage() {
        // Implement message sending logic
        dismiss()
    }
}

// Updated preview provider
struct MessageComposerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview with recipient
            MessageComposerView(
                recipient: Patron.previewPatron,
                patreonClient: PatreonClient(config: .preview)
            )
            .previewDisplayName("With Recipient")

            // Preview without recipient (broadcast message)
            MessageComposerView(
                recipient: nil,
                patreonClient: PatreonClient(config: .preview)
            )
            .previewDisplayName("Broadcast Message")
        }
    }
}

extension PatreonConfig {
    static let preview = PatreonConfig(
        clientId: ProcessInfo.processInfo.environment["PATREON_CLIENT_ID"] ?? "preview-client-id",
        clientSecret: ProcessInfo.processInfo.environment["PATREON_CLIENT_SECRET"] ?? "preview-secret",
        creatorAccessToken: ProcessInfo.processInfo.environment["PATREON_ACCESS_TOKEN"] ?? "preview-token",
        creatorRefreshToken: ProcessInfo.processInfo.environment["PATREON_REFRESH_TOKEN"] ?? "preview-refresh-token",
        campaignId: ProcessInfo.processInfo.environment["PATREON_CAMPAIGN_ID"] ?? "preview-campaign"
    )
}
