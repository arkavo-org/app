import Foundation

/// Generates HLS playlists (.m3u8) for TDF3-protected content
public struct HLSPlaylistGenerator {
    private let kasBaseURL: URL
    private let cdnBaseURL: URL

    public init(kasBaseURL: URL, cdnBaseURL: URL) {
        self.kasBaseURL = kasBaseURL
        self.cdnBaseURL = cdnBaseURL
    }

    /// Generate master playlist for adaptive bitrate streaming
    public func generateMasterPlaylist(
        variants: [PlaylistVariant]
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
        ]

        for variant in variants {
            lines.append("#EXT-X-STREAM-INF:BANDWIDTH=\(variant.bandwidth),RESOLUTION=\(variant.resolution)")
            lines.append(variant.playlistURL.absoluteString)
        }

        return lines.joined(separator: "\n")
    }

    /// Generate media playlist with TDF3 key references
    public func generateMediaPlaylist(
        segments: [SegmentMetadata],
        assetID: String,
        userID: String,
        sessionID: UUID,
        targetDuration: Int = 10,
        mediaSequence: Int = 0
    ) -> String {
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:\(mediaSequence)",
        ]

        for segment in segments {
            // Add key directive for TDF3
            let keyURL = generateKeyURL(
                assetID: assetID,
                userID: userID,
                sessionID: sessionID,
                segmentIndex: segment.index
            )

            // Convert IV to hex string
            let ivHex = segment.iv.map { String(format: "%02x", $0) }.joined()

            lines.append("#EXT-X-KEY:METHOD=AES-128,URI=\"\(keyURL.absoluteString)\",IV=0x\(ivHex)")

            // Add segment
            lines.append("#EXTINF:\(String(format: "%.3f", segment.duration)),")
            lines.append(segment.url.absoluteString)
        }

        lines.append("#EXT-X-ENDLIST")

        return lines.joined(separator: "\n")
    }

    /// Generate variant playlist (specific bitrate/resolution)
    public func generateVariantPlaylist(
        segments: [SegmentMetadata],
        assetID: String,
        userID: String,
        sessionID: UUID,
        variant: PlaylistVariant
    ) -> String {
        generateMediaPlaylist(
            segments: segments,
            assetID: assetID,
            userID: userID,
            sessionID: sessionID,
            targetDuration: Int(ceil(segments.map(\.duration).max() ?? 10.0))
        )
    }

    /// Generate TDF3 key URL for a segment
    private func generateKeyURL(
        assetID: String,
        userID: String,
        sessionID: UUID,
        segmentIndex: Int
    ) -> URL {
        var components = URLComponents(url: kasBaseURL, resolvingAgainstBaseURL: false)!
        components.scheme = "tdf3"
        components.path = "/key"
        components.queryItems = [
            URLQueryItem(name: "asset", value: assetID),
            URLQueryItem(name: "user", value: userID),
            URLQueryItem(name: "session", value: sessionID.uuidString),
            URLQueryItem(name: "segment", value: String(segmentIndex)),
        ]

        return components.url!
    }

    /// Save playlist to file
    public func savePlaylist(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Playlist variant for adaptive bitrate streaming
public struct PlaylistVariant: Sendable {
    public let bandwidth: Int
    public let resolution: String
    public let playlistURL: URL

    public init(bandwidth: Int, resolution: String, playlistURL: URL) {
        self.bandwidth = bandwidth
        self.resolution = resolution
        self.playlistURL = playlistURL
    }
}

extension PlaylistVariant: Codable {}
