import Foundation

@MainActor
class VideoStreamCache: ObservableObject {
    private let maxCacheSize = 100
    private let cacheDirectory: URL
    @Published private(set) var cachedVideos: [(date: Date, url: URL)] = []

    private struct CacheMetadata: Codable {
        let date: Date
        let filename: String

        init(date: Date, filename: String) {
            self.date = date
            self.filename = filename
        }
    }

    init() {
        // Get the cache directory in the app's Documents folder
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cacheDirectory = documentsPath.appendingPathComponent("VideoCache", isDirectory: true)

        // Create cache directory if it doesn't exist
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                 withIntermediateDirectories: true)

        // Load existing cache metadata
        loadCacheMetadata()
    }

    private func loadCacheMetadata() {
        let metadataURL = cacheDirectory.appendingPathComponent("metadata.plist")
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? PropertyListDecoder().decode([CacheMetadata].self, from: data)
        {
            cachedVideos = metadata.map { meta in
                (meta.date, cacheDirectory.appendingPathComponent(meta.filename))
            }
        }
    }

    private func saveCacheMetadata() {
        let metadataURL = cacheDirectory.appendingPathComponent("metadata.plist")
        let metadata = cachedVideos.map {
            CacheMetadata(date: $0.date, filename: $0.url.lastPathComponent)
        }
        if let data = try? PropertyListEncoder().encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }

    func addVideo(_ data: Data) throws {
        // Generate unique filename
        let filename = "\(UUID().uuidString).mp4"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        // Save video data to file
        try data.write(to: fileURL)

        // Update cache list
        cachedVideos.append((Date(), fileURL))

        // Remove older videos if we exceed cache size
        if cachedVideos.count > maxCacheSize {
            cachedVideos.sort { $0.date > $1.date } // Sort by date, newest first

            // Remove excess files
            let toRemove = Array(cachedVideos.suffix(from: maxCacheSize))
            for item in toRemove {
                try? FileManager.default.removeItem(at: item.url)
            }

            cachedVideos = Array(cachedVideos.prefix(maxCacheSize))
        }

        // Save metadata
        saveCacheMetadata()
    }

    func clearCache() {
        // Remove all cached files
        for item in cachedVideos {
            try? FileManager.default.removeItem(at: item.url)
        }
        cachedVideos.removeAll()

        // Clear metadata
        saveCacheMetadata()
    }

    func getVideo(at index: Int) -> Data? {
        guard index < cachedVideos.count else { return nil }
        return try? Data(contentsOf: cachedVideos[index].url)
    }

    // Get video URL directly for more efficient playback
    func getVideoURL(at index: Int) -> URL? {
        guard index < cachedVideos.count else { return nil }
        return cachedVideos[index].url
    }
}
