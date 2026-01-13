import AVFoundation
import Foundation

/// Custom URL scheme resource loader for serving fMP4/HLS content to AVPlayer
///
/// This loader intercepts requests using a custom URL scheme (arkavo-local://)
/// and serves content directly from a local directory, avoiding the need for an HTTP server.
final class LocalContentLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    /// Custom URL scheme for local content
    static let scheme = "arkavo-local"

    private let contentDirectory: URL
    private let queue = DispatchQueue(label: "com.arkavo.LocalContentLoader")

    /// Initialize with content directory
    /// - Parameter contentDirectory: Directory containing content files
    init(contentDirectory: URL) {
        self.contentDirectory = contentDirectory
        super.init()
    }

    /// Transform a file URL to use the custom scheme
    /// - Parameter filename: Filename within the content directory
    /// - Returns: URL with custom scheme
    func localURL(for filename: String) -> URL {
        // Create URL with custom scheme that encodes the file path
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "local"
        components.path = "/" + filename
        return components.url!
    }

    // MARK: - AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        // Handle only our custom scheme
        guard let url = loadingRequest.request.url,
              url.scheme == Self.scheme else {
            return false
        }

        queue.async { [weak self] in
            self?.handleLoadingRequest(loadingRequest)
        }

        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        // Request was cancelled, nothing to clean up
    }

    // MARK: - Request Handling

    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
        guard let url = loadingRequest.request.url else {
            loadingRequest.finishLoading(with: makeError(.invalidURL))
            return
        }

        // Extract file path from URL
        let filename = String(url.path.dropFirst()) // Remove leading /
        let fileURL = contentDirectory.appendingPathComponent(filename)

        print("📁 LocalContentLoader: \(filename)")

        // Check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("   ❌ Not found: \(fileURL.path)")
            loadingRequest.finishLoading(with: makeError(.fileNotFound))
            return
        }

        do {
            let fileData = try Data(contentsOf: fileURL)
            let contentType = mimeType(for: fileURL.pathExtension)

            // Handle content info request
            if let contentInfoRequest = loadingRequest.contentInformationRequest {
                contentInfoRequest.isByteRangeAccessSupported = true
                contentInfoRequest.contentLength = Int64(fileData.count)
                contentInfoRequest.contentType = contentType
            }

            // Handle data request
            if let dataRequest = loadingRequest.dataRequest {
                let requestedOffset = Int(dataRequest.requestedOffset)

                // When requestsAllDataToEndOfResource is true, serve all remaining data
                let availableLength = fileData.count - requestedOffset
                let respondLength: Int
                if dataRequest.requestsAllDataToEndOfResource {
                    respondLength = availableLength
                } else {
                    respondLength = min(dataRequest.requestedLength, availableLength)
                }

                if respondLength > 0 {
                    let responseData = fileData.subdata(in: requestedOffset..<(requestedOffset + respondLength))
                    dataRequest.respond(with: responseData)
                }

                print("   ✅ Served \(respondLength) bytes (offset: \(requestedOffset), allToEnd: \(dataRequest.requestsAllDataToEndOfResource))")
            }

            loadingRequest.finishLoading()

        } catch {
            print("   ❌ Error: \(error)")
            loadingRequest.finishLoading(with: error)
        }
    }

    private func mimeType(for pathExtension: String) -> String {
        // Return UTI strings for AVAssetResourceLoader content types
        switch pathExtension.lowercased() {
        case "m3u8":
            // HLS playlist UTI
            return "public.m3u-playlist"
        case "mp4", "m4s", "m4v", "m4a":
            // MPEG-4 and fMP4 segments
            return "public.mpeg-4"
        case "mov":
            return "com.apple.quicktime-movie"
        case "ts":
            return "public.mpeg-2-transport-stream"
        default:
            return "public.data"
        }
    }

    private func makeError(_ code: LoaderError) -> NSError {
        NSError(domain: "com.arkavo.LocalContentLoader",
                code: code.rawValue,
                userInfo: [NSLocalizedDescriptionKey: code.description])
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

// MARK: - Asset Factory

extension LocalContentLoader {
    /// Create an AVURLAsset configured to use this loader for a specific file
    /// - Parameter filename: Main content file (e.g., playlist.m3u8)
    /// - Returns: Configured AVURLAsset
    func createAsset(for filename: String) -> AVURLAsset {
        let url = localURL(for: filename)
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }
}
