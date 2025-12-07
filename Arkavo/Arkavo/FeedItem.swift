import Foundation

/// Unified feed item that can represent either a VOD video or a live stream
enum FeedItem: Identifiable, Hashable {
    case video(Video)
    case liveStream(LiveStream)

    var id: String {
        switch self {
        case let .video(video):
            return video.id
        case let .liveStream(stream):
            return stream.id
        }
    }

    var isLive: Bool {
        if case .liveStream = self {
            return true
        }
        return false
    }

    var contributors: [Contributor] {
        switch self {
        case let .video(video):
            return video.contributors
        case let .liveStream(stream):
            return stream.contributors
        }
    }

    var description: String {
        switch self {
        case let .video(video):
            return video.description
        case let .liveStream(stream):
            return stream.title
        }
    }

    var streamPublicID: Data? {
        switch self {
        case let .video(video):
            return video.streamPublicID
        case let .liveStream(stream):
            return stream.creatorPublicID
        }
    }

    // MARK: - Hashable

    static func == (lhs: FeedItem, rhs: FeedItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Convenience Accessors

extension FeedItem {
    /// Get the video if this is a video item
    var video: Video? {
        if case let .video(video) = self {
            return video
        }
        return nil
    }

    /// Get the live stream if this is a live stream item
    var liveStream: LiveStream? {
        if case let .liveStream(stream) = self {
            return stream
        }
        return nil
    }
}
