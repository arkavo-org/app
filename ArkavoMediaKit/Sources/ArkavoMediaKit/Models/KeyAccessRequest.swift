import Foundation

/// Request for accessing a segment decryption key
public struct KeyAccessRequest: Sendable {
    /// Session identifier
    public let sessionID: UUID

    /// User identifier
    public let userID: String

    /// Asset identifier
    public let assetID: String

    /// Segment index
    public let segmentIndex: Int

    /// NanoTDF header (base64 encoded) from the segment
    public let nanoTDFHeader: String

    /// Request timestamp
    public let timestamp: Date

    /// Client context (optional metadata)
    public let context: [String: String]

    public init(
        sessionID: UUID,
        userID: String,
        assetID: String,
        segmentIndex: Int,
        nanoTDFHeader: String,
        context: [String: String] = [:]
    ) {
        self.sessionID = sessionID
        self.userID = userID
        self.assetID = assetID
        self.segmentIndex = segmentIndex
        self.nanoTDFHeader = nanoTDFHeader
        self.timestamp = Date()
        self.context = context
    }
}

/// Response containing the wrapped decryption key
public struct KeyAccessResponse: Sendable {
    /// Wrapped symmetric key (base64 encoded)
    public let wrappedKey: Data

    /// Key metadata
    public let metadata: KeyMetadata

    public struct KeyMetadata: Sendable, Codable {
        public let segmentIndex: Int
        public let expiresAt: Date?
        public let latencyMS: Int?

        public init(segmentIndex: Int, expiresAt: Date? = nil, latencyMS: Int? = nil) {
            self.segmentIndex = segmentIndex
            self.expiresAt = expiresAt
            self.latencyMS = latencyMS
        }
    }

    public init(wrappedKey: Data, metadata: KeyMetadata) {
        self.wrappedKey = wrappedKey
        self.metadata = metadata
    }
}

extension KeyAccessRequest: Codable {}
extension KeyAccessResponse: Codable {}
