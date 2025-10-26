import SwiftUI
import AVKit

struct RecordingsLibraryView: View {
    @StateObject private var manager = RecordingsManager()
    @State private var selectedRecording: Recording?
    @State private var showingPlayer = false
    @State private var showingProvenance = false
    @State private var gridColumns = [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 16)]

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
        .onAppear {
            manager.loadRecordings()
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

            Button(action: {
                manager.loadRecordings()
            }) {
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
            manager.deleteRecording(recording)
        }
    }
}

// MARK: - Recording Card

struct RecordingCard: View {
    let recording: Recording
    @State private var thumbnail: NSImage?
    @State private var c2paStatus: Recording.C2PAStatus?

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

                // C2PA Badge (top-left)
                VStack {
                    HStack {
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
                            .padding(8)
                        }
                        Spacer()
                    }
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

#Preview {
    RecordingsLibraryView()
}
