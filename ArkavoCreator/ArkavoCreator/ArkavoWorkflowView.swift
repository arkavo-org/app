import ArkavoKit
import AuthenticationServices
import CoreML
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

struct ArkavoWorkflowView: View {
    @StateObject private var viewModel: WorkflowViewModel
    @State private var searchText = ""
    @State private var isFileDialogPresented = false
    @State private var selectedMessages = Set<UUID>()

    private var authState: ArkavoAuthState { ArkavoAuthState.shared }

    init() {
        print("ArkavoWorkflowView: Initializing")
        _viewModel = StateObject(wrappedValue: ViewModelFactory.shared.makeWorkflowViewModel())
    }

    var body: some View {
        Group {
            if authState.isAuthenticated {
                contentView
            } else {
                loginView
            }
        }
        .sheet(isPresented: Bindable(authState).showingLoginSheet) {
            ArkavoLoginSheet(authState: authState)
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
            await authState.checkStoredCredentials()
        }
    }

    private var contentView: some View {
        NavigationView {
            MessageListView(
                messageManager: viewModel.messageDelegate.getMessageManager(),
                workflowViewModel: viewModel,
                selectedMessages: $selectedMessages,
            )
            .navigationTitle("Messages")
            .searchable(text: $searchText, prompt: "Search messages")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task {
                            await viewModel.sendSelectedContent(selectedMessages)
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .keyboardShortcut("r", modifiers: [.command])
                    .help("Send content to network")
                    .disabled(selectedMessages.isEmpty)

                    Button(action: { isFileDialogPresented = true }) {
                        Label("Import Content", systemImage: "plus")
                    }
                    .keyboardShortcut("i", modifiers: [.command])

                    Menu {
                        Button(role: .destructive) {
                            // Add clear all functionality
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }

                    Button {
                        Task {
                            await authState.logout()
                        }
                    } label: {
                        Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .fileImporter(
                isPresented: $isFileDialogPresented,
                allowedContentTypes: [UTType.quickTimeMovie],
                allowsMultipleSelection: false,
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

            // Empty state view when no messages
            if viewModel.messageDelegate.getMessageManager().messages.isEmpty {
                ContentPlaceholderView()
            }
        }
    }

    private var hasFailedMessages: Bool {
        guard !selectedMessages.isEmpty else { return false }
        return viewModel.messageDelegate.getMessageManager().messages
            .filter { selectedMessages.contains($0.id) }
            .contains { $0.status == .failed }
    }

    private struct ContentPlaceholderView: View {
        var body: some View {
            VStack(spacing: 20) {
                Image(systemName: "message")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("No Messages")
                    .font(.title2)
                    .foregroundColor(.primary)

                Text("Messages will appear here when content is processed")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
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

            Button(action: { authState.showingLoginSheet = true }) {
                if authState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Login with Passkey")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(authState.isLoading)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

struct MessageRow: View {
    let message: ArkavoMessage
    @StateObject private var viewModel: MessageRowViewModel
    @Environment(\.isEnabled) private var isEnabled

    init(message: ArkavoMessage, workflowViewModel: WorkflowViewModel) {
        self.message = message
        _viewModel = StateObject(wrappedValue: MessageRowViewModel(workflowViewModel: workflowViewModel))
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: message.status.icon)
                .foregroundColor(message.status.color)
                .font(.system(size: 16))

            // Message info
            VStack(alignment: .leading, spacing: 4) {
                Text("Message \(message.id.uuidString.prefix(8))")
                    .font(.headline)

                Text("Received: \(message.timestamp.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if message.status == .pending {
                    Text("Retry count: \(message.retryCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let lastRetry = message.lastRetryDate {
                    Text("Last retry: \(lastRetry.formatted())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(message.status.rawValue.capitalized)
                .font(.caption)
                .foregroundColor(message.status.color)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

@MainActor
class MessageRowViewModel: ObservableObject {
    @Published var isSending = false
    @Published var error: Error?

    private let workflowViewModel: WorkflowViewModel

    init(workflowViewModel: WorkflowViewModel) {
        self.workflowViewModel = workflowViewModel
    }
}

struct MessageListView: View {
    @ObservedObject var messageManager: ArkavoMessageManager
    let workflowViewModel: WorkflowViewModel
    @Binding var selectedMessages: Set<UUID>

    var body: some View {
        List(selection: $selectedMessages) {
            ForEach(messageManager.messages) { message in
                MessageRow(message: message, workflowViewModel: workflowViewModel)
                    .tag(message.id)
            }
        }
        .toolbar {
            if !selectedMessages.isEmpty {
                ToolbarItem {
                    Button {
                        Task {
                            await retrySelected()
                        }
                    } label: {
                        Label("Retry Selected", systemImage: "arrow.clockwise")
                    }
                    .disabled(!hasFailedMessages)
                }
            }
        }
    }

    private var hasFailedMessages: Bool {
        guard !selectedMessages.isEmpty else { return false }
        return messageManager.messages
            .filter { selectedMessages.contains($0.id) }
            .contains { $0.status == .failed }
    }

    private func retrySelected() async {
        let failedMessages = selectedMessages.filter { messageId in
            messageManager.messages.first { $0.id == messageId }?.status == .failed
        }
        await workflowViewModel.sendSelectedContent(failedMessages)
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
                        .foregroundStyle(Color.accentColor),
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
                Button("View Details", action: { /* TODO: Implement view details */ })
                Button("Edit", action: { /* TODO: Implement edit */ })
                if case .unprotected = content.protectionStatus {
                    Button("Protect Content", action: { /* TODO: Implement content protection */ })
                }
                Button("Set Patron Access", action: { /* TODO: Implement patron access */ })
                Divider()
                Button("Delete", role: .destructive, action: { /* TODO: Implement delete */ })
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
class WorkflowViewModel: ObservableObject, ArkavoClientDelegate {
    private let client: ArkavoClient
    let messageDelegate: ArkavoMessageChainDelegate
    @Published var isLoading = false
    @Published var errorMessage: String?

    init(client: ArkavoClient, messageDelegate: ArkavoMessageChainDelegate) {
        print("WorkflowViewModel: Initializing with ArkavoClient")
        self.client = client
        self.messageDelegate = messageDelegate

        // Set up delegate chain
        messageDelegate.updateNextDelegate(self)
        client.delegate = messageDelegate
    }

    // MARK: - ArkavoClientDelegate Methods

    func clientDidChangeState(_: ArkavoClient, state: ArkavoClientState) {
        print("WorkflowViewModel: Client state changed to: \(state)")
        Task { @MainActor in
            switch state {
            case let .error(error):
                self.errorMessage = error.localizedDescription
            case .disconnected:
                print("WorkflowViewModel: Client disconnected")
            case .connecting:
                print("WorkflowViewModel: Client connecting")
            case .authenticating:
                print("WorkflowViewModel: Client authenticating")
            case .connected:
                print("WorkflowViewModel: Client connected")
            }
        }
    }

    func clientDidReceiveMessage(_: ArkavoClient, message: Data) {
        print("WorkflowViewModel: Received message of size: \(message.count)")
        if let messageType = message.first {
            switch messageType {
            case 0x06:
                print("WorkflowViewModel: Received type 6 message")
                handleType6Message(message.dropFirst())
            default:
                print("WorkflowViewModel: Received message with type: \(messageType)")
            }
        }
    }

    func clientDidReceiveError(_: ArkavoClient, error: Error) {
        print("WorkflowViewModel: Received error: \(error)")
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private Message Handlers

    private func handleType6Message(_ messageData: Data) {
        print("WorkflowViewModel: Processing type 6 message of size: \(messageData.count)")
    }

    // MARK: - Content Processing

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
                referenceMetadata: [referenceMetadata],
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

    func sendSelectedContent(_ selectedIds: Set<UUID>) async {
        guard client.currentState == .connected else {
            errorMessage = "Not connected to network"
            return
        }

        guard !selectedIds.isEmpty else {
            errorMessage = "No messages selected"
            return
        }

        isLoading = true
        defer { isLoading = false }

        let manager = messageDelegate.getMessageManager()

        do {
            // Get all selected messages
            let selectedMessages = manager.messages.filter { selectedIds.contains($0.id) }

            // Send each selected message
            for message in selectedMessages {
                // Convert the first 20 bytes of the message data to hex
                let first20Bytes = message.data.prefix(20)
                let hexString = first20Bytes.map { String(format: "%02x", $0) }.joined(separator: " ")

                print("Message \(message.id): \(hexString)")

                try await client.sendMessage(message.data)
                print("Sent message: \(message.id)")
            }
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
        }
    }

    // MARK: - Computed Properties

    var isConnected: Bool {
        client.currentState == .connected
    }
}
