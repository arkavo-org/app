import ArkavoSocial
import SwiftUI
import ZIPFoundation

// MARK: - Content Detail View

/// Detailed view for a single content descriptor
/// Allows fetching the full TDF payload from Iroh
struct ContentDetailView: View {
    let descriptor: ContentDescriptor
    @Environment(\.dismiss) private var dismiss
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var tdfData: Data?
    @State private var payloadURL: URL?
    @State private var extractedManifest: TDFManifestLite?
    @State private var isExtracting = false
    @State private var showingVideoPlayer = false
    @State private var isHLSContent = false
    @State private var isFMP4Content = false
    @State private var showingHLSVideoPlayer = false
    @State private var showingFMP4VideoPlayer = false

    /// Get NTDF token for KAS authentication
    /// This token is issued by authnz-rs during WebAuthn registration
    /// and can be validated by KAS for rewrap requests
    private var ntdfToken: String {
        KeychainManager.getAuthenticationToken() ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(height: 200)

                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)

                            Text("TDF Protected")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    // Title
                    Text(descriptor.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        ContentInfoRow(label: "Type", value: descriptor.mimeType)

                        if let duration = descriptor.durationSeconds {
                            ContentInfoRow(label: "Duration", value: formatDuration(duration))
                        }

                        ContentInfoRow(label: "Original Size", value: formatSize(descriptor.originalFileSize))
                        ContentInfoRow(label: "TDF Size", value: formatSize(descriptor.payloadSize))
                        ContentInfoRow(label: "Protected", value: formatDate(descriptor.manifest.protectedAt))
                        ContentInfoRow(label: "Encryption", value: descriptor.manifest.algorithm)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Fetch button
                    if tdfData == nil {
                        Button {
                            Task { await fetchContent() }
                        } label: {
                            HStack {
                                if isFetching {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text(isFetching ? "Fetching..." : "Fetch Content")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isFetching)
                    } else {
                        VStack(spacing: 12) {
                            Label("Content fetched (\(formatSize(Int64(tdfData!.count))))",
                                  systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)

                            // Play button - prepare and play
                            if payloadURL == nil {
                                Button {
                                    Task { await extractAndPrepare() }
                                } label: {
                                    HStack {
                                        if isExtracting {
                                            ProgressView()
                                                .tint(.white)
                                        } else {
                                            Image(systemName: "play.fill")
                                        }
                                        Text(isExtracting ? "Preparing..." : "Play Video")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                .disabled(isExtracting)
                            } else {
                                Button {
                                    showingVideoPlayer = true
                                } label: {
                                    Label("Play Video", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.green)
                                        .foregroundColor(.white)
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }

                    if let error = fetchError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Content Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingVideoPlayer) {
                if let url = payloadURL, let manifest = extractedManifest {
                    TDFVideoPlayerView(payloadURL: url, manifest: manifest)
                }
            }
            .fullScreenCover(isPresented: $showingHLSVideoPlayer) {
                if let tdfData, isHLSContent {
                    HLSTDFVideoPlayerView(
                        tdfData: tdfData,
                        kasURL: URL(string: descriptor.manifest.kasURL)!,
                        assetID: descriptor.manifest.assetID,
                        ntdfToken: ntdfToken
                    )
                }
            }
            .fullScreenCover(isPresented: $showingFMP4VideoPlayer) {
                if let tdfData, isFMP4Content {
                    FMP4VideoPlayerView(
                        tdfData: tdfData,
                        manifest: descriptor.manifest
                    )
                }
            }
        }
    }

    /// Extract manifest and payload from TDF archive, write payload to temp file
    private func extractAndPrepare() async {
        isExtracting = true
        fetchError = nil
        defer { isExtracting = false }

        guard let tdfData else {
            fetchError = "No TDF data available"
            return
        }

        do {
            // Check content type by looking at archive contents
            let contentType = detectContentType(tdfData)

            if contentType == .fmp4 {
                // fMP4/FairPlay content - use the fMP4 player
                isFMP4Content = true
                showingFMP4VideoPlayer = true
            } else if contentType == .hls {
                // HLS content with segment encryption - use HLS player
                isHLSContent = true
                showingHLSVideoPlayer = true
            } else {
                // Standard TDF - extract and play with FairPlay
                let (manifest, payload) = try TDFArchiveReader.extractAll(from: tdfData)
                extractedManifest = manifest

                // Write payload to temp file for AVPlayer
                // Use .mov extension for QuickTime or .ts for MPEG-TS
                let fileExtension = descriptor.mimeType.contains("quicktime") ? "mov" : "ts"
                payloadURL = try TDFArchiveReader.writePayloadToTempFile(payload, fileExtension: fileExtension)
            }

        } catch {
            fetchError = "Failed to prepare video: \(error.localizedDescription)"
        }
    }

    /// Content types that can be in a TDF archive
    private enum TDFContentType {
        case fmp4       // fMP4/FairPlay with init.mp4 + segments
        case hls        // HLS with segment encryption
        case standard   // Standard TDF with single payload
    }

    /// Detect content type by examining archive contents
    private func detectContentType(_ data: Data) -> TDFContentType {
        guard let archive = try? Archive(data: data, accessMode: .read) else {
            return .standard
        }

        let hasPlaylist = archive["playlist.m3u8"] != nil
        let hasInitMP4 = archive["init.mp4"] != nil

        if hasPlaylist && hasInitMP4 {
            // fMP4/FairPlay content (has both playlist and init segment)
            return .fmp4
        } else if hasPlaylist {
            // HLS with segment encryption (playlist but no init.mp4)
            return .hls
        } else {
            // Standard TDF payload
            return .standard
        }
    }

    private func fetchContent() async {
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        guard let service = await ArkavoIrohManager.shared.contentService else {
            fetchError = "Iroh not initialized"
            return
        }

        do {
            tdfData = try await service.fetchPayloadWithRetry(
                payloadTicket: descriptor.payloadTicket
            )
        } catch {
            fetchError = error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return isoString
    }
}

// MARK: - Content Info Row

private struct ContentInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentDetailView(
        descriptor: ContentDescriptor(
            id: UUID(),
            contentID: Data(repeating: 0, count: 32),
            creatorPublicID: Data(repeating: 1, count: 32),
            manifest: TDFManifestLite(
                kasURL: "https://100.arkavo.net/kas",
                wrappedKey: "base64key",
                algorithm: "AES-128-CBC",
                iv: "base64iv",
                assetID: UUID().uuidString,
                protectedAt: ISO8601DateFormatter().string(from: Date())
            ),
            payloadTicket: "blobaaaa...",
            payloadSize: 52_428_800,
            title: "Sample Video Recording",
            mimeType: "video/quicktime",
            durationSeconds: 125.5,
            originalFileSize: 104_857_600,
            createdAt: Date(),
            updatedAt: Date(),
            version: 1
        )
    )
}
