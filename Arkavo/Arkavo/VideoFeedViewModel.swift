import ArkavoSocial
import AVFoundation
import Foundation
import OpenTDFKit
import SwiftUI

@MainActor
final class VideoFeedViewModel: ViewModel, VideoFeedUpdating, ObservableObject {
    let client: ArkavoClient
    let account: Account
    let profile: Profile
    @Published private(set) var videos: [Video] = []
    @Published var currentVideoIndex: Int = 0
    @Published var isLoading = false
    @Published var error: Error?
    @Published var connectionState: ArkavoClientState = .disconnected
    @Published var videoQueue = VideoMessageQueue()
    let playerManager = VideoPlayerManager()
    private var notificationObservers: [NSObjectProtocol] = []
    private var processedMessageIDs = Set<String>() // Track processed message IDs
    private var uniqueVideoIDs: Set<String> = Set() // Track video IDs

    init(client: ArkavoClient, account: Account, profile: Profile) {
        self.client = client
        self.account = account
        self.profile = profile
        setupNotifications()
        // Load initial videos
        Task {
            await loadVideos(count: 10)
        }
    }

    private func setupNotifications() {
//        print("VideoFeedViewModel: setupNotifications")
        // Clean up any existing observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        // Connection state changes
        let stateObserver = NotificationCenter.default.addObserver(
            forName: .arkavoClientStateChanged,
            object: nil,
            queue: nil,
        ) { [weak self] notification in
            guard let state = notification.userInfo?["state"] as? ArkavoClientState else { return }
            Task { @MainActor [weak self] in
                self?.connectionState = state
            }
        }
        notificationObservers.append(stateObserver)

        // Decrypted message handling
        let messageObserver = NotificationCenter.default.addObserver(
            forName: .messageDecrypted,
            object: nil,
            queue: nil,
        ) { [weak self] notification in
            guard let data = notification.userInfo?["data"] as? Data,
                  let header = notification.userInfo?["header"] as? Header,
                  let policy = notification.userInfo?["policy"] as? ArkavoPolicy else { return }

            Task { @MainActor [weak self] in
                await self?.handleDecryptedMessage(data: data, header: header, policy: policy)
            }
        }
        notificationObservers.append(messageObserver)

        // Error handling
        let errorObserver = NotificationCenter.default.addObserver(
            forName: .messageHandlingError,
            object: nil,
            queue: nil,
        ) { [weak self] notification in
            guard let error = notification.userInfo?["error"] as? Error else { return }
            Task { @MainActor [weak self] in
                self?.error = error
            }
        }
        notificationObservers.append(errorObserver)
    }

    private func loadVideos(count: Int = 1) async {
        isLoading = true
        defer { isLoading = false }

        // First try to load from stream
        if let videoStream = try? await getOrCreateVideoStream() {
            // Load any cached messages first
            let queueManager = ViewModelFactory.shared.serviceLocator.resolve() as MessageQueueManager
            let router = ViewModelFactory.shared.serviceLocator.resolve() as ArkavoMessageRouter

            // Try to load requested number of messages
            var loadedCount = 0
            while loadedCount < count {
                if let (messageId, message) = queueManager.getNextMessage(
                    ofType: 0x05,
                    forStream: videoStream.publicID,
                ) {
                    do {
                        try await router.processMessage(message.data, messageId: messageId)
                        loadedCount += 1
                    } catch {
                        print("Failed to process cached message: \(error)")
                    }
                } else {
                    break // No more messages available
                }
            }

            // If still haven't loaded enough videos, load from account video-stream thoughts
            if loadedCount < count {
                let remainingCount = count - loadedCount
                let relevantThoughts = videoStream.thoughts
                    .filter { $0.metadata.mediaType == .video }
                    .suffix(remainingCount)

                for thought in relevantThoughts {
                    try? await router.processMessage(thought.nano, messageId: thought.id)
                    loadedCount += 1
                }
            }
        } else {
            print("Could not find or create video stream")
        }
    }

    deinit {
        // Clean up observers
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func handleDecryptedMessage(data: Data, header: Header, policy: ArkavoPolicy) async {
        let messageID = header.ephemeralPublicKey.hexEncodedString()
        guard !processedMessageIDs.contains(messageID) else {
//            print("Message with ID \(messageID) already processed")
            return
        }
        processedMessageIDs.insert(messageID)

        do {
//            print("\nHandling decrypted video message:")
//            print("- Data size: \(data.count)")
//            print("- Policy type: \(policy.type)")

            // Verify this is a video message based on policy
            guard policy.type == .videoFrame else {
//                print("❌ Incorrect policy type")
                return
            }
            // using EPK as an ID
            let videoID = header.ephemeralPublicKey.hexEncodedString()
            // Create a temporary file URL in the cache directory for the video data
            let fileManager = FileManager.default
            let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let videoFileName = videoID + ".mp4" // Or appropriate extension
            let videoFileURL = cacheDir.appendingPathComponent(videoFileName)

            // Write the video data to the cache file
            try data.write(to: videoFileURL)
//            print("✅ Wrote video data to cache: \(videoFileURL)")

            // Analyze the video file after writing
//            let asset = AVURLAsset(url: videoFileURL)
//            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
//                let naturalSize = try await videoTrack.load(.naturalSize)
//                let transform = try await videoTrack.load(.preferredTransform)
//                let videoAngle = atan2(transform.b, transform.a)
//
//                print("\n📼 Decrypted Video Analysis:")
//                print("- File size: \(data.count) bytes")
//                print("- Natural size: \(naturalSize)")
//                print("- Aspect ratio: \(naturalSize.width / naturalSize.height)")
//                print("- Transform angle: \(videoAngle * 180 / .pi)°")
//                print("- Transform matrix: \(transform)")
//            }

            // Create contributor with metadata if available, or empty contributor if not
            let (contributor, streamPublicID): (Contributor, Data) = {
                guard let bodyData = header.policy.body?.body,
                      let metadata = try? ArkavoPolicy.parseMetadata(from: bodyData)
                else {
                    print("❌ Failed to parse metadata. Using default contributor and streamPublicID.")
                    return (Contributor(profilePublicID: Data(), role: "creator"), Data())
                }

                // Safely handle the related data conversion
                return (Contributor(profilePublicID: Data(metadata.creator), role: "creator"), Data(metadata.related))
            }()
            // Extract description from video metadata
            let asset = AVURLAsset(url: videoFileURL)
            let description = try await extractVideoDescription(from: asset) ?? ""
            // Create new video object using the cached file URL
            let video = Video(
                id: videoID,
                streamPublicID: streamPublicID,
                url: videoFileURL,
                contributors: [contributor],
                description: description,
            )

            // Add to queue
            await MainActor.run {
                addVideo(video)
            }

        } catch {
            print("❌ Error processing video: \(error)")
            await MainActor.run {
                self.error = error
            }
        }
    }

    func addVideo(_ video: Video) {
        guard !uniqueVideoIDs.contains(video.id) else { return }

        uniqueVideoIDs.insert(video.id)
        videoQueue.enqueueVideo(video)
        videos = videoQueue.videos // Let the queue manage the video array
    }

    private func extractVideoDescription(from asset: AVURLAsset) async throws -> String? {
//        print("📝 Attempting to extract description from video metadata")
        let metadata = try await asset.load(.metadata)
//        print("📝 Found \(metadata.count) metadata items")

        // Log all metadata items for debugging
//        for (index, item) in metadata.enumerated() {
//            print("📝 Metadata item \(index):")
//            print("  - Identifier: \(String(describing: item.identifier?.rawValue))")
//            if let value = try? await item.load(.value) {
//                print("  - Value: \(value)")
//            }
//        }

        // Check for both standard and custom identifier
        let descriptionItem = metadata.first { item in
            if let identifier = item.identifier?.rawValue {
                return identifier == AVMetadataIdentifier.commonIdentifierDescription.rawValue ||
                    identifier == "uiso/dscp"
            }
            return false
        }

        guard let descriptionItem else {
            print("❌ No description metadata found")
            return nil
        }

        let value = try await descriptionItem.load(.value) as? String
//        print("📝 Extracted description: \(value ?? "nil")")
        return value
    }

    func streams() -> [Stream] {
        let streams = account.streams.dropFirst(2).filter { $0.source == nil }
        return Array(streams)
    }

    func cleanupOldCacheFiles() {
        let fileManager = FileManager.default
        guard let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }

        do {
            let cacheContents = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles],
            )

            // Keep only the 20 most recent videos
            let oldFiles = cacheContents
                .filter { $0.pathExtension == "mp4" }
                .sorted { url1, url2 -> Bool in
                    let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                    return date1! > date2!
                }
                .dropFirst(20)

            for fileURL in oldFiles {
                try? fileManager.removeItem(at: fileURL)
            }
        } catch {
            print("Error cleaning cache: \(error)")
        }
    }

    func addNewVideo(from uploadResult: UploadResult, contributors: [Contributor]) {
        Task {
            do {
                // Get or create video stream
                let videoStream = try await getOrCreateVideoStream()

                // Create new video
                let newVideo = Video.from(uploadResult: uploadResult, contributors: contributors, streamPublicID: videoStream.publicID)

                // Create thought for the video
                let metadata = Thought.Metadata(
                    creatorPublicID: profile.publicID,
                    streamPublicID: videoStream.publicID,
                    mediaType: .video,
                    createdAt: Date(),
                    contributors: contributors,
                )

                // Convert video URL to data for storage
                let videoData = newVideo.url.absoluteString.data(using: .utf8) ?? Data()
                let thought = Thought(nano: videoData, metadata: metadata)

                // Add thought to stream
                videoStream.thoughts.append(thought)

                // Save changes to persistence
                try await PersistenceController.shared.saveChanges()

                // Update UI
                await MainActor.run {
                    videos.insert(newVideo, at: 0)
                    currentVideoIndex = 0
                }

                // Preload video
                try? await playerManager.preloadVideo(url: newVideo.url)

            } catch VideoStreamError.noVideoStream {
                print("No video stream exists and couldn't create one")
                self.error = VideoStreamError.noVideoStream
            } catch {
                print("Error adding video: \(error)")
                self.error = error
            }
        }
    }

    func getOrCreateVideoStream() async throws -> Stream {
        // First check for existing video stream
        if let existingStream = account.streams.first(where: { stream in
            stream.source?.metadata.mediaType == .video
        }) {
            return existingStream
        }
        throw VideoStreamError.noVideoStream
    }

    func preloadVideo(url: URL) {
        Task {
            do {
                try await playerManager.preloadVideo(url: url)
            } catch {
                self.error = error
            }
        }
    }
}

@MainActor
protocol VideoFeedUpdating: AnyObject {
    func addNewVideo(from result: UploadResult, contributors: [Contributor])
    func preloadVideo(url: URL)
}

// Extension to provide default implementation
@MainActor
extension VideoFeedUpdating {
    func preloadVideo(url _: URL) {
        // Optional default implementation
    }
}

// MARK: - Models

struct Video: Identifiable, Hashable {
    let id: String
    let streamPublicID: Data
    let url: URL
    let contributors: [Contributor]
    let description: String
    var nano: Data?

    // Conform to Hashable
    static func == (lhs: Video, rhs: Video) -> Bool {
        lhs.id == rhs.id // Compare based on the unique ID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id) // Use the unique ID for hashing
    }

    static func from(uploadResult: UploadResult, contributors: [Contributor], streamPublicID: Data) -> Video {
        Video(
            id: uploadResult.id,
            streamPublicID: streamPublicID,
            url: URL(string: uploadResult.playbackURL)!,
            contributors: contributors,
            description: Date().ISO8601Format(),
            nano: uploadResult.nano,
        )
    }

    // FIXME: this isn't working
    static func from(thought: Thought) -> Video? {
        Video(
            id: thought.id.uuidString,
            streamPublicID: thought.metadata.streamPublicID,
            url: URL(string: "nano://\(thought.publicID.base58EncodedString)/")!,
            contributors: thought.metadata.contributors,
            description: thought.metadata.createdAt.ISO8601Format(),
        )
    }
}

@MainActor
final class VideoMessageQueue {
    // MARK: - Constants

    private enum Constants {
        static let maxBufferAhead = 10 // Number of videos to keep ready
        static let maxBufferBehind = 5 // Number of viewed videos to keep
    }

    // MARK: - Types

    enum VideoQueueError: Error {
        case invalidIndex
        case videoNotFound
        case bufferEmpty
    }

    // MARK: - Properties

    private var viewedVideos: [Video] = [] // Videos already viewed, limited to maxBufferBehind
    private var pendingVideos: [Video] = [] // Videos ready to view, limited to maxBufferAhead
    private var currentIndex: Int = 0 // Index in the combined video array

    var videos: [Video] { viewedVideos + pendingVideos }
    var needsMoreVideos: Bool { pendingVideos.count < Constants.maxBufferAhead }

    // MARK: - Public Methods

    /// Add a new video to the pending queue
    func enqueueVideo(_ video: Video) {
        // Only add if we haven't hit the buffer limit
        if pendingVideos.count < Constants.maxBufferAhead {
            pendingVideos.append(video)
        }
    }

    /// Get the current video
    func currentVideo() throws -> Video {
        guard !videos.isEmpty else { throw VideoQueueError.bufferEmpty }
        guard currentIndex >= 0, currentIndex < videos.count else {
            throw VideoQueueError.invalidIndex
        }
        return videos[currentIndex]
    }

    /// Move to next video and maintain buffers
    func moveToNext() {
        guard currentIndex + 1 < videos.count else {
            return
        }

        // If moving forward, move current video to viewed
        if let currentVideo = try? currentVideo() {
            viewedVideos.append(currentVideo)
            // Only remove the first element if pendingVideos is not empty
            if !pendingVideos.isEmpty {
                pendingVideos.removeFirst()
            }

            // Maintain viewed buffer size
            while viewedVideos.count > Constants.maxBufferBehind {
                viewedVideos.removeFirst()
            }
        }

        currentIndex = min(currentIndex + 1, videos.count - 1)
    }

    /// Move to previous video
    func moveToPrevious() throws {
        guard currentIndex > 0 else {
            throw VideoQueueError.invalidIndex
        }

        currentIndex = max(0, currentIndex - 1)
    }

    /// Clear all videos
    func clear() {
        viewedVideos.removeAll()
        pendingVideos.removeAll()
        currentIndex = 0
    }

    /// Get current queue stats
    var stats: (viewed: Int, pending: Int, current: Int) {
        (viewedVideos.count, pendingVideos.count, currentIndex)
    }
}

extension VideoFeedViewModel {
    @MainActor
    func handleSwipe(_ direction: SwipeDirection) async {
//        print("Handling swipe: \(direction)")
        switch direction {
        case .up:
            if currentVideoIndex < videos.count - 1 {
//                print("Moving to next video")
                currentVideoIndex += 1
                videoQueue.moveToNext()
                if videoQueue.needsMoreVideos {
                    await loadVideos()
                }
                await prepareNextVideo()
            }
        case .down:
            if currentVideoIndex > 0 {
//                print("Moving to previous video")
                currentVideoIndex -= 1
                try? videoQueue.moveToPrevious()
                await prepareNextVideo()
            }
        }
    }

    @MainActor
    func prepareNextVideo() async {
        if videoQueue.stats.pending > 1 {
            let nextIndex = videoQueue.stats.current + 1
            if nextIndex < videoQueue.videos.count {
                let nextVideo = videoQueue.videos[nextIndex]
                do {
                    try await playerManager.preloadVideo(url: nextVideo.url)
                } catch {
                    print("Failed to preload video: \(error)")
                }
            }
        }
    }

    enum SwipeDirection {
        case up
        case down
    }
}
