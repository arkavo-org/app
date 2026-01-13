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
    private var keyDelegate: TDFContentKeyDelegate?
    private var contentLoader: FMP4ContentLoader?
    private var tempDirectory: URL?

    func load(tdfData: Data, manifest: TDFManifestLite) async {
        isLoading = true
        error = nil
        loadingMessage = "Extracting content..."

        do {
            // 1. Create temp directory for extracted content
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("fmp4-player-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir

            // 2. Extract fMP4 content from TDF archive
            loadingMessage = "Extracting fMP4 segments..."
            try extractFMP4Content(from: tdfData, to: tempDir)

            // 3. Create content loader for custom URL scheme
            loadingMessage = "Setting up player..."
            let loader = FMP4ContentLoader(contentDirectory: tempDir)
            contentLoader = loader

            // 4. Create FairPlay content key session
            contentKeySession = AVContentKeySession(keySystem: .fairPlayStreaming)

            // 5. Create key delegate with manifest
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

            // 6. Create asset with custom URL scheme
            let asset = loader.createAsset(for: "playlist.m3u8")

            // 7. Add asset as content key recipient
            contentKeySession?.addContentKeyRecipient(asset)

            // 8. Proactively request the content key using asset ID
            loadingMessage = "Requesting decryption key..."
            contentKeySession?.processContentKeyRequest(
                withIdentifier: manifest.assetID,
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

        } catch {
            self.error = error
            isLoading = false
        }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil

        contentKeySession = nil
        keyDelegate = nil
        contentLoader = nil

        // Clean up temp directory
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
    }

    /// Extract fMP4 content from TDF archive to temp directory
    private func extractFMP4Content(from tdfData: Data, to outputDir: URL) throws {
        guard let archive = try? Archive(data: tdfData, accessMode: .read) else {
            throw FMP4PlayerError.invalidArchive
        }

        // Extract all files except manifest.json
        for entry in archive {
            // Skip manifest.json (we already have the parsed manifest)
            guard entry.path != "manifest.json" else { continue }

            let destinationURL = outputDir.appendingPathComponent(entry.path)

            // Create parent directories if needed
            let parentDir = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Extract file
            _ = try archive.extract(entry, to: destinationURL)
            print("📦 Extracted: \(entry.path)")
        }
    }
}

// MARK: - FMP4 Content Loader

/// Custom URL scheme resource loader for serving fMP4/HLS content to AVPlayer
@available(iOS 26.0, *)
final class FMP4ContentLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// Custom URL scheme for local content
    static let scheme = "arkavo-fmp4"

    private let contentDirectory: URL
    private let queue = DispatchQueue(label: "com.arkavo.FMP4ContentLoader")

    init(contentDirectory: URL) {
        self.contentDirectory = contentDirectory
        super.init()
    }

    /// Transform a file URL to use the custom scheme
    func localURL(for filename: String) -> URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "local"
        components.path = "/" + filename
        return components.url!
    }

    /// Create an AVURLAsset configured to use this loader
    func createAsset(for filename: String) -> AVURLAsset {
        let url = localURL(for: filename)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url,
              url.scheme == Self.scheme else {
            return false
        }

        queue.async { [weak self] in
            self?.handleLoadingRequest(loadingRequest)
        }

        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        // Request cancelled, nothing to clean up
    }

    // MARK: - Request Handling

    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url else {
            print("🔴 FMP4ContentLoader: Invalid URL in request")
            loadingRequest.finishLoading(with: makeError(.invalidURL))
            return
        }

        // Extract file path from URL
        let filename = String(url.path.dropFirst()) // Remove leading /
        let fileURL = contentDirectory.appendingPathComponent(filename)

        // Diagnostic logging
        print("📁 FMP4ContentLoader: \(filename)")
        print("   📋 contentInfoRequest: \(loadingRequest.contentInformationRequest != nil)")
        print("   📋 dataRequest: \(loadingRequest.dataRequest != nil)")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("   ❌ Not found: \(fileURL.path)")
            loadingRequest.finishLoading(with: makeError(.fileNotFound))
            return
        }

        do {
            let fileData = try Data(contentsOf: fileURL)
            let contentType = mimeType(for: fileURL.pathExtension)

            print("   📊 File size: \(fileData.count) bytes, contentType: \(contentType)")

            // Handle content info request
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                contentInfoRequest.isByteRangeAccessSupported = true
                contentInfoRequest.contentLength = Int64(fileData.count)
                contentInfoRequest.contentType = contentType
                print("   ℹ️  Set content info: length=\(fileData.count), type=\(contentType)")
            }

            // Handle data request
            if let dataRequest = loadingRequest.dataRequest {
                let requestedOffset = Int(dataRequest.requestedOffset)
                let requestedLength = dataRequest.requestedLength
                let requestsAllData = dataRequest.requestsAllDataToEndOfResource

                print("   📥 Data request: offset=\(requestedOffset), length=\(requestedLength), allToEnd=\(requestsAllData)")

                // Validate offset is within bounds
                guard requestedOffset >= 0, requestedOffset < fileData.count else {
                    print("   ⚠️  Offset \(requestedOffset) out of bounds for file size \(fileData.count)")
                    loadingRequest.finishLoading()
                    return
                }

                let availableLength = fileData.count - requestedOffset

                // FIX: Respect requestsAllDataToEndOfResource flag
                let respondLength: Int
                if requestsAllData {
                    respondLength = availableLength
                } else {
                    respondLength = min(requestedLength, availableLength)
                }

                if respondLength > 0 {
                    let responseData = fileData.subdata(in: requestedOffset..<(requestedOffset + respondLength))
                    dataRequest.respond(with: responseData)
                }

                print("   ✅ Served \(respondLength) bytes (offset: \(requestedOffset), available: \(availableLength))")
            }

            loadingRequest.finishLoading()

        } catch {
            print("   ❌ Error reading file: \(error)")
            loadingRequest.finishLoading(with: error)
        }
    }

    private func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "m3u8":
            return "public.m3u-playlist"
        case "mp4":
            return "public.mpeg-4"
        case "m4s":
            return "public.mpeg-4"
        case "mov":
            return "public.movie"
        case "ts":
            return "public.mpeg-2-transport-stream"
        default:
            return "public.data"
        }
    }

    private func makeError(_ code: LoaderError) -> NSError {
        NSError(
            domain: "com.arkavo.FMP4ContentLoader",
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: code.description]
        )
    }

    enum LoaderError: Int {
        case invalidURL = 1
        case fileNotFound = 2
        case readError = 3

        var description: String {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .fileNotFound: return "File not found"
            case .readError: return "Error reading file"
            }
        }
    }
}

// MARK: - FMP4 Player Errors

enum FMP4PlayerError: Error, LocalizedError {
    case invalidArchive
    case missingPlaylist
    case missingInitSegment
    case extractionFailed(String)

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
