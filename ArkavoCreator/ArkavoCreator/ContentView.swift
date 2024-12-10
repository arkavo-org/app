import ArkavoContent
import ArkavoSocial
import CoreML
import SwiftUI

// MARK: - Main Content View

struct ContentView: View {
    @State private var selectedSection: NavigationSection = .dashboard
    @State private var isFileDialogPresented: Bool = false
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) var colorScheme
    @StateObject var patreonClient: PatreonClient
    @StateObject var redditClient: RedditClient
    @StateObject var micropubClient: MicropubClient
    @StateObject var blueskyClient: BlueskyClient
    @StateObject var youtubeClient: YouTubeClient

    var body: some View {
        NavigationSplitView {
            Sidebar(selectedSection: $selectedSection,
                    patreonClient: patreonClient,
                    redditClient: redditClient,
                    blueskyClient: blueskyClient,
                    youtubeClient: youtubeClient)
        } detail: {
            VStack(spacing: 0) {
                SectionContainer(
                    selectedSection: selectedSection,
                    patreonClient: patreonClient,
                    redditClient: redditClient,
                    micropubClient: micropubClient,
                    blueskyClient: blueskyClient,
                    youtubeClient: youtubeClient
                )
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationSubtitle(selectedSection.subtitle)
            .toolbar {
                if patreonClient.isAuthenticated || redditClient.isAuthenticated || youtubeClient.isAuthenticated || micropubClient.isAuthenticated ||
                    blueskyClient.isAuthenticated
                {
                    ToolbarItemGroup {
                        Button(action: {
                            isFileDialogPresented = true
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
                        } label: {
                            Image(systemName: "person.circle")
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isFileDialogPresented,
                allowedContentTypes: [.quickTimeMovie],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        Task {
                            do {
                                try await processContent(url)
                            } catch {
                                print("Unable to read file: \(error.localizedDescription)")
                            }
                        }
                    }
                case let .failure(error):
                    print("Failed to select file: \(error.localizedDescription)")
                }
            }
        }
        .environmentObject(appState)
    }

    private func processContent(_ url: URL) async throws {
        print(url)
        do {
            // Initialize the processor with GPU acceleration if available
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let processor = try VideoSegmentationProcessor(configuration: configuration)

            // Create a proper file URL
            let fileManager = FileManager.default

            // Verify file exists and is accessible
            // Debug info
            let inputPath = url.absoluteString
            let path: String = if inputPath.starts(with: "file://") {
                String(inputPath.dropFirst(7))
            } else {
                inputPath
            }
            print("Current working directory: \(fileManager.currentDirectoryPath)")
            print("Checking file: \(path)")

            let videoURL = URL(fileURLWithPath: path)

            // Check file existence
            if fileManager.fileExists(atPath: path) {
                print("✅ File exists")

                // Get file attributes
                if let attrs = try? fileManager.attributesOfItem(atPath: path) {
                    print("File size: \(attrs[.size] ?? "unknown")")
                    print("File permissions: \(attrs[.posixPermissions] ?? "unknown")")
                    print("File type: \(attrs[.type] ?? "unknown")")
                }

                // Check read permissions
                if fileManager.isReadableFile(atPath: path) {
                    print("✅ File is readable")
                } else {
                    print("❌ File is not readable")
                }
            } else {
                print("❌ File does not exist")

                // List Downloads directory contents
                print("\nContents of Downloads directory:")
                if let contents = try? fileManager.contentsOfDirectory(atPath: "/Users/paul/Downloads") {
                    for item in contents {
                        if item.hasSuffix(".mov") {
                            print("📹 \(item)")
                        }
                    }
                } else {
                    print("❌ Could not read Downloads directory")
                }
            }
            guard fileManager.fileExists(atPath: videoURL.path),
                  fileManager.isReadableFile(atPath: videoURL.path)
            else {
                print("Video file doesn't exist or isn't readable")
                return
            }
            // VideoSceneDetector
            let detector = try VideoSceneDetector()
            let referenceURL1 = url
            let referenceMetadata1 = try await detector.generateMetadata(for: referenceURL1)
            // Create scene match detector with reference metadata
            let matchDetector = VideoSceneDetector.SceneMatchDetector(
                referenceMetadata: [referenceMetadata1]
            )

            // Process the video with progress updates
            let segmentations = try await processor.processVideo(url: url) { progress in
                print("Processing progress: \(Int(progress * 100))%")
            }

            print("Processed \(segmentations.count) frames")

            // Analyze segmentations for significant changes
            let changes = processor.analyzeSegmentations(segmentations, threshold: 0.8)

            print("Found \(changes.count) significant scene changes")
            for (timestamp, similarity) in changes {
                print("Scene change at \(String(format: "%.2f", timestamp))s (similarity: \(String(format: "%.2f", similarity)))")
            }

            // Optionally save processed frames
            print("tmp out \(FileManager.default.temporaryDirectory)")
            let outputDirectory = URL(fileURLWithPath: FileManager.default.temporaryDirectory.absoluteString)
            for segmentation in segmentations {
                try processor.saveFrameWithSegmentation(segmentation, toDirectory: outputDirectory)
            }

            for segmentation in segmentations {
                let sceneData = try await detector.processSegmentation(segmentation)
                let matches = await matchDetector.findMatches(for: sceneData)

                if !matches.isEmpty {
                    print("Found matches at \(sceneData.timestamp):")
                    for match in matches {
                        print("- Match in \(match.matchedVideoId) at \(match.matchedTimestamp)s (similarity: \(match.similarity))")
                    }
                }
            }

            print("Finished processing video")
        } catch {
            print("Error: \(error)")
        }
    }
}

// MARK: - Navigation Section Updates

enum NavigationSection: String, CaseIterable {
    case dashboard = "Dashboard"
    case content = "Workflow"
    case patrons = "Patron Management"
    case protection = "Content Protection"
    case social = "Social Distribution"
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
        case .content: "doc.badge.plus"
        case .patrons: "person.2.circle"
        case .protection: "lock.shield"
        case .social: "square.and.arrow.up.circle"
        case .settings: "gear"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: "Overview"
        case .content: "Manage Your Content"
        case .patrons: "Manage Your Community"
        case .protection: "Content Security"
        case .social: "Share Your Content"
        case .settings: "App Settings"
        }
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
    @StateObject private var webViewPresenter = WebViewPresenter()
    @State private var authCode: String = ""
    @Namespace private var animation

    var body: some View {
        ZStack {
            switch selectedSection {
            case .dashboard:
                ScrollView {
                    VStack(spacing: 24) {
                        // Patreon Section
                        DashboardCard(title: "Patreon") {
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
                                                    // Keep the window open on error to show any error pages
                                                }
                                            }
                                        }
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        // Reddit Section
                        DashboardCard(title: "Reddit") {
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
                        // Micro.blog Section
                        DashboardCard(title: "Micro.blog") {
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
                        // Bluesky Section
                        DashboardCard(title: "Bluesky") {
                            if blueskyClient.isAuthenticated {
                                BlueskyRootView(blueskyClient: blueskyClient)
                            } else {
                                BlueskyLoginView(blueskyClient: blueskyClient)
                            }
                        }
                        // YouTube Section
                        DashboardCard(title: "YouTube") {
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
                                        VStack(spacing: 16) {
                                            Button("Login with YouTube") {
                                                Task {
                                                    let authURL = await youtubeClient.authURL
                                                    webViewPresenter.present(
                                                        url: authURL,
                                                        handleCallback: { url in
                                                            Task {
                                                                do {
                                                                    try await youtubeClient.handleCallback(url)
                                                                    webViewPresenter.dismiss()
                                                                } catch {
                                                                    print("YouTube OAuth error: \(error)")
                                                                }
                                                            }
                                                        }
                                                    )
                                                }
                                            }
                                            .buttonStyle(.borderedProminent)

                                            Button("Sign in with Authorization Code") {
                                                youtubeClient.showAuthCodeForm = true
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                    }

                                    if youtubeClient.showAuthCodeForm {
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text("Authorization Code")
                                                .font(.headline)

                                            Text("Please paste the authorization code from Google:")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)

                                            TextEditor(text: $authCode)
                                                .font(.system(.body, design: .monospaced))
                                                .frame(height: 80)
                                                .scrollContentBackground(.hidden)
                                                .background(Color(NSColor.textBackgroundColor))
                                                .cornerRadius(6)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .stroke(Color.gray.opacity(0.2))
                                                )

                                            if let error = youtubeClient.error {
                                                Text(error.localizedDescription)
                                                    .foregroundColor(.red)
                                                    .font(.caption)
                                            }

                                            HStack {
                                                Spacer()

                                                Button("Cancel") {
                                                    youtubeClient.showAuthCodeForm = false
                                                    authCode = ""
                                                }
                                                .buttonStyle(.plain)

                                                Button("Submit") {
                                                    Task {
                                                        do {
                                                            try await youtubeClient.authenticateWithCode(authCode)
                                                            authCode = ""
                                                        } catch {
                                                            print("Authentication error: \(error)")
                                                        }
                                                    }
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(authCode.isEmpty || youtubeClient.isLoading)
                                            }
                                        }
                                        .padding()
                                        .frame(maxWidth: 400)
                                    }
                                }
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
            case .content:
                ContentManagerView()
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
            VStack(alignment: .leading, spacing: 20) {
                Text(section.rawValue)
                    .font(.title)
                    .padding(.bottom)

                ContentCard()
            }
            .padding()
        }
    }
}

// MARK: - Custom Transitions

extension AnyTransition {
    static func moveAndFade() -> AnyTransition {
        AnyTransition.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity.combined(with: .move(edge: .leading))
        )
    }
}

// MARK: - Sidebar View

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
            icon: { Image(systemName: section.systemImage) }
        )
    }
}

// MARK: - Top Bar View

struct TopBar: View {
    let title: String
    @State private var showNotifications = false
    @State private var showProfileMenu = false

    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            HStack(spacing: 16) {
                Button(action: { showNotifications.toggle() }) {
                    Image(systemName: "bell")
                        .symbolVariant(showNotifications ? .fill : .none)
                }
                .help("Notifications")

                Menu {
                    Button("Profile", action: {})
                    Button("Preferences", action: {})
                    Divider()
                    Button("Sign Out", action: {})
                } label: {
                    HStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Divider(),
            alignment: .bottom
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
                                .foregroundStyle(Color.accentColor)
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
    }
}
