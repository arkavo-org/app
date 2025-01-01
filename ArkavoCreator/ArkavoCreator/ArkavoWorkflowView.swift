import ArkavoSocial
import CoreML
import SwiftUI

struct ArkavoWorkflowView: View {
    @StateObject private var viewModel: WorkflowViewModel
    @State private var searchText = ""
    @State private var selectedItems = Set<UUID>()
    @State private var isFileDialogPresented = false

    init() {
        print("ArkavoWorkflowView: Initializing")
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeWorkflowViewModel())
    }

    var body: some View {
        Group {
            if viewModel.isConnected {
                contentView
            } else {
                loginView
            }
        }
        .sheet(isPresented: $viewModel.showingLoginSheet) {
            loginSheet
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .task {
            await viewModel.checkStoredCredentials()
        }
    }

    private var contentView: some View {
        List(selection: $selectedItems) {
            ForEach(sampleContent) { content in
                ContentItemRow(content: content)
                    .tag(content.id)
            }
        }
        .navigationTitle("Workflow")
        .searchable(text: $searchText, prompt: "Search content")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { isFileDialogPresented = true }) {
                    Label("Import Content", systemImage: "plus")
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button {
                    Task {
                        await viewModel.logout()
                    }
                } label: {
                    Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            if !selectedItems.isEmpty {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {}) {
                        Label("Protect", systemImage: "lock.shield")
                    }
                    Button(action: {}) {
                        Label("Share", systemImage: "square.and.arrow.up")
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
                            try await viewModel.processContent(url)
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
            case let .failure(error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private var loginView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Login Required")
                .font(.title)

            Text("Please log in to access your content")
                .foregroundColor(.secondary)

            Button(action: { viewModel.showingLoginSheet = true }) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login with Passkey")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loginSheet: some View {
        VStack(spacing: 20) {
            Text("Login to Arkavo")
                .font(.title2)
                .bold()

            Text("Enter your account name to continue")
                .foregroundColor(.secondary)

            TextField("Account Name", text: $viewModel.accountName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .disabled(viewModel.isLoading)

            HStack(spacing: 16) {
                Button("Cancel") {
                    viewModel.showingLoginSheet = false
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)

                Button {
                    Task {
                        await viewModel.login()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.accountName.isEmpty || viewModel.isLoading)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

struct ContentItemRow: View {
    let content: ContentItem
    @State private var showingMenu = false

    var body: some View {
        HStack(spacing: 12) {
            // Type Icon with proper SF Symbol
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(.body)

                    HStack(spacing: 8) {
                        Text(content.type.rawValue)
                            .foregroundStyle(.secondary)

                        switch content.protectionStatus {
                        case let .protected(date):
                            Text("Protected \(date)")
                                .foregroundStyle(.secondary)
                        case .registering:
                            Label("Registering...", systemImage: "arrow.clockwise")
                                .foregroundStyle(.secondary)
                        case .unprotected:
                            Label("Not Protected", systemImage: "lock.open")
                                .foregroundStyle(.secondary)
                        case .failed:
                            Label("Protection Failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }

                        if !content.patronAccess.isEmpty {
                            Text("\(content.patronAccess.count) Tiers")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
            } icon: {
                Image(systemName: content.type.icon)
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(width: 32)
            }

            Spacer()

            if content.views > 0 {
                VStack(alignment: .trailing) {
                    Text("\(content.views) views")
                    Text("\(content.engagement, specifier: "%.1f")% engagement")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }

            Menu {
                Button("View Details") {}
                Button("Edit") {}

                if case .unprotected = content.protectionStatus {
                    Divider()
                    Button("Protect Content") {}
                }

                Divider()
                Button("Delete", role: .destructive) {}
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolVariant(.fill)
                    .contentTransition(.symbolEffect(.replace))
            }
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

struct ProtectionConfigSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var isRegistering = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Protect Content")
                .font(.title)

            if isRegistering {
                ProgressView("Registering with Arkavo Network...")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Registration will:")
                        .font(.headline)

                    Label("Create immutable record", systemImage: "checkmark.circle")
                    Label("Generate unique identifier", systemImage: "checkmark.circle")
                    Label("Enable patron distribution", systemImage: "checkmark.circle")
                }
            }

            HStack {
                Button("Cancel", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)

                Button("Register Content") {
                    isRegistering = true
                    // Registration logic
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top)
        }
        .padding()
        .frame(width: 400)
    }
}

struct PatronAccessSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTiers: Set<UUID> = []

    var body: some View {
        VStack(spacing: 20) {
            Text("Set Patron Access")
                .font(.title)

//            List(sampleTiers, selection: $selectedTiers) { tier in
//                HStack {
//                    VStack(alignment: .leading) {
//                        Text(tier.name)
//                            .font(.headline)
//                        Text("\(tier.patronCount) patrons")
//                            .font(.caption)
//                            .foregroundStyle(.secondary)
//                    }
//
//                    Spacer()
//
//                    Text("$\(tier.price, specifier: "%.2f")/month")
//                        .foregroundStyle(.secondary)
//                }
//            }

            HStack {
                Button("Cancel", action: { dismiss() })
                    .keyboardShortcut(.cancelAction)

                Button("Confirm Access") {
                    // Distribution logic
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

// MARK: - Content Item Model

struct ContentItem: Identifiable, Hashable {
    let id: UUID
    let title: String
    let type: ContentType
    let createdDate: Date
    let lastModified: Date
    var protectionStatus: ProtectionStatus
    var patronAccess: [PatronTier]
    var views: Int
    var engagement: Double // percentage

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ContentItem, rhs: ContentItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Types

enum ContentType: String {
    case blogPost = "Blog Post"
    case video = "Video"
    case audio = "Audio"
    case image = "Image"
    case document = "Document"

    var icon: String {
        switch self {
        case .blogPost: "doc.text"
        case .video: "video"
        case .audio: "waveform"
        case .image: "photo"
        case .document: "doc"
        }
    }
}

enum ProtectionStatus {
    case unprotected
    case registering
    case protected(Date)
    case failed(String)

    var icon: String {
        switch self {
        case .unprotected: "lock.open"
        case .registering: "arrow.clockwise"
        case .protected: "lock.shield"
        case .failed: "exclamationmark.triangle"
        }
    }

    var description: String {
        switch self {
        case .unprotected: "Not Protected"
        case .registering: "Registering..."
        case let .protected(date): "Protected on \(date.formatted(date: .abbreviated, time: .shortened))"
        case let .failed(error): "Failed: \(error)"
        }
    }
}

// MARK: - Sample Content

let sampleContent: [ContentItem] = [
    ContentItem(
        id: UUID(),
        title: "Getting Started with SwiftUI",
        type: .blogPost,
        createdDate: Date().addingTimeInterval(-86400 * 2),
        lastModified: Date().addingTimeInterval(-3600 * 2),
        protectionStatus: .protected(Date().addingTimeInterval(-3600)),
        patronAccess: [],
        views: 156,
        engagement: 78.5
    ),
    ContentItem(
        id: UUID(),
        title: "Monthly Update Video",
        type: .video,
        createdDate: Date().addingTimeInterval(-86400),
        lastModified: Date().addingTimeInterval(-3600),
        protectionStatus: .unprotected,
        patronAccess: [],
        views: 0,
        engagement: 0
    ),
    ContentItem(
        id: UUID(),
        title: "Project Documentation",
        type: .document,
        createdDate: Date(),
        lastModified: Date(),
        protectionStatus: .registering,
        patronAccess: [],
        views: 0,
        engagement: 0
    ),
]

// MARK: - Content Row View

struct ContentRow: View {
    let content: ContentItem

    var body: some View {
        HStack(spacing: 16) {
            // Content Icon
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: content.type.icon)
                        .foregroundStyle(Color.accentColor)
                )

            // Content Info
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline)

                HStack(spacing: 12) {
                    Label(content.type.rawValue, systemImage: content.type.icon)

                    Label(content.protectionStatus.description,
                          systemImage: content.protectionStatus.icon)

                    if !content.patronAccess.isEmpty {
                        Label("\(content.patronAccess.count) Tiers",
                              systemImage: "person.2.circle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            // Stats
            if content.views > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(content.views) views")
                        .font(.subheadline)

                    Text("\(content.engagement, specifier: "%.1f")% engagement")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Actions Menu
            Menu {
                Button("View Details", action: {})
                Button("Edit", action: {})
                if case .unprotected = content.protectionStatus {
                    Button("Protect Content", action: {})
                }
                Button("Set Patron Access", action: {})
                Divider()
                Button("Delete", role: .destructive, action: {})
            } label: {
                Image(systemName: "ellipsis.circle")
                    .symbolVariant(.fill)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Error Types

enum ArkavoError: Error {
    case invalidURL
    case authenticationFailed(String)
    case connectionFailed(String)
    case invalidResponse
    case messageError(String)
    case notConnected
    case invalidState
}

// MARK: - ViewModel

@MainActor
class WorkflowViewModel: ObservableObject {
    private let client: ArkavoClient

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingLoginSheet = false
    @Published var accountName = ""

    init(client: ArkavoClient) {
        print("WorkflowViewModel: Initializing with ArkavoClient")
        self.client = client
        if let handle = KeychainManager.getHandle() {
            accountName = handle
        }
    }

    var isConnected: Bool {
        client.currentState == .connected
    }

    func login() async {
        guard !accountName.isEmpty else {
            print("WorkflowViewModel: Login attempted with empty account name")
            return
        }

        print("WorkflowViewModel: Starting login for account: \(accountName)")
        isLoading = true
        errorMessage = nil

        do {
            print("WorkflowViewModel: Attempting to connect client...")
            try await client.connect(accountName: accountName)
            print("WorkflowViewModel: Client connected successfully")

            // Save account name for future sessions
            UserDefaults.standard.set(accountName, forKey: "arkavo_account_name")
            print("WorkflowViewModel: Saved account name to UserDefaults")

            if let token = client.currentToken {
                print("WorkflowViewModel: Got token from client, saving to keychain...")
                try KeychainManager.saveAuthenticationToken(token)
                print("WorkflowViewModel: Token saved successfully")
            } else {
                print("WorkflowViewModel: No token received from client after connection")
            }

            showingLoginSheet = false
            accountName = ""
        } catch {
            print("WorkflowViewModel: Login failed with error: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func logout() async {
        print("WorkflowViewModel: Starting logout process")
        await client.disconnect()

        print("WorkflowViewModel: Clearing stored credentials")
        KeychainManager.deleteAuthenticationToken()
        UserDefaults.standard.removeObject(forKey: "arkavo_account_name")
        print("WorkflowViewModel: Logout complete")
    }

    func checkStoredCredentials() async {
        print("WorkflowViewModel: Checking stored credentials")

        // First check the keychain for token
        if let token = KeychainManager.getAuthenticationToken() {
            print("WorkflowViewModel: Found stored token starting with: \(String(token.prefix(10)))...")
        } else {
            print("WorkflowViewModel: No stored token found in keychain")
            return
        }

        // Then check UserDefaults for account name
        guard let storedName = UserDefaults.standard.string(forKey: "arkavo_account_name") else {
            print("WorkflowViewModel: No stored account name found in UserDefaults")
            return
        }

        print("WorkflowViewModel: Found stored account name: \(storedName)")

        print("WorkflowViewModel: Attempting to connect with stored credentials")
        isLoading = true
        errorMessage = nil

        do {
            print("WorkflowViewModel: Connecting with stored account: \(storedName)")
            try await client.connect(accountName: storedName)
            print("WorkflowViewModel: Successfully connected with stored credentials")
        } catch let error as ArkavoError {
            print("WorkflowViewModel: Connection failed with ArkavoError: \(error)")
            switch error {
            case let .authenticationFailed(message):
                print("WorkflowViewModel: Authentication failed: \(message)")
            case let .connectionFailed(message):
                print("WorkflowViewModel: Connection failed: \(message)")
            default:
                print("WorkflowViewModel: Other error: \(error)")
            }

            print("WorkflowViewModel: Clearing stored credentials after failure")
            KeychainManager.deleteAuthenticationToken()
            UserDefaults.standard.removeObject(forKey: "arkavo_account_name")
            errorMessage = error.localizedDescription
        } catch {
            print("WorkflowViewModel: Unexpected error during connection: \(error)")
            print("WorkflowViewModel: Clearing stored credentials")
            KeychainManager.deleteAuthenticationToken()
            UserDefaults.standard.removeObject(forKey: "arkavo_account_name")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func processContent(_ url: URL) async throws {
        print("WorkflowViewModel: Starting content processing for \(url)")
        isLoading = true
        defer { isLoading = false }

        do {
            // Initialize the processor with GPU acceleration if available
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .all
            let processor = try VideoSegmentationProcessor(configuration: configuration)

            // Create a proper file URL
            let fileManager = FileManager.default

            // Verify file exists and is accessible
            let inputPath = url.absoluteString
            let path: String = if inputPath.starts(with: "file://") {
                String(inputPath.dropFirst(7))
            } else {
                inputPath
            }
            print("Current working directory: \(fileManager.currentDirectoryPath)")
            print("Checking file: \(path)")

            let videoURL = URL(fileURLWithPath: path)

            // Verify file access
            guard fileManager.fileExists(atPath: videoURL.path),
                  fileManager.isReadableFile(atPath: videoURL.path)
            else {
                print("Video file doesn't exist or isn't readable")
                throw ArkavoError.invalidURL
            }

            // Process the video with scene detection
            let detector = try VideoSceneDetector()
            let referenceMetadata = try await detector.generateMetadata(for: videoURL)

            // Create scene match detector with reference metadata
            let matchDetector = VideoSceneDetector.SceneMatchDetector(
                referenceMetadata: [referenceMetadata]
            )

            // Process the video with progress updates
            let segmentations = try await processor.processVideo(url: videoURL) { progress in
                print("Processing progress: \(Int(progress * 100))%")
            }

            print("Processed \(segmentations.count) frames")

            // Analyze segmentations for significant changes
            let changes = processor.analyzeSegmentations(segmentations, threshold: 0.8)
            print("Found \(changes.count) significant scene changes")

            // Process scene matches
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

            print("Content processing completed successfully")

        } catch {
            print("Content processing failed: \(error)")
            throw error
        }
    }
}
