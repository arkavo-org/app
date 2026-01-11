import SwiftUI
import AVKit
import ArkavoSocial
import ArkavoMediaKit
import CryptoKit
import OpenTDFKit

struct RecordingsLibraryView: View {
    @StateObject private var manager = RecordingsManager()
    @State private var selectedRecording: Recording?
    @State private var playerRecording: Recording?  // Dedicated state for video player sheet
    @State private var showingProvenance = false
    @State private var showingDeleteConfirmation = false
    @State private var protectedPlayerRecording: Recording?  // Dedicated state for protected player
    @State private var isProtecting = false
    @State private var protectionError: String?
    @State private var showingProtectionError = false
    @State private var recordingToDelete: Recording?
    @State private var gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)]

    // Iroh publishing state
    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var showingPublishError = false
    @State private var publishedTicket: ContentTicket?
    @State private var showingPublishSuccess = false

    private let kasURL = URL(string: "https://100.arkavo.net")!

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            if manager.recordings.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(manager.recordings) { recording in
                            RecordingCard(recording: recording)
                                .accessibilityIdentifier("RecordingCard_\(recording.id)")
                                .onTapGesture {
                                    playerRecording = recording
                                }
                                .contextMenu {
                                    recordingContextMenu(for: recording)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $playerRecording) { recording in
            VideoPlayerView(recording: recording)
        }
        .sheet(isPresented: $showingProvenance) {
            if let recording = selectedRecording {
                ProvenanceView(recording: recording)
            }
        }
        .sheet(item: $protectedPlayerRecording) { recording in
            ProtectedVideoPlayerView(recording: recording, kasURL: kasURL)
        }
        .task {
            await manager.loadRecordings()
        }
        .alert("Delete Recording?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                recordingToDelete = nil
            }
            Button("Delete", role: .destructive) {
                confirmDelete()
            }
        } message: {
            if let recording = recordingToDelete {
                Text("Are you sure you want to permanently delete \"\(recording.title)\"? This action cannot be undone.")
            }
        }
        .alert("Protection Error", isPresented: $showingProtectionError) {
            Button("OK") {
                protectionError = nil
            }
        } message: {
            if let error = protectionError {
                Text(error)
            }
        }
        .alert("Publish Error", isPresented: $showingPublishError) {
            Button("OK") {
                publishError = nil
            }
        } message: {
            if let error = publishError {
                Text(error)
            }
        }
        .alert("Published to Network", isPresented: $showingPublishSuccess) {
            Button("Copy Ticket") {
                if let ticket = publishedTicket {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ticket.ticket, forType: .string)
                }
            }
            Button("OK", role: .cancel) {
                publishedTicket = nil
            }
        } message: {
            Text("Content published successfully. Share the ticket to allow others to access this content.")
        }
        .overlay {
            if isProtecting || isPublishing {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(isProtecting ? "Protecting video..." : "Publishing to network...")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(isProtecting ? "Encrypting with TDF3 for FairPlay streaming" : "Uploading TDF content via Iroh P2P")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .ignoresSafeArea()
                .accessibilityIdentifier(isProtecting ? "ProtectionOverlay" : "PublishingOverlay")
            }
        }
    }

    // MARK: - View Components

    private var headerView: some View {
        HStack {
            Text("Recordings")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Text("\(manager.recordings.count) recording\(manager.recordings.count == 1 ? "" : "s")")
                .foregroundColor(.secondary)
                .font(.subheadline)

            Button {
                Task {
                    await manager.loadRecordings()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
        }
        .padding()
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            if manager.needsFolderSelection {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Choose Recordings Folder")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select where to store your recordings")
                    .foregroundColor(.secondary)

                Button("Select Folder...") {
                    Task {
                        await manager.selectRecordingsFolder()
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "video.slash")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary)

                Text("No Recordings Yet")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Start recording to see your videos here")
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func recordingContextMenu(for recording: Recording) -> some View {
        Button("Play") {
            playerRecording = recording
        }

        Divider()

        // TDF3 Protection options
        Button {
            Task {
                await protectRecording(recording)
            }
        } label: {
            Label("Protect with TDF3", systemImage: "lock.shield")
        }
        .disabled(isProtecting)

        Button {
            Task {
                await protectRecordingHLS(recording)
            }
        } label: {
            Label("Protect with HLS (Streaming)", systemImage: "play.tv.fill")
        }
        .disabled(isProtecting)

        if FileManager.default.fileExists(atPath: recording.tdfURL.path) {
            Button {
                print("🎬 Opening protected player for: \(recording.title)")
                protectedPlayerRecording = recording
            } label: {
                Label("Play Protected (FairPlay)", systemImage: "play.tv")
            }

            Button {
                NSWorkspace.shared.selectFile(recording.tdfURL.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show TDF Archive", systemImage: "doc.zipper")
            }

            Divider()

            // Iroh P2P Publishing
            Button {
                Task {
                    await publishToIroh(recording)
                }
            } label: {
                Label("Publish to Network", systemImage: "globe")
            }
            .disabled(isPublishing || !ArkavoIrohManager.shared.isReady)

            if recording.irohStatus.isPublished, let ticket = recording.irohStatus.contentTicket {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(ticket.ticket, forType: .string)
                } label: {
                    Label("Copy Content Ticket", systemImage: "doc.on.doc")
                }
            }
        }

        Divider()

        Button("View Provenance") {
            selectedRecording = recording
            showingProvenance = true
        }

        Button("Show in Finder") {
            NSWorkspace.shared.selectFile(recording.url.path, inFileViewerRootedAtPath: "")
        }

        Button("Share...") {
            let picker = NSSharingServicePicker(items: [recording.url])
            if let view = NSApp.keyWindow?.contentView {
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        }

        Divider()

        Button("Delete", role: .destructive) {
            recordingToDelete = recording
            showingDeleteConfirmation = true
        }
    }

    /// Protect a recording with TDF3
    private func protectRecording(_ recording: Recording) async {
        isProtecting = true
        defer { isProtecting = false }

        do {
            try await manager.protectRecording(recording, kasURL: kasURL)
            await manager.loadRecordings() // Refresh to show protection status
        } catch {
            protectionError = error.localizedDescription
            showingProtectionError = true
        }
    }

    /// Protect a recording with HLS segmentation for streaming playback
    private func protectRecordingHLS(_ recording: Recording) async {
        isProtecting = true
        defer { isProtecting = false }

        do {
            try await manager.protectRecordingHLS(recording, kasURL: kasURL)
            await manager.loadRecordings() // Refresh to show protection status
        } catch {
            protectionError = error.localizedDescription
            showingProtectionError = true
        }
    }

    /// Publish a TDF-protected recording to the Iroh P2P network
    private func publishToIroh(_ recording: Recording) async {
        isPublishing = true
        defer { isPublishing = false }

        guard let contentService = ArkavoIrohManager.shared.contentService else {
            publishError = "Iroh node not initialized. Please try again later."
            showingPublishError = true
            return
        }

        // Start security-scoped access for the recordings folder
        guard let folder = RecordingsFolderAccess.getBookmarkedFolder() else {
            publishError = "Recordings folder not selected. Please select a folder first."
            showingPublishError = true
            return
        }
        guard folder.startAccessingSecurityScopedResource() else {
            publishError = "Cannot access recordings folder. Please re-select the folder."
            showingPublishError = true
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        do {
            // Read TDF archive data
            let tdfData = try Data(contentsOf: recording.tdfURL)

            // Extract manifest from TDF
            let manifestJSON = try TDFArchiveReader.extractManifest(from: recording.tdfURL)
            let manifestLite = try TDFManifestLite.from(manifestJSON: manifestJSON)

            // Build TDFContentInfo
            let contentInfo = TDFContentInfo(
                id: recording.id,
                tdfData: tdfData,
                manifest: manifestLite,
                title: recording.title,
                mimeType: "video/quicktime",
                durationSeconds: recording.duration,
                originalFileSize: recording.fileSize,
                createdAt: recording.date
            )

            // Get creator public ID (use a placeholder for now - should come from authenticated user)
            // TODO: Get actual creator publicID from authenticated profile
            let creatorPublicID = Data(repeating: 0, count: 32)

            // Publish to Iroh
            print("🌐 Publishing to Iroh network...")
            let ticket = try await contentService.publishContentWithRetry(
                info: contentInfo,
                creatorPublicID: creatorPublicID
            )
            print("✅ Published with ticket: \(ticket.ticket)")

            // Cache the ticket
            await ContentTicketCache.shared.cache(ticket, for: ticket.contentID)

            // Show success
            publishedTicket = ticket
            showingPublishSuccess = true

            // Refresh recordings to update status
            await manager.loadRecordings()
        } catch {
            print("❌ Publish error: \(error)")
            publishError = error.localizedDescription
            showingPublishError = true
        }
    }

    /// Performs the actual deletion after confirmation
    private func confirmDelete() {
        guard let recording = recordingToDelete else { return }
        manager.deleteRecording(recording)
        recordingToDelete = nil
    }
}

// MARK: - Recording Card

struct RecordingCard: View {
    let recording: Recording
    @State private var thumbnail: NSImage?
    @State private var c2paStatus: Recording.C2PAStatus?
    @State private var tdfStatus: Recording.TDFProtectionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 150)
                        .cornerRadius(8)
                        .overlay {
                            ProgressView()
                        }
                }

                // Badges (top-left)
                VStack {
                    HStack(spacing: 4) {
                        // TDF Badge
                        if let status = tdfStatus, status.isProtected {
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.caption2)
                                Text("TDF3")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.blue.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .accessibilityIdentifier("TDF3Badge")
                        }

                        // C2PA Badge
                        if let status = c2paStatus, status.isSigned {
                            HStack(spacing: 4) {
                                Image(systemName: status.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                Text("C2PA")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(status.isValid ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .padding(8)
                    Spacer()
                }

                // Duration badge (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(recording.formattedDuration)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .padding(8)
                    }
                }
            }

            // Title
            Text(recording.title)
                .font(.headline)
                .lineLimit(1)

            // Metadata
            HStack(spacing: 12) {
                Label(recording.formattedDate, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Label(recording.formattedFileSize, systemImage: "doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let manager = RecordingsManager()
        if let image = await manager.generateThumbnail(for: recording) {
            thumbnail = image
        }
        // Check C2PA status
        c2paStatus = await manager.verifyC2PA(for: recording)
        // Check TDF protection status
        tdfStatus = await manager.checkTDFStatus(for: recording)
    }
}

// MARK: - Video Player

struct VideoPlayerView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(recording.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Video Player using native AVPlayerView wrapper
            AVPlayerViewRepresentable(url: recording.url)
                .frame(minWidth: 800, minHeight: 600)

            Divider()

            // Footer with actions
            HStack(spacing: 16) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(recording.url.path, inFileViewerRootedAtPath: "")
                }

                Button("Share...") {
                    let picker = NSSharingServicePicker(items: [recording.url])
                    if let view = NSApp.keyWindow?.contentView {
                        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
                    }
                }

                Spacer()

                Text(recording.formattedFileSize)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
        }
    }
}

// Custom AVPlayerView wrapper for macOS
struct AVPlayerViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .floating

        // Start security-scoped access on the recordings folder
        if let folder = RecordingsFolderAccess.getBookmarkedFolder() {
            _ = folder.startAccessingSecurityScopedResource()
        }

        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()

        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        // No updates needed
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
        // Stop security-scoped access
        if let folder = RecordingsFolderAccess.getBookmarkedFolder() {
            folder.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - Protected Video Player (FairPlay)

struct ProtectedVideoPlayerView: View {
    let recording: Recording
    let kasURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var manifestInfo: ManifestInfo?
    @State private var isPlaying = false
    @State private var player: AVPlayer?
    @State private var playbackError: String?
    @State private var isPreparingPlayback = false
    @State private var playbackStatus: String = ""

    init(recording: Recording, kasURL: URL) {
        self.recording = recording
        self.kasURL = kasURL
        print("🎬 ProtectedVideoPlayerView initialized for: \(recording.title)")
    }

    struct ManifestInfo {
        let algorithm: String
        let kasURL: String
        let protectedAt: String
        let payloadSize: String
        let hlsManifest: HLSManifest?
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recording.title)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Label("TDF3 Protected", systemImage: "lock.shield.fill")
                            .font(.caption)
                            .foregroundColor(.blue)

                        if let info = manifestInfo {
                            Text(info.algorithm)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading protected content...")
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 800, minHeight: 600)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)

                    Text("Playback Error")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(error)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(minWidth: 800, minHeight: 600)
            } else if isPlaying, let player {
                // Video player
                VideoPlayer(player: player)
                    .frame(minWidth: 800, minHeight: 600)
            } else {
                // Protected content info with Play button
                VStack(spacing: 24) {
                    Image(systemName: "play.tv.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.blue)

                    Text("FairPlay Protected Content")
                        .font(.title)
                        .fontWeight(.semibold)

                    if let info = manifestInfo {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(label: "Encryption", value: info.algorithm)
                            InfoRow(label: "KAS Server", value: info.kasURL)
                            InfoRow(label: "Protected At", value: info.protectedAt)
                            InfoRow(label: "TDF Size", value: info.payloadSize)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }

                    if let playbackError {
                        Text(playbackError)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    } else if isPreparingPlayback {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text(playbackStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("Click Play to decrypt and stream this content using your KAS credentials.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    HStack(spacing: 16) {
                        Button {
                            Task {
                                await startPlayback()
                            }
                        } label: {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreparingPlayback || manifestInfo == nil)

                        Button("Show TDF Archive") {
                            NSWorkspace.shared.selectFile(recording.tdfURL.path, inFileViewerRootedAtPath: "")
                        }
                    }
                }
                .frame(minWidth: 800, minHeight: 600)
            }

            Divider()

            // Footer
            HStack(spacing: 16) {
                if let info = manifestInfo {
                    Label(info.algorithm, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(recording.formattedFileSize)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .padding()
        }
        .accessibilityIdentifier("ProtectedPlayerView")
        .task {
            await loadManifest()
        }
    }

    private func loadManifest() async {
        print("📂 Loading manifest from: \(recording.tdfURL.path)")
        isLoading = true
        defer {
            isLoading = false
            print("📂 Manifest loading complete. isLoading = false")
        }

        // Get the bookmarked recordings directory for security-scoped access
        guard let recordingsDirectory = RecordingsFolderAccess.getBookmarkedFolder() else {
            print("❌ No bookmarked recordings folder")
            errorMessage = "Please re-select the recordings folder"
            return
        }

        // Start security-scoped access on the directory
        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            print("❌ Cannot access recordings directory")
            errorMessage = "Cannot access recordings folder"
            return
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        do {
            // Extract manifest from TDF ZIP archive
            print("📦 Extracting manifest from TDF archive...")
            let json = try TDFArchiveReader.extractManifest(from: recording.tdfURL)
            print("✅ Manifest extracted successfully: \(json.keys)")

            // Parse manifest
            let encInfo = json["encryptionInformation"] as? [String: Any]
            let method = encInfo?["method"] as? [String: Any]
            let keyAccess = (encInfo?["keyAccess"] as? [[String: Any]])?.first
            let meta = json["meta"] as? [String: Any]

            let algorithm = method?["algorithm"] as? String ?? "Unknown"
            let kasURLString = keyAccess?["url"] as? String ?? "Unknown"
            let protectedAt = meta?["protectedAt"] as? String ?? "Unknown"

            // Get TDF archive size
            let tdfAttrs = try? FileManager.default.attributesOfItem(atPath: recording.tdfURL.path)
            let tdfSize = tdfAttrs?[.size] as? Int64 ?? 0
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let tdfSizeString = formatter.string(fromByteCount: tdfSize)

            // Parse HLS manifest for playback
            var hlsManifest: HLSManifest?
            if let hlsInfo = meta?["hls"] as? [String: Any],
               let assetID = hlsInfo["assetId"] as? String,
               let segmentIVs = hlsInfo["segmentIVs"] as? [String],
               let wrappedKey = keyAccess?["wrappedKey"] as? String {
                let policy = encInfo?["policy"] as? String
                let policyBinding = keyAccess?["policyBinding"] as? [String: String]

                hlsManifest = HLSManifest(
                    assetID: assetID,
                    wrappedKey: wrappedKey,
                    algorithm: algorithm,
                    segmentIVs: segmentIVs,
                    segmentCount: hlsInfo["segmentCount"] as? Int ?? segmentIVs.count,
                    totalDuration: hlsInfo["totalDuration"] as? Double ?? 0,
                    encryptionMode: hlsInfo["encryptionMode"] as? String,
                    kasURL: URL(string: kasURLString) ?? kasURL,
                    policy: policy,
                    policyBindingAlg: policyBinding?["alg"],
                    policyBindingHash: policyBinding?["hash"]
                )
                print("✅ HLS manifest parsed: \(segmentIVs.count) segments")
            }

            manifestInfo = ManifestInfo(
                algorithm: algorithm,
                kasURL: kasURLString,
                protectedAt: protectedAt,
                payloadSize: tdfSizeString,
                hlsManifest: hlsManifest
            )
            print("✅ Manifest parsed: algorithm=\(algorithm), size=\(tdfSizeString)")
        } catch {
            print("❌ Manifest loading error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func startPlayback() async {
        guard let info = manifestInfo, let hlsManifest = info.hlsManifest else {
            playbackError = "No HLS manifest available"
            return
        }

        isPreparingPlayback = true
        playbackError = nil
        playbackStatus = "Loading TDF archive..."

        // Get the bookmarked recordings directory for security-scoped access
        guard let recordingsDirectory = RecordingsFolderAccess.getBookmarkedFolder() else {
            playbackError = "Please re-select the recordings folder"
            isPreparingPlayback = false
            return
        }

        guard recordingsDirectory.startAccessingSecurityScopedResource() else {
            playbackError = "Cannot access recordings folder"
            isPreparingPlayback = false
            return
        }
        defer { recordingsDirectory.stopAccessingSecurityScopedResource() }

        do {
            // Read TDF data
            let tdfData = try Data(contentsOf: recording.tdfURL)
            print("📂 Loaded TDF archive: \(tdfData.count) bytes")

            // Extract HLS content
            playbackStatus = "Extracting HLS segments..."
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hls-player-\(UUID().uuidString)")
            let extractor = HLSTDFExtractor(kasURL: kasURL)
            let localAsset = try await extractor.extract(tdfData: tdfData, outputDirectory: tempDir)
            print("✅ Extracted \(localAsset.segmentURLs.count) segments")

            // Get NTDF token for KAS authentication
            playbackStatus = "Authenticating with KAS..."
            guard let ntdfToken = KeychainManager.getAuthenticationToken() else {
                playbackError = "Not authenticated - please sign in first"
                isPreparingPlayback = false
                return
            }

            // Unwrap key from KAS
            playbackStatus = "Obtaining decryption key..."
            let symmetricKey = try await unwrapKeyFromKAS(manifest: hlsManifest, ntdfToken: ntdfToken)
            print("✅ Key unwrapped successfully")

            // Decrypt segments and create playable content
            playbackStatus = "Decrypting content..."
            let playableURL = try await decryptAndPreparePlayback(
                localAsset: localAsset,
                symmetricKey: symmetricKey,
                extractor: extractor
            )

            // Create player
            playbackStatus = "Starting playback..."
            let avPlayer = AVPlayer(url: playableURL)
            self.player = avPlayer
            isPlaying = true
            isPreparingPlayback = false

            // Start playback
            avPlayer.play()
            print("▶️ Playback started")

        } catch {
            print("❌ Playback error: \(error)")
            playbackError = error.localizedDescription
            isPreparingPlayback = false
        }
    }

    private func unwrapKeyFromKAS(manifest: HLSManifest, ntdfToken: String) async throws -> SymmetricKey {
        // Build TDFManifest from HLSManifest for KAS rewrap
        guard let policy = manifest.policy,
              let policyBindingAlg = manifest.policyBindingAlg,
              let policyBindingHash = manifest.policyBindingHash
        else {
            throw PlaybackError.missingPolicyData
        }

        // Create TDF manifest structures
        let policyBinding = TDFPolicyBinding(alg: policyBindingAlg, hash: policyBindingHash)

        let keyAccess = TDFKeyAccessObject(
            type: .wrapped,
            url: manifest.kasURL.absoluteString,
            protocolValue: .kas,
            wrappedKey: manifest.wrappedKey,
            policyBinding: policyBinding,
            encryptedMetadata: nil,
            kid: nil,
            sid: nil,
            schemaVersion: nil,
            ephemeralPublicKey: nil
        )

        let method = TDFMethodDescriptor(
            algorithm: manifest.algorithm,
            iv: manifest.segmentIVs.first ?? "",
            isStreamable: true
        )

        let encInfo = TDFEncryptionInformation(
            type: .split,
            keyAccess: [keyAccess],
            method: method,
            integrityInformation: nil,
            policy: policy
        )

        let payloadDescriptor = TDFPayloadDescriptor(
            type: .reference,
            url: "playlist.m3u8",
            protocolValue: .zip,
            isEncrypted: true,
            mimeType: "application/x-mpegURL"
        )

        let tdfManifest = TDFManifest(
            schemaVersion: "4.3.0",
            payload: payloadDescriptor,
            encryptionInformation: encInfo,
            assertions: nil
        )

        // Generate ephemeral P-256 key pair for ECDH
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let clientPublicKeyPEM = clientPrivateKey.publicKey.pemRepresentation

        // Create KAS rewrap client
        let kasClient = KASRewrapClient(
            kasURL: manifest.kasURL,
            oauthToken: ntdfToken
        )

        // Perform rewrap request
        print("🔑 Sending rewrap request to KAS...")
        let result = try await kasClient.rewrapTDF(
            manifest: tdfManifest,
            clientPublicKeyPEM: clientPublicKeyPEM
        )

        // Get wrapped key from result
        guard let wrappedKeyData = result.wrappedKeys.values.first else {
            throw PlaybackError.keyUnwrapFailed
        }

        // Extract session public key from PEM and unwrap
        guard let sessionPEM = result.sessionPublicKeyPEM else {
            throw PlaybackError.keyUnwrapFailed
        }

        let sessionKey = try extractCompressedKeyFromPEM(sessionPEM)

        // Unwrap using ECDH
        return try KASRewrapClient.unwrapKey(
            wrappedKey: wrappedKeyData,
            sessionPublicKey: sessionKey,
            clientPrivateKey: Data(clientPrivateKey.rawRepresentation)
        )
    }

    private func extractCompressedKeyFromPEM(_ pem: String) throws -> Data {
        let normalizedPEM = pem
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let markers = [
            "-----BEGIN PUBLIC KEY-----",
            "-----END PUBLIC KEY-----",
            "-----BEGIN EC PUBLIC KEY-----",
            "-----END EC PUBLIC KEY-----"
        ]

        var base64Content = normalizedPEM
        for marker in markers {
            base64Content = base64Content.replacingOccurrences(of: marker, with: "")
        }
        base64Content = base64Content.components(separatedBy: .whitespacesAndNewlines).joined()

        guard let keyData = Data(base64Encoded: base64Content) else {
            throw PlaybackError.invalidKASResponse
        }

        // Parse the key and return compressed form
        let publicKey: P256.KeyAgreement.PublicKey
        if keyData.count == 65, keyData[0] == 0x04 {
            publicKey = try P256.KeyAgreement.PublicKey(x963Representation: keyData)
        } else if keyData.count == 33, keyData[0] == 0x02 || keyData[0] == 0x03 {
            publicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: keyData)
        } else if keyData.count >= 70 {
            publicKey = try P256.KeyAgreement.PublicKey(derRepresentation: keyData)
        } else {
            throw PlaybackError.invalidKASResponse
        }

        return publicKey.compressedRepresentation
    }

    private func decryptAndPreparePlayback(
        localAsset: LocalHLSAsset,
        symmetricKey: SymmetricKey,
        extractor: HLSTDFExtractor
    ) async throws -> URL {
        // Create directory for decrypted content
        let decryptedDir = localAsset.outputDirectory.appendingPathComponent("decrypted")
        try FileManager.default.createDirectory(at: decryptedDir, withIntermediateDirectories: true)

        // Decrypt each segment
        for (index, segmentURL) in localAsset.segmentURLs.enumerated() {
            let encryptedData = try Data(contentsOf: segmentURL)
            let decryptedData = try await extractor.decryptSegment(
                segmentData: encryptedData,
                segmentIndex: index,
                symmetricKey: symmetricKey,
                manifest: localAsset.manifest
            )

            let decryptedURL = decryptedDir.appendingPathComponent("segment_\(index).mov")
            try decryptedData.write(to: decryptedURL)
        }

        // For single segment, play directly; for multiple, create playlist
        if localAsset.segmentURLs.count == 1 {
            return decryptedDir.appendingPathComponent("segment_0.mov")
        } else {
            // Create a simple playlist for concatenated playback
            // For now, just play the first segment
            return decryptedDir.appendingPathComponent("segment_0.mov")
        }
    }

    enum PlaybackError: Error, LocalizedError {
        case missingPolicyData
        case keyUnwrapFailed
        case invalidKASResponse
        case decryptionFailed

        var errorDescription: String? {
            switch self {
            case .missingPolicyData:
                "TDF manifest missing policy data"
            case .keyUnwrapFailed:
                "Failed to unwrap decryption key from KAS"
            case .invalidKASResponse:
                "Invalid response from KAS server"
            case .decryptionFailed:
                "Failed to decrypt content"
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

#Preview {
    RecordingsLibraryView()
}
