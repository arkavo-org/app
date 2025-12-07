import Foundation

/// Represents an active live stream in the feed
struct LiveStream: Identifiable, Hashable {
    let id: String
    let streamKey: String
    let rtmpURL: String
    let streamName: String
    let creatorPublicID: Data
    let manifestHeader: String
    let startedAt: Date
    var contributors: [Contributor]
    var title: String

    init(
        id: String? = nil,
        streamKey: String,
        rtmpURL: String,
        streamName: String,
        creatorPublicID: Data,
        manifestHeader: String,
        startedAt: Date = Date(),
        contributors: [Contributor] = [],
        title: String = "Live Stream"
    ) {
        self.id = id ?? "live-\(streamKey)"
        self.streamKey = streamKey
        self.rtmpURL = rtmpURL
        self.streamName = streamName
        self.creatorPublicID = creatorPublicID
        self.manifestHeader = manifestHeader
        self.startedAt = startedAt
        self.contributors = contributors
        self.title = title
    }

    static func == (lhs: LiveStream, rhs: LiveStream) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// Event types for live stream lifecycle
enum LiveStreamEventType {
    case started(LiveStream)
    case stopped(streamKey: String)
}

/// Actions for stream events (maps to FlatBuffers Arkavo_Action)
enum StreamEventAction: Int8 {
    case unused = 0
    case started = 9  // New action for stream started
    case stopped = 10 // New action for stream stopped
}
