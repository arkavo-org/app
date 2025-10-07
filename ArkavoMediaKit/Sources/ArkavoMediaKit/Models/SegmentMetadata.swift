import Foundation

/// Metadata for an HLS segment encrypted with TDF3
public struct SegmentMetadata: Sendable {
    /// Segment index in the playlist
    public let index: Int

    /// Segment duration in seconds
    public let duration: Double

    /// URL to the encrypted segment file
    public let url: URL

    /// NanoTDF header (base64 encoded)
    public let nanoTDFHeader: String

    /// Initialization vector for AES encryption
    public let iv: Data

    /// Segment creation timestamp
    public let createdAt: Date

    /// Asset identifier this segment belongs to
    public let assetID: String

    public init(
        index: Int,
        duration: Double,
        url: URL,
        nanoTDFHeader: String,
        iv: Data,
        assetID: String
    ) {
        self.index = index
        self.duration = duration
        self.url = url
        self.nanoTDFHeader = nanoTDFHeader
        self.iv = iv
        self.createdAt = Date()
        self.assetID = assetID
    }
}

extension SegmentMetadata: Codable {}
extension SegmentMetadata: Identifiable {
    public var id: Int { index }
}
