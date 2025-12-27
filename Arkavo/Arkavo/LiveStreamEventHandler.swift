import Combine
import Foundation

#if canImport(ArkavoStreaming)
    import ArkavoStreaming
#endif

/// Handles WebSocket events for live stream discovery
@MainActor
final class LiveStreamEventHandler: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var activeStreams: [LiveStream] = []

    // MARK: - Private Properties

    private let defaultRTMPURL = "rtmp://100.arkavo.net:1935"
    private let defaultStreamName = "live/creator"
    private var checkTask: Task<Void, Never>?

    // MARK: - Singleton

    static let shared = LiveStreamEventHandler()

    private init() { /* Singleton: prevents external instantiation */ }

    // MARK: - Public Methods

    /// Handle incoming WebSocket message (called from customMessageCallback)
    func handleWebSocketMessage(_ data: Data) {
        // Check message type prefix
        guard data.count > 1 else { return }

        let messageType = data[0]

        // Handle CBOR messages (0x08) - new stream events
        if messageType == 0x08 {
            let cborData = data.suffix(from: 1)
            parseCborStreamEvent(Data(cborData))
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

    /// Check if the default Arkavo live stream is being published
    /// This bypasses WebSocket discovery and directly checks the RTMP server
    func checkForArkavoLiveStream() {
        // Don't start another check if one is already in progress
        guard checkTask == nil else { return }

        // Skip if we already have this stream
        guard !activeStreams.contains(where: { $0.streamName == defaultStreamName }) else {
            return
        }

        checkTask = Task {
            await performStreamCheck()
            checkTask = nil
        }
    }

    /// Stop any ongoing stream check
    func stopStreamCheck() {
        checkTask?.cancel()
        checkTask = nil
    }

    // MARK: - Private Methods

    private func performStreamCheck() async {
        #if canImport(ArkavoStreaming)
            let subscriber = RTMPSubscriber()

            do {
                // Try to connect and play - if the stream exists, we'll connect successfully
                try await subscriber.connect(url: defaultRTMPURL, streamName: defaultStreamName)

                // Wait briefly and check if we're in a playing state
                try await Task.sleep(for: .milliseconds(500))

                // Check if we got a state indicating success
                let state = await subscriber.currentState

                if state == .playing || state == .connected {
                    // Stream is live! Add it to active streams
                    let stream = LiveStream(
                        streamKey: defaultStreamName,
                        rtmpURL: defaultRTMPURL,
                        streamName: defaultStreamName,
                        creatorPublicID: Data(),
                        manifestHeader: "",
                        startedAt: Date(),
                        contributors: [],
                        title: "Live Stream"
                    )
                    addLiveStream(stream)
                    print("LiveStreamEventHandler: Detected live stream at \(defaultStreamName)")
                }

                await subscriber.disconnect()
            } catch {
                // Stream not available or connection failed - this is expected when no stream is live
                print("LiveStreamEventHandler: No live stream detected (\(error.localizedDescription))")
            }
        #endif
    }

    /// Parse CBOR-encoded stream event
    private func parseCborStreamEvent(_ data: Data) {
        // Use simple CBOR parser for stream events
        guard let decoded = SimpleCborParser.parse(data),
              let type = decoded["type"] as? String
        else {
            print("LiveStreamEventHandler: Failed to parse CBOR stream event")
            return
        }

        switch type {
        case "stream_started":
            handleStreamStarted(decoded)
        case "stream_stopped":
            handleStreamStopped(decoded)
        default:
            print("LiveStreamEventHandler: Unknown stream event type: \(type)")
        }
    }

    private func handleStreamStarted(_ event: [String: Any]) {
        guard let streamKey = event["stream_key"] as? String else {
            print("LiveStreamEventHandler: stream_started missing stream_key")
            return
        }

        let rtmpURL = event["rtmp_url"] as? String ?? defaultRTMPURL
        let manifestHeader = event["manifest_header"] as? String ?? ""
        let title = event["title"] as? String ?? "Live Stream"

        // Extract stream name from key (format: "app/stream_name")
        let streamName = streamKey.contains("/") ? streamKey : "live/\(streamKey)"

        // Use empty data for creator ID (no source_id in simple stream events)
        let creatorID = Data()

        let stream = LiveStream(
            streamKey: streamKey,
            rtmpURL: rtmpURL,
            streamName: streamName,
            creatorPublicID: creatorID,
            manifestHeader: manifestHeader,
            startedAt: Date(),
            contributors: [],
            title: title
        )

        addLiveStream(stream)
        print("LiveStreamEventHandler: Stream started - \(streamKey)")
    }

    private func handleStreamStopped(_ event: [String: Any]) {
        guard let streamKey = event["stream_key"] as? String else {
            print("LiveStreamEventHandler: stream_stopped missing stream_key")
            return
        }

        removeLiveStream(streamKey: streamKey)
        print("LiveStreamEventHandler: Stream stopped - \(streamKey)")
    }
}

// MARK: - Simple CBOR Parser

/// Minimal CBOR parser for simple map structures used in stream events
/// Only supports: maps, strings, unsigned integers, and null
enum SimpleCborParser {
    static func parse(_ data: Data) -> [String: Any]? {
        var offset = 0
        return parseMap(data, offset: &offset)
    }

    private static func parseMap(_ data: Data, offset: inout Int) -> [String: Any]? {
        guard offset < data.count else { return nil }

        let majorType = (data[offset] & 0xE0) >> 5
        let additionalInfo = data[offset] & 0x1F

        // Must be a map (major type 5)
        guard majorType == 5 else { return nil }

        offset += 1
        let count: Int

        if additionalInfo < 24 {
            count = Int(additionalInfo)
        } else if additionalInfo == 24 {
            guard offset < data.count else { return nil }
            count = Int(data[offset])
            offset += 1
        } else if additionalInfo == 25 {
            guard offset + 1 < data.count else { return nil }
            count = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
        } else {
            // Indefinite length or larger sizes not supported
            return nil
        }

        var result: [String: Any] = [:]

        for _ in 0 ..< count {
            guard let key = parseString(data, offset: &offset) else { return nil }
            guard let value = parseValue(data, offset: &offset) else { return nil }
            result[key] = value
        }

        return result
    }

    private static func parseString(_ data: Data, offset: inout Int) -> String? {
        guard offset < data.count else { return nil }

        let majorType = (data[offset] & 0xE0) >> 5
        let additionalInfo = data[offset] & 0x1F

        // Must be a text string (major type 3)
        guard majorType == 3 else { return nil }

        offset += 1
        let length: Int

        if additionalInfo < 24 {
            length = Int(additionalInfo)
        } else if additionalInfo == 24 {
            guard offset < data.count else { return nil }
            length = Int(data[offset])
            offset += 1
        } else if additionalInfo == 25 {
            guard offset + 1 < data.count else { return nil }
            length = Int(data[offset]) << 8 | Int(data[offset + 1])
            offset += 2
        } else {
            return nil
        }

        guard offset + length <= data.count else { return nil }
        let stringData = data[offset ..< offset + length]
        offset += length

        return String(data: stringData, encoding: .utf8)
    }

    private static func parseValue(_ data: Data, offset: inout Int) -> Any? {
        guard offset < data.count else { return nil }

        let majorType = (data[offset] & 0xE0) >> 5

        switch majorType {
        case 0: // Unsigned integer
            return parseUnsignedInt(data, offset: &offset)
        case 3: // Text string
            return parseString(data, offset: &offset)
        case 5: // Map
            return parseMap(data, offset: &offset)
        case 7: // Simple values (null, bool, etc)
            let additionalInfo = data[offset] & 0x1F
            offset += 1
            if additionalInfo == 22 {
                return NSNull() // null
            } else if additionalInfo == 20 {
                return false
            } else if additionalInfo == 21 {
                return true
            }
            return nil
        default:
            return nil
        }
    }

    private static func parseUnsignedInt(_ data: Data, offset: inout Int) -> UInt64? {
        guard offset < data.count else { return nil }

        let additionalInfo = data[offset] & 0x1F
        offset += 1

        if additionalInfo < 24 {
            return UInt64(additionalInfo)
        } else if additionalInfo == 24 {
            guard offset < data.count else { return nil }
            let value = UInt64(data[offset])
            offset += 1
            return value
        } else if additionalInfo == 25 {
            guard offset + 1 < data.count else { return nil }
            let value = UInt64(data[offset]) << 8 | UInt64(data[offset + 1])
            offset += 2
            return value
        } else if additionalInfo == 26 {
            guard offset + 3 < data.count else { return nil }
            var value = UInt64(data[offset]) << 24
            value |= UInt64(data[offset + 1]) << 16
            value |= UInt64(data[offset + 2]) << 8
            value |= UInt64(data[offset + 3])
            offset += 4
            return value
        } else if additionalInfo == 27 {
            guard offset + 7 < data.count else { return nil }
            var value = UInt64(data[offset]) << 56
            value |= UInt64(data[offset + 1]) << 48
            value |= UInt64(data[offset + 2]) << 40
            value |= UInt64(data[offset + 3]) << 32
            value |= UInt64(data[offset + 4]) << 24
            value |= UInt64(data[offset + 5]) << 16
            value |= UInt64(data[offset + 6]) << 8
            value |= UInt64(data[offset + 7])
            offset += 8
            return value
        }

        return nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let liveStreamStarted = Notification.Name("liveStreamStarted")
    static let liveStreamStopped = Notification.Name("liveStreamStopped")
}
