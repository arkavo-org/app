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

        Button {
            Task {
                await protectRecordingFMP4(recording)
            }
        } label: {
            Label("Protect with FairPlay (fMP4)", systemImage: "lock.shield.fill")
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

    /// Protect a recording with fMP4/CBCS for true FairPlay hardware DRM
    private func protectRecordingFMP4(_ recording: Recording) async {
        isProtecting = true
        defer { isProtecting = false }

        do {
            try await manager.protectRecordingFMP4(recording, kasURL: kasURL)
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

// MARK: - AVPlayer Status Observer

/// Observer class for AVPlayer and AVPlayerItem status changes
/// Properly retains KVO observers to avoid premature deallocation
final class PlayerStatusObserver: NSObject {
    private var playerStatusObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var errorObservation: NSKeyValueObservation?

    var player: AVPlayer? {
        didSet {
            setupObservations()
        }
    }

    private func setupObservations() {
        // Clear old observations
        playerStatusObservation?.invalidate()
        itemStatusObservation?.invalidate()
        timeControlObservation?.invalidate()
        errorObservation?.invalidate()

        guard let player = player else { return }

        // Observe player status
        playerStatusObservation = player.observe(\.status, options: [.new, .initial]) { player, change in
            print("🎬 [Observer] AVPlayer status: \(player.status.rawValue) (\(player.status.description))")
            if player.status == .failed, let error = player.error {
                print("❌ [Observer] AVPlayer failed: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ [Observer] Domain: \(nsError.domain), Code: \(nsError.code)")
                    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                        print("❌ [Observer] Underlying: \(underlying)")
                    }
                }
            }
        }

        // Observe time control status (playing, paused, waiting)
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { player, _ in
            print("🎬 [Observer] TimeControlStatus: \(player.timeControlStatus.rawValue) (\(player.timeControlStatus.description))")
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                if let reason = player.reasonForWaitingToPlay {
                    print("⏳ [Observer] Waiting reason: \(reason.rawValue)")
                }
            }
        }

        // Observe current item for status changes
        if let item = player.currentItem {
            observeItem(item)
        }

        // Observe when current item changes
        errorObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            if let item = player.currentItem {
                self?.observeItem(item)
            }
        }
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemStatusObservation?.invalidate()

        itemStatusObservation = item.observe(\.status, options: [.new, .initial]) { item, _ in
            print("📼 [Observer] AVPlayerItem status: \(item.status.rawValue) (\(item.status.description))")
            if item.status == .failed, let error = item.error {
                print("❌ [Observer] AVPlayerItem failed: \(error.localizedDescription)")
                if let nsError = error as NSError? {
                    print("❌ [Observer] Domain: \(nsError.domain), Code: \(nsError.code)")
                    for (key, value) in nsError.userInfo {
                        print("❌ [Observer] UserInfo[\(key)]: \(value)")
                    }
                }
            }

            // Log error logs when status changes
            if let errorLog = item.errorLog() {
                for event in errorLog.events {
                    print("📊 [Observer] Error event: \(event.errorComment ?? "nil"), code: \(event.errorStatusCode), domain: \(event.errorDomain)")
                }
            }
        }
    }

    func cleanup() {
        playerStatusObservation?.invalidate()
        itemStatusObservation?.invalidate()
        timeControlObservation?.invalidate()
        errorObservation?.invalidate()
        player = nil
    }
}

extension AVPlayer.Status {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

extension AVPlayerItem.Status {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .readyToPlay: return "readyToPlay"
        case .failed: return "failed"
        @unknown default: return "unknown(\(rawValue))"
        }
    }
}

extension AVPlayer.TimeControlStatus {
    var description: String {
        switch self {
        case .paused: return "paused"
        case .waitingToPlayAtSpecifiedRate: return "waiting"
        case .playing: return "playing"
        @unknown default: return "unknown(\(rawValue))"
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
    @State private var contentKeySession: AVContentKeySession?
    @State private var keyDelegate: TDFContentKeyDelegate?
    @State private var useFairPlay = false  // FairPlay requires SAMPLE-AES; using local decryption
    @State private var httpServer: LocalHTTPServer?
    @State private var tempDirectory: URL?
    @State private var playerObserver: PlayerStatusObserver?

    init(recording: Recording, kasURL: URL) {
        self.recording = recording
        self.kasURL = kasURL
        print("🎬 ProtectedVideoPlayerView initialized for: \(recording.title)")
    }

    /// Content format detected in TDF archive
    enum ContentFormat {
        case hls           // AES-128-CBC full segment encryption
        case fmp4          // CBCS 1:9 pattern encryption (FairPlay)

        var displayName: String {
            switch self {
            case .hls: return "HLS (AES-CBC)"
            case .fmp4: return "fMP4 (FairPlay CBCS)"
            }
        }
    }

    /// fMP4/FairPlay manifest info
    struct FMP4Manifest {
        let assetID: String
        let wrappedKey: String
        let algorithm: String
        let iv: String
        let kasURL: URL
        let playlistFilename: String
        let initFilename: String
        let segmentFilenames: [String]
    }

    struct ManifestInfo {
        let algorithm: String
        let kasURL: String
        let protectedAt: String
        let payloadSize: String
        let contentFormat: ContentFormat
        let hlsManifest: HLSManifest?
        let fmp4Manifest: FMP4Manifest?
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
                            Text(info.contentFormat.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(info.contentFormat == .fmp4 ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                                .cornerRadius(4)

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
        .onDisappear {
            // Clean up resources when view is dismissed
            player?.pause()
            player = nil

            // Stop HTTP server
            httpServer?.stop()
            httpServer = nil

            // Clear FairPlay session
            contentKeySession = nil
            keyDelegate = nil

            // Clean up temp directory
            if let tempDir = tempDirectory {
                try? FileManager.default.removeItem(at: tempDir)
                tempDirectory = nil
                print("🗑️ Cleaned up temp directory")
            }
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

            // Detect content format and parse manifest
            var hlsManifest: HLSManifest?
            var fmp4Manifest: FMP4Manifest?
            var contentFormat: ContentFormat = .hls

            // Try to extract fMP4 metadata from multiple locations:
            // 1. encryptedMetadata in keyAccess (TDF spec compliant)
            // 2. meta.fmp4 or meta.fairplay (legacy)
            var fmp4Info: [String: Any]?

            // Check encryptedMetadata first (TDF spec compliant)
            if let encryptedMetadataBase64 = keyAccess?["encryptedMetadata"] as? String,
               let encryptedMetadataData = Data(base64Encoded: encryptedMetadataBase64),
               let decoded = try? JSONSerialization.jsonObject(with: encryptedMetadataData) as? [String: Any],
               decoded["type"] as? String == "fmp4-fairplay" {
                fmp4Info = decoded
                print("📋 Found fMP4 metadata in encryptedMetadata")
            }
            // Fall back to legacy meta.fmp4 or meta.fairplay
            else if let legacyInfo = meta?["fmp4"] as? [String: Any] ?? meta?["fairplay"] as? [String: Any] {
                fmp4Info = legacyInfo
                print("📋 Found fMP4 metadata in legacy meta field")
            }

            // Check for fMP4/FairPlay format
            if let fmp4Info,
               let assetID = fmp4Info["assetId"] as? String,
               let wrappedKey = keyAccess?["wrappedKey"] as? String {

                let ivString = (method?["iv"] as? String) ?? ""
                let playlistFilename = fmp4Info["playlistFilename"] as? String ?? "playlist.m3u8"
                let initFilename = fmp4Info["initFilename"] as? String ?? "init.mp4"
                let segmentFilenames = fmp4Info["segmentFilenames"] as? [String] ?? ["segment0.m4s"]

                fmp4Manifest = FMP4Manifest(
                    assetID: assetID,
                    wrappedKey: wrappedKey,
                    algorithm: algorithm,
                    iv: ivString,
                    kasURL: URL(string: kasURLString) ?? kasURL,
                    playlistFilename: playlistFilename,
                    initFilename: initFilename,
                    segmentFilenames: segmentFilenames
                )
                contentFormat = .fmp4
                print("✅ fMP4/FairPlay manifest parsed: \(segmentFilenames.count) segments")
                print("   Asset ID: \(assetID)")
                print("   Playlist: \(playlistFilename)")
                print("   Init: \(initFilename)")
                print("   IV from manifest: '\(ivString)' (length: \(ivString.count))")
            }
            // Fall back to HLS format
            else if let hlsInfo = meta?["hls"] as? [String: Any],
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
                contentFormat = .hls
                print("✅ HLS manifest parsed: \(segmentIVs.count) segments")
            }

            manifestInfo = ManifestInfo(
                algorithm: algorithm,
                kasURL: kasURLString,
                protectedAt: protectedAt,
                payloadSize: tdfSizeString,
                contentFormat: contentFormat,
                hlsManifest: hlsManifest,
                fmp4Manifest: fmp4Manifest
            )
            print("✅ Manifest parsed: format=\(contentFormat.displayName), algorithm=\(algorithm), size=\(tdfSizeString)")
        } catch {
            print("❌ Manifest loading error: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    private func startPlayback() async {
        guard let info = manifestInfo else {
            playbackError = "No manifest available"
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
            // Get NTDF token for KAS authentication
            playbackStatus = "Authenticating with KAS..."
            guard let ntdfToken = KeychainManager.getAuthenticationToken() else {
                playbackError = "Not authenticated - please sign in first"
                isPreparingPlayback = false
                return
            }

            // Route to appropriate playback method based on content format
            switch info.contentFormat {
            case .fmp4:
                guard let fmp4Manifest = info.fmp4Manifest else {
                    playbackError = "No fMP4 manifest available"
                    isPreparingPlayback = false
                    return
                }
                try await startFMP4Playback(fmp4Manifest: fmp4Manifest, authToken: ntdfToken)

            case .hls:
                guard let hlsManifest = info.hlsManifest else {
                    playbackError = "No HLS manifest available"
                    isPreparingPlayback = false
                    return
                }
                try await startHLSPlayback(hlsManifest: hlsManifest, authToken: ntdfToken)
            }

        } catch {
            print("❌ Playback error: \(error)")
            playbackError = error.localizedDescription
            isPreparingPlayback = false
        }
    }

    /// fMP4/FairPlay playback - extracts and plays with hardware DRM
    private func startFMP4Playback(fmp4Manifest: FMP4Manifest, authToken: String) async throws {
        playbackStatus = "Extracting fMP4 content..."
        print("🎬 Starting fMP4/FairPlay playback...")

        // Extract fMP4 content to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fmp4-player-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        // Use TDFArchiveReader to extract all files
        let files = try TDFArchiveReader.extractAllFiles(from: recording.tdfURL, to: tempDir)
        print("✅ Extracted \(files.count) files to: \(tempDir.path)")
        for file in files {
            print("   - \(file.lastPathComponent)")
        }

        // Find the playlist file
        let localPlaylistPath = tempDir.appendingPathComponent(fmp4Manifest.playlistFilename)
        guard FileManager.default.fileExists(atPath: localPlaylistPath.path) else {
            throw FMP4PlaybackError.missingPlaylist(fmp4Manifest.playlistFilename)
        }

        // Fix playlist: Inject IV from manifest if missing
        // FairPlay requires the IV to be explicit in the playlist for correct decryption
        print("🔧 Manifest IV: '\(fmp4Manifest.iv)' (length: \(fmp4Manifest.iv.count))")
        if !fmp4Manifest.iv.isEmpty {
            var playlistContent = try String(contentsOf: localPlaylistPath, encoding: .utf8)
            print("📄 Original playlist:\n\(playlistContent)")

            // Convert IV to Hex if it looks like Base64 (TDF usually uses Base64)
            var hexIV = fmp4Manifest.iv

            // Check for Base64 vs Hex format
            // Base64: 22-24 chars for 16 bytes (varies with padding)
            // Hex: 32 chars for 16 bytes
            if !hexIV.hasPrefix("0x") {
                // Try Base64 first - it's shorter than hex for same data
                // Base64 of 16 bytes = ceil(16*8/6) = 22 chars + up to 2 padding = 22-24
                if hexIV.count >= 22 && hexIV.count <= 24 {
                    // Ensure proper padding for Base64 decoding
                    var padded = hexIV
                    while padded.count % 4 != 0 {
                        padded += "="
                    }
                    if let data = Data(base64Encoded: padded), data.count == 16 {
                        hexIV = "0x" + data.map { String(format: "%02X", $0) }.joined()
                        print("🔧 Converted Base64 IV to Hex: \(hexIV)")
                    } else {
                        // Not valid Base64, treat as hex
                        hexIV = "0x" + hexIV.uppercased()
                        print("🔧 Added 0x prefix to IV: \(hexIV)")
                    }
                } else if hexIV.count == 32 {
                    // Already hex, just add prefix
                    hexIV = "0x" + hexIV.uppercased()
                    print("🔧 Added 0x prefix to hex IV: \(hexIV)")
                } else {
                    // Unknown format, add prefix and hope for the best
                    hexIV = "0x" + hexIV.uppercased()
                    print("⚠️ Unknown IV format (length: \(fmp4Manifest.iv.count)), added 0x prefix: \(hexIV)")
                }
            } else {
                print("🔧 IV already has 0x prefix: \(hexIV)")
            }

            // Check if IV is already present
            if !playlistContent.contains("IV=") {
                print("🔧 Injecting IV into playlist: \(hexIV)")
                // Regex to find the #EXT-X-KEY line and append IV
                // Pattern matches: #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://..." ...
                // We want to insert IV=0x... after the URI
                let pattern = #"(#EXT-X-KEY:[^\n]*URI="[^"]+")"#
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let range = NSRange(location: 0, length: playlistContent.utf16.count)

                let originalContent = playlistContent
                playlistContent = regex.stringByReplacingMatches(
                    in: playlistContent,
                    options: [],
                    range: range,
                    withTemplate: "$1,IV=\(hexIV)"
                )

                if playlistContent != originalContent {
                    print("✅ IV injected successfully")
                    print("📄 Modified playlist:\n\(playlistContent)")
                    try playlistContent.write(to: localPlaylistPath, atomically: true, encoding: .utf8)
                } else {
                    print("⚠️ Regex did not match #EXT-X-KEY line - IV not injected")
                    // Try to show what lines exist for debugging
                    let lines = playlistContent.components(separatedBy: "\n")
                    for line in lines where line.contains("EXT-X-KEY") {
                        print("   Found key line: \(line)")
                    }
                }
            } else {
                print("ℹ️ IV already present in playlist, skipping injection")
            }
        } else {
            print("⚠️ Manifest IV is empty, cannot inject")
        }

        // Start local HTTP server to serve fMP4 content
        playbackStatus = "Starting HTTP server..."
        let server = LocalHTTPServer(contentDirectory: tempDir)
        do {
            let baseURL = try server.start()
            httpServer = server
            print("🌐 HTTP server started at: \(baseURL)")
        } catch {
            throw FMP4PlaybackError.serverStartFailed(error)
        }

        // Create asset with HTTP URL
        guard let baseURL = server.baseURL else {
            throw FMP4PlaybackError.serverStartFailed(LocalHTTPServer.ServerError.notStarted)
        }
        let playlistURL = baseURL.appendingPathComponent(fmp4Manifest.playlistFilename)
        let asset = AVURLAsset(url: playlistURL)

        // Set up FairPlay content key session
        playbackStatus = "Setting up FairPlay..."
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        contentKeySession = session

        // Create key delegate with manifest info
        let hlsManifest = HLSManifestLite(
            kasURL: fmp4Manifest.kasURL.absoluteString,
            wrappedKey: fmp4Manifest.wrappedKey,
            algorithm: fmp4Manifest.algorithm,
            iv: fmp4Manifest.iv,
            assetID: fmp4Manifest.assetID
        )
        let delegate = TDFContentKeyDelegate(
            manifest: hlsManifest,
            authToken: authToken,
            serverURL: fmp4Manifest.kasURL
        )
        keyDelegate = delegate
        session.setDelegate(delegate, queue: .main)

        // Add asset as content key recipient
        session.addContentKeyRecipient(asset)

        // Wait for the content key to be delivered before starting playback
        playbackStatus = "Requesting decryption key..."
        let skdURI = "skd://\(fmp4Manifest.assetID)"
        print("🔐 Proactively requesting content key for: \(skdURI)")

        // Use continuation to await key delivery
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.onKeyDelivered = {
                print("✅ Content key delivered, starting playback...")
                continuation.resume()
            }
            delegate.onKeyFailed = { error in
                print("❌ Content key failed: \(error)")
                continuation.resume(throwing: error)
            }

            // Trigger the key request
            session.processContentKeyRequest(
                withIdentifier: skdURI,
                initializationData: nil,
                options: nil
            )
        }

        // Create player AFTER key is delivered
        playbackStatus = "Starting playback..."
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer
        isPlaying = true
        isPreparingPlayback = false

        // Set up proper status observation using retained observer
        let observer = PlayerStatusObserver()
        observer.player = avPlayer
        self.playerObserver = observer

        // Add notification observers for additional error events
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                print("❌ [Notification] AVPlayerItem failed to play to end: \(error.localizedDescription)")
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: playerItem,
            queue: .main
        ) { notification in
            if let item = notification.object as? AVPlayerItem,
               let errorLog = item.errorLog(),
               let lastEvent = errorLog.events.last {
                print("❌ [Notification] Error log entry: \(lastEvent.errorComment ?? "Unknown") (code: \(lastEvent.errorStatusCode), domain: \(lastEvent.errorDomain))")
            }
        }

        // Check for immediate errors
        if playerItem.status == .failed {
            print("❌ PlayerItem failed immediately: \(playerItem.error?.localizedDescription ?? "Unknown")")
        }

        // Start playback
        avPlayer.play()
        print("▶️ fMP4/FairPlay playback started")

        // Log detailed playback status after delays
        for delay in [1.0, 3.0, 5.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak avPlayer, weak playerItem] in
                guard let avPlayer = avPlayer, let playerItem = playerItem else { return }
                print("📊 [\(delay)s] AVPlayer status: \(avPlayer.status.description), timeControl: \(avPlayer.timeControlStatus.description)")
                print("📊 [\(delay)s] PlayerItem status: \(playerItem.status.description), duration: \(playerItem.duration.seconds)s")
                print("📊 [\(delay)s] Current time: \(avPlayer.currentTime().seconds)s, rate: \(avPlayer.rate)")
                if let error = playerItem.error {
                    print("❌ [\(delay)s] PlayerItem error: \(error.localizedDescription)")
                    if let nsError = error as NSError? {
                        print("❌ [\(delay)s] Domain: \(nsError.domain), Code: \(nsError.code)")
                        for (key, value) in nsError.userInfo {
                            print("❌ [\(delay)s] UserInfo[\(key)]: \(value)")
                        }
                    }
                }
                if let accessLog = playerItem.accessLog() {
                    print("📊 [\(delay)s] Access log: \(accessLog.events.count) events")
                    for event in accessLog.events {
                        print("   - URI: \(event.uri ?? "nil"), bytes: \(event.numberOfBytesTransferred), duration: \(event.durationWatched)s")
                    }
                }
                if let errorLog = playerItem.errorLog() {
                    print("📊 [\(delay)s] Error log: \(errorLog.events.count) events")
                    for event in errorLog.events {
                        print("   - Error: \(event.errorComment ?? "nil"), code: \(event.errorStatusCode), domain: \(event.errorDomain)")
                    }
                }
            }
        }
    }

    enum FMP4PlaybackError: Error, LocalizedError {
        case missingPlaylist(String)
        case serverStartFailed(Error)

        var errorDescription: String? {
            switch self {
            case .missingPlaylist(let filename):
                return "Playlist not found: \(filename)"
            case .serverStartFailed(let error):
                return "Failed to start content server: \(error.localizedDescription)"
            }
        }
    }

    /// HLS playback - extracts and plays with optional FairPlay or local decryption
    private func startHLSPlayback(hlsManifest: HLSManifest, authToken: String) async throws {
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

        if useFairPlay {
            // FairPlay playback - hardware decryption via Secure Enclave
            try await startFairPlayPlayback(
                hlsManifest: hlsManifest,
                localAsset: localAsset,
                authToken: authToken
            )
        } else {
            // Local decryption fallback
            try await startLocalDecryptionPlayback(
                hlsManifest: hlsManifest,
                localAsset: localAsset,
                extractor: extractor,
                authToken: authToken
            )
        }
    }

    /// FairPlay playback using AVContentKeySession
    private func startFairPlayPlayback(
        hlsManifest: HLSManifest,
        localAsset: LocalHLSAsset,
        authToken: String
    ) async throws {
        playbackStatus = "Setting up FairPlay..."
        print("🔐 Starting FairPlay playback...")

        // Create FairPlay manifest for key delegate
        let manifest = HLSManifestLite(
            kasURL: hlsManifest.kasURL.absoluteString,
            wrappedKey: hlsManifest.wrappedKey,
            algorithm: hlsManifest.algorithm,
            iv: hlsManifest.segmentIVs.first ?? "",
            assetID: hlsManifest.assetID
        )

        // Create content key session with FairPlay
        let session = AVContentKeySession(keySystem: .fairPlayStreaming)
        contentKeySession = session

        // Create key delegate
        let delegate = TDFContentKeyDelegate(
            manifest: manifest,
            authToken: authToken,
            serverURL: kasURL
        )
        keyDelegate = delegate
        session.setDelegate(delegate, queue: .main)

        // Use the first segment or playlist URL
        let assetURL = localAsset.playlistURL
        let asset = AVURLAsset(url: assetURL)

        // Add asset as content key recipient - this triggers key request
        session.addContentKeyRecipient(asset)

        playbackStatus = "Requesting FairPlay key..."
        print("🔐 Asset added as content key recipient")

        // Create player
        let playerItem = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: playerItem)
        self.player = avPlayer

        playbackStatus = "Starting playback..."
        isPlaying = true
        isPreparingPlayback = false

        avPlayer.play()
        print("▶️ FairPlay playback started")
    }

    /// Local decryption playback (fallback)
    private func startLocalDecryptionPlayback(
        hlsManifest: HLSManifest,
        localAsset: LocalHLSAsset,
        extractor: HLSTDFExtractor,
        authToken: String
    ) async throws {
        // Unwrap key from KAS
        playbackStatus = "Obtaining decryption key..."
        let symmetricKey = try await unwrapKeyFromKAS(manifest: hlsManifest, ntdfToken: authToken)
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
        print("▶️ Local decryption playback started")
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

        // Generate ephemeral P-256 key pair for ECDH and JWT signing
        let clientPrivateKey = P256.KeyAgreement.PrivateKey()

        // Create KAS rewrap client
        let kasClient = KASRewrapClient(
            kasURL: manifest.kasURL,
            oauthToken: ntdfToken
        )

        // Perform rewrap request - the same key is used for:
        // 1. clientPublicKey in request (derived from clientPrivateKey)
        // 2. JWT signing (converted to P256.Signing key)
        // 3. ECDH unwrap of response (using clientPrivateKey)
        print("🔑 Sending RSA rewrap request to KAS: \(manifest.kasURL.appendingPathComponent("v2/rewrap"))")
        let result = try await kasClient.rewrapTDF(
            manifest: tdfManifest,
            clientPrivateKey: clientPrivateKey
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
