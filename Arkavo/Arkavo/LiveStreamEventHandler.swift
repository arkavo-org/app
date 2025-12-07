import Combine
import FlatBuffers
import Foundation

/// Handles WebSocket events for live stream discovery
@MainActor
final class LiveStreamEventHandler: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var activeStreams: [LiveStream] = []

    // MARK: - Private Properties

    private let defaultRTMPURL = "rtmp://100.arkavo.net:1935"

    // MARK: - Singleton

    static let shared = LiveStreamEventHandler()

    private init() {}

    // MARK: - Public Methods

    /// Handle incoming WebSocket message (called from customMessageCallback)
    func handleWebSocketMessage(_ data: Data) {
        // Check message type prefix
        guard data.count > 1 else { return }

        let messageType = data[0]

        // Handle event messages (0x06)
        if messageType == 0x06 {
            let eventData = data.suffix(from: 1)
            parseStreamEvent(Data(eventData))
        }
    }

    /// Manually add a live stream (for testing or direct notifications)
    func addLiveStream(_ stream: LiveStream) {
        guard !activeStreams.contains(where: { $0.streamKey == stream.streamKey }) else {
            return
        }
        activeStreams.insert(stream, at: 0)
        NotificationCenter.default.post(
            name: .liveStreamStarted,
            object: nil,
            userInfo: ["stream": stream]
        )
    }

    /// Remove a live stream by stream key
    func removeLiveStream(streamKey: String) {
        activeStreams.removeAll { $0.streamKey == streamKey }
        NotificationCenter.default.post(
            name: .liveStreamStopped,
            object: nil,
            userInfo: ["streamKey": streamKey]
        )
    }

    /// Clear all active streams
    func clearAllStreams() {
        activeStreams.removeAll()
    }

    // MARK: - Private Methods

    private func parseStreamEvent(_ data: Data) {
        // Parse FlatBuffers event
        var buffer = ByteBuffer(data: data)
        let event = Arkavo_Event(buffer, o: Int32(buffer.read(def: UInt32.self, position: 0)))

        // Check if this is a stream event based on action
        // We'll use RouteEvent with specific payload format for stream events
        guard event.dataType == .routeevent,
              let routeEvent: Arkavo_RouteEvent = event.data(type: Arkavo_RouteEvent.self)
        else {
            return
        }

        // Parse stream event from RouteEvent payload
        let payload = Data(routeEvent.payload)
        guard !payload.isEmpty else { return }

        // Payload format: [1 byte event type] [rest is JSON or structured data]
        let eventType = payload[0]
        let eventData = payload.suffix(from: 1)

        switch eventType {
        case 0x01: // Stream started
            parseStreamStarted(Data(eventData), sourceId: Data(routeEvent.sourceId))
        case 0x02: // Stream stopped
            parseStreamStopped(Data(eventData))
        default:
            break
        }
    }

    private func parseStreamStarted(_ data: Data, sourceId: Data) {
        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streamKey = json["stream_key"] as? String
        else {
            return
        }

        let rtmpURL = json["rtmp_url"] as? String ?? defaultRTMPURL
        let manifestHeader = json["manifest_header"] as? String ?? ""
        let title = json["title"] as? String ?? "Live Stream"

        // Extract stream name from key (format: "app/stream_name")
        let streamName = streamKey.contains("/") ? streamKey : "live/\(streamKey)"

        let stream = LiveStream(
            streamKey: streamKey,
            rtmpURL: rtmpURL,
            streamName: streamName,
            creatorPublicID: sourceId,
            manifestHeader: manifestHeader,
            startedAt: Date(),
            contributors: [Contributor(profilePublicID: sourceId, role: "creator")],
            title: title
        )

        addLiveStream(stream)
    }

    private func parseStreamStopped(_ data: Data) {
        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streamKey = json["stream_key"] as? String
        else {
            return
        }

        removeLiveStream(streamKey: streamKey)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let liveStreamStarted = Notification.Name("liveStreamStarted")
    static let liveStreamStopped = Notification.Name("liveStreamStopped")
}
