import SwiftUI
import AVKit

struct RecordingsLibraryView: View {
    @StateObject private var manager = RecordingsManager()
    @State private var selectedRecording: Recording?
    @State private var showingPlayer = false
    @State private var showingProvenance = false
    @State private var showingDeleteConfirmation = false
    @State private var showingProtectedPlayer = false
    @State private var isProtecting = false
    @State private var protectionError: String?
    @State private var showingProtectionError = false
    @State private var recordingToDelete: Recording?
    @State private var gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)]

    private let kasURL = URL(string: "https://kas.arkavo.net")!

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
                                .onTapGesture {
                                    selectedRecording = recording
                                    showingPlayer = true
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
        .sheet(isPresented: $showingPlayer) {
            if let recording = selectedRecording {
                VideoPlayerView(recording: recording)
            }
        }
        .sheet(isPresented: $showingProvenance) {
            if let recording = selectedRecording {
                ProvenanceView(recording: recording)
            }
        }
        .sheet(isPresented: $showingProtectedPlayer) {
            if let recording = selectedRecording {
                ProtectedVideoPlayerView(recording: recording, kasURL: kasURL)
            }
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
        .overlay {
            if isProtecting {
                ZStack {
                    Color.black.opacity(0.5)
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Protecting video...")
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Encrypting with TDF3 for FairPlay streaming")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .ignoresSafeArea()
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
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Recordings Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start recording to see your videos here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func recordingContextMenu(for recording: Recording) -> some View {
        Button("Play") {
            selectedRecording = recording
            showingPlayer = true
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

        if FileManager.default.fileExists(atPath: recording.protectedURL.path) {
            Button {
                selectedRecording = recording
                showingProtectedPlayer = true
            } label: {
                Label("Play Protected (FairPlay)", systemImage: "play.tv")
            }

            Button {
                NSWorkspace.shared.selectFile(recording.manifestURL.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Show TDF Manifest", systemImage: "doc.text")
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

            // Video Player
            VideoPlayer(player: AVPlayer(url: recording.url))
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

// MARK: - Protected Video Player (FairPlay)

struct ProtectedVideoPlayerView: View {
    let recording: Recording
    let kasURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var manifestInfo: ManifestInfo?

    struct ManifestInfo {
        let algorithm: String
        let kasURL: String
        let protectedAt: String
        let payloadSize: String
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
            } else {
                // Protected content info (actual FairPlay playback requires server integration)
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
                            InfoRow(label: "Payload Size", value: info.payloadSize)
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Text("To play this content, a FairPlay license must be obtained from the KAS server.\nThe client app will request a CKC (Content Key Context) using the TDF manifest.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    HStack(spacing: 16) {
                        Button("Open Manifest") {
                            NSWorkspace.shared.open(recording.manifestURL)
                        }

                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(recording.protectedURL.path, inFileViewerRootedAtPath: "")
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
        .task {
            await loadManifest()
        }
    }

    private func loadManifest() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let manifestData = try Data(contentsOf: recording.manifestURL)
            guard let json = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
                throw NSError(domain: "Manifest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid manifest format"])
            }

            // Parse manifest
            let encInfo = json["encryptionInformation"] as? [String: Any]
            let method = encInfo?["method"] as? [String: Any]
            let keyAccess = (encInfo?["keyAccess"] as? [[String: Any]])?.first
            let meta = json["meta"] as? [String: Any]

            let algorithm = method?["algorithm"] as? String ?? "Unknown"
            let kasURLString = keyAccess?["url"] as? String ?? "Unknown"
            let protectedAt = meta?["protectedAt"] as? String ?? "Unknown"

            // Get payload size
            let payloadAttrs = try? FileManager.default.attributesOfItem(atPath: recording.protectedURL.path)
            let payloadSize = payloadAttrs?[.size] as? Int64 ?? 0
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useMB, .useGB]
            formatter.countStyle = .file
            let payloadSizeString = formatter.string(fromByteCount: payloadSize)

            manifestInfo = ManifestInfo(
                algorithm: algorithm,
                kasURL: kasURLString,
                protectedAt: protectedAt,
                payloadSize: payloadSizeString
            )
        } catch {
            errorMessage = error.localizedDescription
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
