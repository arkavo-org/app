import ArkavoMediaKit
import ArkavoSocial
import AVFoundation
import AVKit
import SwiftUI
import ZIPFoundation

// MARK: - FMP4 Video Player View

/// Video player view for fMP4/FairPlay TDF content
///
/// This view:
/// 1. Extracts fMP4 content (init.mp4, segments, playlist.m3u8) from TDF archive
/// 2. Sets up custom URL scheme resource loader to serve content
/// 3. Configures AVContentKeySession with TDFContentKeyDelegate for FairPlay
/// 4. Plays video with hardware-backed FairPlay decryption
@available(iOS 26.0, *)
struct FMP4VideoPlayerView: View {
    /// Raw TDF archive data containing fMP4 content
    let tdfData: Data

    /// TDF manifest lite with encryption info
    let manifest: TDFManifestLite

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FMP4PlayerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)

                        Text("Playback Error")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            Task {
                                await viewModel.load(tdfData: tdfData, manifest: manifest)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                } else if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text(viewModel.loadingMessage)
                            .foregroundColor(.gray)
                    }
                } else if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        viewModel.stop()
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            await viewModel.load(tdfData: tdfData, manifest: manifest)
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}

// MARK: - FMP4 Player View Model

@available(iOS 26.0, *)
@MainActor
final class FMP4PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var loadingMessage = "Preparing playback..."
    @Published var error: Error?

    private var contentKeySession: AVContentKeySession?
    private var keyDelegate: TDFContentKeyDelegate<TDFManifestLite>?
    private var httpServer: LocalHTTPServer?
    private var tempDirectory: URL?

    func load(tdfData: Data, manifest: TDFManifestLite) async {
        isLoading = true
        error = nil

        do {
            // 1. Create temp directory for extracted content
            loadingMessage = "Extracting content..."
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("fmp4-player-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir

            // 2. Extract fMP4 content from TDF archive
            try extractFMP4Content(from: tdfData, to: tempDir)

            // 3. Start local HTTP server
            loadingMessage = "Starting HTTP server..."
            let server = LocalHTTPServer(contentDirectory: tempDir)
            let baseURL = try server.start()
            httpServer = server
            print("🌐 HTTP server started at: \(baseURL)")

            // 4. Create asset with HTTP URL
            let playlistURL = baseURL.appendingPathComponent("playlist.m3u8")
            let asset = AVURLAsset(url: playlistURL)

            // 5. Set up FairPlay content key session
            loadingMessage = "Setting up FairPlay..."
            contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)

            // 6. Create key delegate with manifest
            let tdfManifestForDelegate = TDFManifestLite(
                kasURL: manifest.kasURL,
                wrappedKey: manifest.wrappedKey,
                algorithm: manifest.algorithm,
                iv: manifest.iv,
                assetID: manifest.assetID,
                protectedAt: manifest.protectedAt
            )
            keyDelegate = TDFContentKeyDelegate(manifest: tdfManifestForDelegate)
            contentKeySession?.setDelegate(keyDelegate, queue: .main)

            // 7. Add asset as content key recipient
            contentKeySession?.addContentKeyRecipient(asset)

            // 8. Proactively request the content key using asset ID
            loadingMessage = "Requesting decryption key..."
            let skdURI = "skd://\(manifest.assetID)"
            print("🔐 Proactively requesting content key for: \(skdURI)")
            contentKeySession?.processContentKeyRequest(
                withIdentifier: skdURI,
                initializationData: nil,
                options: nil
            )

            // 9. Create player
            loadingMessage = "Starting playback..."
            let playerItem = AVPlayerItem(asset: asset)
            let avPlayer = AVPlayer(playerItem: playerItem)

            self.player = avPlayer
            isLoading = false

            // Start playback
            avPlayer.play()
            print("▶️ fMP4/FairPlay playback started")

        } catch {
            print("❌ FMP4 playback error: \(error)")
            self.error = error
            isLoading = false
        }
    }

    func stop() {
        // 1. Stop player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        // 2. Stop HTTP server
        httpServer?.stop()
        httpServer = nil

        // 3. Clear FairPlay session
        contentKeySession = nil
        keyDelegate = nil

        // 4. Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
            print("🗑️ Cleaned up temp directory")
        }
    }

    /// Extract fMP4 content from TDF archive to temp directory
    private func extractFMP4Content(from tdfData: Data, to outputDir: URL) throws {
        guard let archive = try? Archive(data: tdfData, accessMode: .read) else {
            throw FMP4PlayerError.invalidArchive
        }

        var extractedFiles: [String] = []

        // Extract all files
        for entry in archive {
            let destinationURL = outputDir.appendingPathComponent(entry.path)

            // Create parent directories if needed
            let parentDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Extract file
            _ = try archive.extract(entry, to: destinationURL)
            extractedFiles.append(entry.path)
        }

        print("📦 Extracted \(extractedFiles.count) files: \(extractedFiles.joined(separator: ", "))")

        // Verify required files exist
        let playlistURL = outputDir.appendingPathComponent("playlist.m3u8")
        guard FileManager.default.fileExists(atPath: playlistURL.path) else {
            throw FMP4PlayerError.missingPlaylist
        }

        let initURL = outputDir.appendingPathComponent("init.mp4")
        guard FileManager.default.fileExists(atPath: initURL.path) else {
            throw FMP4PlayerError.missingInitSegment
        }
    }
}

// MARK: - FMP4 Content Server Helper

/// Helper for serving fMP4/HLS content from a local directory
/// Used by local HTTP server implementations for FairPlay playback
@available(iOS 26.0, *)
final class FMP4ContentServer: @unchecked Sendable {
    let contentDirectory: URL

    init(contentDirectory: URL) {
        self.contentDirectory = contentDirectory
    }

    /// Get file data for a given filename
    /// - Parameter filename: The file to read (e.g., "playlist.m3u8", "init.mp4", "segment0.m4s")
    /// - Returns: File data and content type, or nil if file doesn't exist
    func fileData(for filename: String) -> (data: Data, contentType: String)? {
        let fileURL = contentDirectory.appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return (data, mimeType(for: fileURL.pathExtension))
    }

    /// Get HTTP Content-Type header value for a file extension
    func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "m3u8":
            return "application/vnd.apple.mpegurl"
        case "mp4":
            return "video/mp4"
        case "m4s":
            return "video/iso.segment"
        case "mov":
            return "video/quicktime"
        case "ts":
            return "video/MP2T"
        default:
            return "application/octet-stream"
        }
    }

    /// List all files in the content directory
    var files: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: contentDirectory.path)) ?? []
    }
}

// MARK: - FMP4 Player Errors

enum FMP4PlayerError: Error, LocalizedError {
    case invalidArchive
    case missingPlaylist
    case missingInitSegment
    case extractionFailed(String)
    case serverStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "Invalid TDF archive"
        case .missingPlaylist:
            return "Missing playlist.m3u8"
        case .missingInitSegment:
            return "Missing init.mp4"
        case .extractionFailed(let reason):
            return "Extraction failed: \(reason)"
        case .serverStartFailed(let error):
            return "Failed to start content server: \(error.localizedDescription)"
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    FMP4VideoPlayerView(
        tdfData: Data(),
        manifest: TDFManifestLite(
            kasURL: "https://100.arkavo.net",
            wrappedKey: "test",
            algorithm: "AES-128-CBC",
            iv: "test",
            assetID: UUID().uuidString,
            protectedAt: ISO8601DateFormatter().string(from: Date())
        )
    )
}
