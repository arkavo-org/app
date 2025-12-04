import ArkavoKit
import ArkavoKit
import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedSection: NavigationSection = UserDefaults.standard.loadSelectedTab()
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) var colorScheme
    @StateObject var patreonClient: PatreonClient
    @StateObject var redditClient: RedditClient
    @StateObject var micropubClient: MicropubClient
    @StateObject var blueskyClient: BlueskyClient
    @StateObject var youtubeClient: YouTubeClient
    @StateObject private var twitchClient = TwitchAuthClient(
        clientId: Secrets.twitchClientId,
        clientSecret: Secrets.twitchClientSecret
    )

    var body: some View {
        NavigationSplitView {
            Sidebar(
                selectedSection: $selectedSection,
                patreonClient: patreonClient,
                redditClient: redditClient,
                blueskyClient: blueskyClient,
                youtubeClient: youtubeClient
            )
        } detail: {
            SectionContainer(
                selectedSection: selectedSection,
                patreonClient: patreonClient,
                redditClient: redditClient,
                micropubClient: micropubClient,
                blueskyClient: blueskyClient,
                youtubeClient: youtubeClient,
                twitchClient: twitchClient
            )
            .navigationTitle(selectedSection.rawValue)
            .navigationSubtitle(selectedSection.subtitle)
            .toolbar {
                if patreonClient.isAuthenticated || redditClient.isAuthenticated || youtubeClient.isAuthenticated || micropubClient.isAuthenticated ||
                    blueskyClient.isAuthenticated || twitchClient.isAuthenticated
                {
                    ToolbarItemGroup {
                        Button(action: {
                            selectedSection = .social
                        }) {
                            Image(systemName: "bell")
                        }
                        .help("Notifications")
                        Menu {
                            if patreonClient.isAuthenticated {
                                Button("Patreon Sign Out", action: {
                                    patreonClient.logout()
                                })
                            }
                            if redditClient.isAuthenticated {
                                Button("Reddit Sign Out", action: {
                                    redditClient.logout()
                                })
                            }
                            if micropubClient.isAuthenticated {
                                Button("Micro.blog Sign Out", action: {
                                    micropubClient.logout()
                                })
                            }
                            if blueskyClient.isAuthenticated {
                                Button("Bluesky Sign Out", action: {
                                    blueskyClient.logout()
                                })
                            }
                            if youtubeClient.isAuthenticated {
                                Button("YouTube Sign Out", action: {
                                    youtubeClient.logout()
                                })
                            }
                            if twitchClient.isAuthenticated {
                                Button("Twitch Sign Out", action: {
                                    twitchClient.logout()
                                })
                            }
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
        }
        .environmentObject(appState)
        .onChange(of: selectedSection) { _, newValue in
            UserDefaults.standard.saveSelectedTab(newValue)
        }
    }
}

// MARK: - Navigation Section Updates

enum NavigationSection: String, CaseIterable, Codable {
    case dashboard = "Dashboard"
    case studio = "Studio"
    case library = "Library"
    case workflow = "Workflow"
    case patrons = "Patron Management"
    case protection = "Protection"
    case social = "Marketing"
    case settings = "Settings"

    static func availableSections(isCreator: Bool) -> [NavigationSection] {
        if isCreator {
            allCases
        } else {
            allCases.filter { $0 != .patrons }
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .studio: "video.bubble.left.fill"
        case .library: "rectangle.stack.badge.play"
        case .workflow: "doc.badge.plus"
        case .patrons: "person.2.circle"
        case .protection: "lock.shield"
        case .social: "square.and.arrow.up.circle"
        case .settings: "gear"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Overview"
        case .studio: "Record, Stream & Create"
        case .library: "Your Recorded Videos"
        case .workflow: "Manage Your Content"
        case .patrons: "Manage Your Community"
        case .protection: "Protection"
        case .social: "Share Your Content"
        case .settings: "App Settings"
        }
    }
}

// MARK: - Dashboard Section Item

struct DashboardSectionItem: Identifiable {
    let id: String
    let title: String
    let isAuthenticated: Bool
    let hasActiveContent: Bool
    let content: AnyView

    var sortPriority: Int {
        if !isAuthenticated { return 2 }  // Not authenticated: lowest priority
        if hasActiveContent { return 0 }  // Active content: highest priority
        return 1  // Authenticated but no active content: middle priority
    }
}

// MARK: - Section Container View

struct SectionContainer: View {
    let selectedSection: NavigationSection
    @ObservedObject var patreonClient: PatreonClient
    @ObservedObject var redditClient: RedditClient
    @ObservedObject var micropubClient: MicropubClient
    @ObservedObject var blueskyClient: BlueskyClient
    @ObservedObject var youtubeClient: YouTubeClient
    @ObservedObject var twitchClient: TwitchAuthClient
    @StateObject private var webViewPresenter = WebViewPresenter()
    @Namespace private var animation
    @State private var arkavoAccountName = ""

    private var arkavoAuthState: ArkavoAuthState { ArkavoAuthState.shared }

    // Helper to determine if a platform has active content
    private func hasActiveContent(for platform: String) -> Bool {
        switch platform {
        case "Twitch":
            return twitchClient.isLive
        case "YouTube":
            // Could check for recent uploads if API provided that data
            return false
        case "Patreon":
            // Could check for recent posts if API provided that data
            return false
        case "Reddit":
            // Could check for unread notifications if API provided that data
            return false
        default:
            return false
        }
    }

    // MARK: - Individual Platform Dashboard Views

    private var twitchDashboardContent: some View {
        Group {
            if twitchClient.isAuthenticated, let username = twitchClient.username {
                HStack(alignment: .top, spacing: 16) {
                    // Profile Image
                    if let profileImageURL = twitchClient.profileImageURL,
                       let url = URL(string: profileImageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundColor(.purple)
                            .frame(width: 60, height: 60)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        // Username and Status
                        HStack {
                            Text(username)
                                .font(.headline)

                            if twitchClient.isLive {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text("LIVE")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.red)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }

                        // Follower Count
                        if let followerCount = twitchClient.followerCount {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.caption)
                                Text("\(formatNumber(followerCount)) followers")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.secondary)
                        }

                        // Viewer Count (when live)
                        if twitchClient.isLive, let viewerCount = twitchClient.viewerCount {
                            HStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.caption)
                                Text("\(formatNumber(viewerCount)) viewers")
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                        }

                        // Channel Description
                        if let description = twitchClient.channelDescription, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        // Refresh Button
                        Button {
                            Task {
                                await twitchClient.refreshChannelData()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            } else {
                Button("Login with Twitch") {
                    webViewPresenter.present(
                        url: twitchClient.authorizationURL,
                        handleCallback: { url in
                            Task {
                                do {
                                    try await twitchClient.handleCallback(url)
                                    webViewPresenter.dismiss()
                                } catch {
                                    print("Twitch OAuth error: \(error)")
                                }
                            }
                        }
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var youtubeDashboardContent: some View {
        Group {
            if youtubeClient.isAuthenticated {
                if let channelInfo = youtubeClient.channelInfo {
                    VStack(alignment: .leading) {
                        Text(channelInfo.title)
                            .font(.headline)
                        Text("\(channelInfo.subscriberCount) subscribers")
                        Text("\(channelInfo.videoCount) videos")
                    }
                }
            } else {
                VStack(spacing: 12) {
                    if youtubeClient.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Login with YouTube") {
                            Task {
                                do {
                                    try await youtubeClient.authenticateWithLocalServer()
                                } catch YouTubeError.userCancelled {
                                    // User cancelled, no action needed
                                } catch {
                                    print("YouTube OAuth error: \(error)")
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if let error = youtubeClient.error {
                            Text(error.localizedDescription)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var patreonDashboardContent: some View {
        Group {
            if patreonClient.isAuthenticated {
                PatreonRootView(patreonClient: patreonClient)
            } else {
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
                                }
                            }
                        }
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var redditDashboardContent: some View {
        Group {
            if redditClient.isAuthenticated {
                RedditRootView(redditClient: redditClient)
            } else {
                Button("Login with Reddit") {
                    webViewPresenter.present(
                        url: redditClient.authURL,
                        handleCallback: { url in
                            redditClient.handleCallback(url)
                            webViewPresenter.dismiss()
                        }
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var microblogDashboardContent: some View {
        Group {
            if micropubClient.isAuthenticated {
                MicroblogRootView(micropubClient: micropubClient)
            } else {
                Button("Login with Micro.blog") {
                    webViewPresenter.present(
                        url: micropubClient.authURL,
                        handleCallback: { url in
                            Task {
                                do {
                                    try await micropubClient.handleCallback(url)
                                    webViewPresenter.dismiss()
                                } catch {
                                    print("Micro.blog OAuth error: \(error)")
                                }
                            }
                        }
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var blueskyDashboardContent: some View {
        Group {
            if blueskyClient.isAuthenticated {
                BlueskyRootView(blueskyClient: blueskyClient)
            } else {
                BlueskyLoginView(blueskyClient: blueskyClient)
            }
        }
    }

    private var arkavoDashboardContent: some View {
        Group {
            if arkavoAuthState.isAuthenticated {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connected")
                                .font(.headline)
                            Text(arkavoAuthState.accountName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("End-to-end encrypted streaming is available")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Sign Out") {
                        Task {
                            await arkavoAuthState.logout()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if arkavoAuthState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Sign in to enable encrypted streaming")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Login with Arkavo") {
                            arkavoAuthState.showingLoginSheet = true
                        }
                        .buttonStyle(.borderedProminent)

                        if let error = arkavoAuthState.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
                .sheet(isPresented: Bindable(arkavoAuthState).showingLoginSheet) {
                    arkavoLoginSheet
                }
            }
        }
        .task {
            await arkavoAuthState.checkStoredCredentials()
        }
    }

    private var arkavoLoginSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Login to Arkavo")
                .font(.title2)
                .bold()

            Text("Enter your account name to continue")
                .foregroundColor(.secondary)

            TextField("Account Name", text: $arkavoAccountName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .disabled(arkavoAuthState.isLoading)

            HStack(spacing: 16) {
                Button("Cancel") {
                    arkavoAuthState.showingLoginSheet = false
                }
                .buttonStyle(.plain)
                .disabled(arkavoAuthState.isLoading)

                Button {
                    Task {
                        await arkavoAuthState.login(accountName: arkavoAccountName)
                        arkavoAccountName = ""
                    }
                } label: {
                    if arkavoAuthState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(arkavoAccountName.isEmpty || arkavoAuthState.isLoading)
            }

            if let errorMessage = arkavoAuthState.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 400)
    }

    // Computed property for sorted dashboard sections
    private var sortedDashboardSections: [DashboardSectionItem] {
        var sections: [DashboardSectionItem] = []

        // Arkavo Section (first for encrypted streaming)
        sections.append(DashboardSectionItem(
            id: "arkavo",
            title: "Arkavo",
            isAuthenticated: arkavoAuthState.isAuthenticated,
            hasActiveContent: false,
            content: AnyView(arkavoDashboardContent)
        ))

        // Twitch Section
        sections.append(DashboardSectionItem(
            id: "twitch",
            title: "Twitch",
            isAuthenticated: twitchClient.isAuthenticated,
            hasActiveContent: hasActiveContent(for: "Twitch"),
            content: AnyView(twitchDashboardContent)
        ))

        // YouTube Section
        sections.append(DashboardSectionItem(
            id: "youtube",
            title: "YouTube",
            isAuthenticated: youtubeClient.isAuthenticated,
            hasActiveContent: hasActiveContent(for: "YouTube"),
            content: AnyView(youtubeDashboardContent)
        ))

        // Patreon Section
        sections.append(DashboardSectionItem(
            id: "patreon",
            title: "Patreon",
            isAuthenticated: patreonClient.isAuthenticated,
            hasActiveContent: hasActiveContent(for: "Patreon"),
            content: AnyView(patreonDashboardContent)
        ))

        // Reddit Section
        sections.append(DashboardSectionItem(
            id: "reddit",
            title: "Reddit",
            isAuthenticated: redditClient.isAuthenticated,
            hasActiveContent: hasActiveContent(for: "Reddit"),
            content: AnyView(redditDashboardContent)
        ))

        // Micro.blog Section
        sections.append(DashboardSectionItem(
            id: "microblog",
            title: "Micro.blog",
            isAuthenticated: micropubClient.isAuthenticated,
            hasActiveContent: false,
            content: AnyView(microblogDashboardContent)
        ))

        // Bluesky Section
        sections.append(DashboardSectionItem(
            id: "bluesky",
            title: "Bluesky",
            isAuthenticated: blueskyClient.isAuthenticated,
            hasActiveContent: false,
            content: AnyView(blueskyDashboardContent)
        ))

        // Sort by priority (active content first, then authenticated, then not authenticated)
        return sections.sorted { $0.sortPriority < $1.sortPriority }
    }

    var body: some View {
        ZStack {
            switch selectedSection {
            case .dashboard:
                ScrollView {
                    VStack(spacing: 24) {
                        // Render sorted sections
                        ForEach(sortedDashboardSections) { section in
                            DashboardCard(title: section.title) {
                                section.content
                            }
                        }
                    }
                    .padding()
                }
                .transition(.moveAndFade())
                .id("dashboard")
            case .patrons:
                PatronManagementView(patreonClient: patreonClient)
                    .transition(.moveAndFade())
                    .id("patrons")
            case .studio:
                RecordView(youtubeClient: youtubeClient)
                    .transition(.moveAndFade())
                    .id("studio")
            case .library:
                RecordingsLibraryView()
                    .transition(.moveAndFade())
                    .id("library")
            case .workflow:
                ArkavoWorkflowView()
                    .transition(.moveAndFade())
                    .id("content")
            case .settings:
                SettingsContent()
                    .transition(.moveAndFade())
                    .id("settings")
            default:
                DefaultSectionView(section: selectedSection)
                    .transition(.moveAndFade())
                    .id(selectedSection.rawValue)
            }
        }
        .animation(.smooth, value: selectedSection)
    }
}

struct BlueskyLoginView: View {
    @ObservedObject var blueskyClient: BlueskyClient
    @State private var identifier: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(spacing: 16) {
            if let error = blueskyClient.error {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            TextField("Handle or Email", text: $identifier)
                .textFieldStyle(.roundedBorder)
                .disabled(blueskyClient.isLoading)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)
                .disabled(blueskyClient.isLoading)

            Button(action: login) {
                if blueskyClient.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login with Bluesky")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(identifier.isEmpty || password.isEmpty || blueskyClient.isLoading)
        }
        .padding()
    }

    private func login() {
        Task {
            await blueskyClient.login(identifier: identifier, password: password)
        }
    }
}

struct DashboardCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Default Section View

struct DefaultSectionView: View {
    let section: NavigationSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                // Header section using the new text styling
                Text(section.subtitle)
                    .font(.largeTitle)
                    .bold()
                    .padding(.bottom)

                // Preview Alert for upcoming features
                if section == .protection || section == .social {
                    PreviewAlert()
                }

                // Feature grid using the new layout system
                Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 20) {
                    GridRow {
                        switch section {
                        case .protection:
                            FeatureCard(
                                title: "Creator Ownership Control",
                                description: "Maintain full ownership and control of your content across sharing platforms and AI model interactions",
                                symbol: "shield.lefthalf.filled",
                            )

                            FeatureCard(
                                title: "Attribution & Compensation",
                                description: "Ensure proper citation and fair compensation when your content is shared with third parties",
                                symbol: "creditcard.circle",
                            )

                        case .social:
                            FeatureCard(
                                title: "Cross-Platform Sharing",
                                description: "Share content across multiple platforms with customized previews using native macOS integration",
                                symbol: "square.and.arrow.up",
                            )

                            FeatureCard(
                                title: "Analytics Dashboard",
                                description: "Track engagement and performance with detailed metrics and customizable reports",
                                symbol: "chart.line.uptrend.xyaxis",
                            )

                        default:
                            ContentCard()
                        }
                    }

                    if section == .social {
                        GridRow {
                            FeatureCard(
                                title: "Notification Management",
                                description: "Sync and manage notifications across all your connected social platforms",
                                symbol: "bell.badge",
                            )
                            .gridCellColumns(2)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(section.rawValue)
        .navigationSubtitle(section.subtitle)
    }
}

struct PreviewAlert: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .symbolRenderingMode(.multicolor)
                .font(.title2)

            VStack(alignment: .leading) {
                Text("Coming Soon!")
                    .font(.headline)
                Text("This feature is in the works—we'd love to hear your thoughts!")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Send Feedback") {
                if let url = URL(string: "mailto:info@arkavo.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct FeatureCard: View {
    let title: String
    let description: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title)

                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 8)

            Text(description)
                .foregroundStyle(.secondary)
                .lineLimit(3...)

            Spacer()
        }
        .padding()
        .frame(height: 160)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    static func moveAndFade() -> AnyTransition {
        AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading)),
        )
    }
}

// MARK: - Icon Rail View (Compact Navigation)

struct IconRail: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSection: NavigationSection
    @ObservedObject var patreonClient: PatreonClient
    @ObservedObject var redditClient: RedditClient
    @ObservedObject var blueskyClient: BlueskyClient
    @ObservedObject var youtubeClient: YouTubeClient
    @State private var isCreator: Bool = false
    @State private var isExpanded: Bool = false
    @State private var hoverTask: Task<Void, Never>?

    var availableSections: [NavigationSection] {
        var sections = NavigationSection.availableSections(isCreator: isCreator)
        if !redditClient.isAuthenticated {
            sections = sections.filter { $0 != .social }
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 4) {
            // Main navigation items
            ForEach(availableSections.filter { $0 != .settings }, id: \.self) { section in
                IconRailButton(
                    section: section,
                    isSelected: selectedSection == section,
                    isExpanded: isExpanded
                ) {
                    selectedSection = section
                }
            }

            Spacer()

            // Feedback button (if enabled)
            if appState.isFeedbackEnabled {
                Button {
                    if let url = URL(string: "mailto:info@arkavo.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "envelope")
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Send Feedback")
            }

            // Settings at bottom
            IconRailButton(
                section: .settings,
                isSelected: selectedSection == .settings,
                isExpanded: isExpanded
            ) {
                selectedSection = .settings
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: isExpanded ? 160 : 56)
        .background(.ultraThinMaterial)
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
                if selectedSection == .patrons {
                    selectedSection = .dashboard
                }
            }
        }
        .onHover { hovering in
            // Cancel any pending hover task
            hoverTask?.cancel()

            if hovering {
                // Delay expansion to avoid accidental triggers
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
            } else {
                // Collapse immediately when leaving
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }
        }
    }
}

/// Individual button in the icon rail
private struct IconRailButton: View {
    let section: NavigationSection
    let isSelected: Bool
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? section.systemImage + ".fill" : section.systemImage)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .frame(width: 24)

                if isExpanded {
                    Text(section.rawValue)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(width: isExpanded ? 144 : 40, height: 40)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(section.rawValue)
    }
}

// MARK: - Legacy Sidebar View (for reference)

struct Sidebar: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedSection: NavigationSection
    @ObservedObject var patreonClient: PatreonClient
    @ObservedObject var redditClient: RedditClient
    @ObservedObject var blueskyClient: BlueskyClient
    @ObservedObject var youtubeClient: YouTubeClient
    @State private var isCreator: Bool = false

    var availableSections: [NavigationSection] {
        var sections = NavigationSection.availableSections(isCreator: isCreator)
        if !redditClient.isAuthenticated {
            sections = sections.filter { $0 != .social }
        }
        return sections
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section {
                    ForEach(availableSections.filter { $0 != .settings }, id: \.self) { section in
                        NavigationLink(value: section) {
                            Label(section.rawValue, systemImage: section.systemImage)
                        }
                    }
                }
                Section {
                    NavigationLink(value: NavigationSection.settings) {
                        Label(NavigationSection.settings.rawValue,
                              systemImage: NavigationSection.settings.systemImage)
                    }
                }
            }
            if appState.isFeedbackEnabled {
                Divider()
                Button(action: {
                    if let url = URL(string: "mailto:info@arkavo.com") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Send Feedback")
                    }
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
        .listStyle(.sidebar)
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
                if selectedSection == .patrons {
                    selectedSection = .dashboard
                }
            }
        }
    }
}

// MARK: - Sidebar Row View

struct SidebarRow: View {
    let section: NavigationSection

    var body: some View {
        Label(
            title: { Text(section.rawValue) },
            icon: { Image(systemName: section.systemImage) },
        )
    }
}

// MARK: - Content Card View

struct ContentCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)

            ForEach(0 ..< 3) { _ in
                HStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "doc.text")
                                .foregroundStyle(Color.accentColor),
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Content Title")
                            .font(.body)
                        Text("Updated 2 hours ago")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("View") {
                        // Action
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Feedback Toggle Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Feedback")
                    .font(.headline)

                Toggle("Show Feedback Button", isOn: $appState.isFeedbackEnabled)
                    .toggleStyle(.switch)

                Text("When enabled, shows a feedback button in the toolbar for quick access to send feedback.")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - UserDefaults Extension for Tab Persistence

extension UserDefaults {
    private static let selectedTabKey = "ArkavoCreator.SelectedTab"

    func saveSelectedTab(_ section: NavigationSection) {
        if let encoded = try? JSONEncoder().encode(section) {
            set(encoded, forKey: Self.selectedTabKey)
        }
    }

    func loadSelectedTab() -> NavigationSection {
        guard let data = data(forKey: Self.selectedTabKey),
              let section = try? JSONDecoder().decode(NavigationSection.self, from: data)
        else {
            return .dashboard // Default to dashboard if no saved tab
        }
        return section
    }
}

// MARK: - Helper Functions

/// Formats a number with appropriate suffix (K, M, etc.)
private func formatNumber(_ number: Int) -> String {
    switch number {
    case 0..<1_000:
        return "\(number)"
    case 1_000..<1_000_000:
        let thousands = Double(number) / 1_000.0
        return String(format: "%.1fK", thousands)
    case 1_000_000..<1_000_000_000:
        let millions = Double(number) / 1_000_000.0
        return String(format: "%.1fM", millions)
    default:
        let billions = Double(number) / 1_000_000_000.0
        return String(format: "%.1fB", billions)
    }
}
