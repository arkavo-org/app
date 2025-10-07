import CryptoKit
import Foundation
import OpenTDFKit

/// Provides TDF3-wrapped keys for media segments
public actor TDF3KeyProvider {
    private let kasMetadata: KasMetadata
    private let keyStore: KeyStore
    private let sessionManager: TDF3MediaSession

    public init(
        kasMetadata: KasMetadata,
        keyStore: KeyStore,
        sessionManager: TDF3MediaSession
    ) {
        self.kasMetadata = kasMetadata
        self.keyStore = keyStore
        self.sessionManager = sessionManager
    }

    /// Request a key for a specific segment
    public func requestKey(
        request: KeyAccessRequest,
        policy: MediaDRMPolicy,
        deviceInfo: DeviceInfo
    ) async throws -> KeyAccessResponse {
        let startTime = Date()

        // Validate session exists and is active
        let session = try await sessionManager.getSession(sessionID: request.sessionID)

        // Get current active stream count for concurrency check
        let activeStreams = await sessionManager.getActiveStreamCount(userID: request.userID)

        // Validate policy
        try policy.validate(
            session: session,
            firstPlayTimestamp: session.firstPlayTimestamp,
            currentActiveStreams: activeStreams,
            deviceInfo: deviceInfo
        )

        // Decode NanoTDF header from request
        guard let headerData = Data(base64Encoded: request.nanoTDFHeader) else {
            throw KeyProviderError.invalidNanoTDFHeader
        }

        // Parse NanoTDF to extract ephemeral public key and policy
        let nanoTDF = try await parseNanoTDF(from: headerData)

        // Derive the segment symmetric key using our KAS private key
        let segmentKey = try await keyStore.derivePayloadSymmetricKey(header: nanoTDF.header)

        // Wrap the key for transport (base64 encode the raw key data)
        let wrappedKey = segmentKey.withUnsafeBytes { Data($0) }

        // Calculate latency
        let latencyMS = Int(Date().timeIntervalSince(startTime) * 1000)

        // Update session heartbeat
        try await sessionManager.updateHeartbeat(
            sessionID: request.sessionID,
            state: .playing
        )

        return KeyAccessResponse(
            wrappedKey: wrappedKey,
            metadata: .init(
                segmentIndex: request.segmentIndex,
                expiresAt: nil,
                latencyMS: latencyMS
            )
        )
    }

    /// Generate and wrap a new segment key
    public func generateWrappedSegmentKey(
        assetID: String,
        segmentIndex: Int,
        policy: MediaDRMPolicy
    ) async throws -> (nanoTDF: NanoTDF, symmetricKey: SymmetricKey) {
        // Generate unique segment key
        let symmetricKey = TDF3SegmentKey.generateSegmentKey()

        // Wrap with TDF3
        let nanoTDF = try await TDF3SegmentKey.wrapSegmentKey(
            segmentKey: symmetricKey,
            kasMetadata: kasMetadata,
            policy: policy,
            assetID: assetID,
            segmentIndex: segmentIndex
        )

        return (nanoTDF, symmetricKey)
    }

    /// Unwrap a segment key from NanoTDF
    public func unwrapSegmentKey(nanoTDF: NanoTDF) async throws -> SymmetricKey {
        try await TDF3SegmentKey.unwrapSegmentKey(
            nanoTDF: nanoTDF,
            keyStore: keyStore
        )
    }

    /// Parse NanoTDF from binary data
    private func parseNanoTDF(from data: Data) async throws -> NanoTDF {
        let parser = BinaryParser(data: data)
        let header = try parser.parseHeader()

        // Parse payload - assumes remaining data is payload
        // Read 3-byte length
        guard let lengthData = parser.read(length: 3) else {
            throw KeyProviderError.invalidNanoTDFHeader
        }
        let length = UInt32(lengthData[0]) << 16 | UInt32(lengthData[1]) << 8 | UInt32(lengthData[2])

        // IV is 3 bytes for NanoTDF
        guard let iv = parser.read(length: 3) else {
            throw KeyProviderError.invalidNanoTDFHeader
        }

        // Calculate ciphertext and tag lengths
        let tagLength = 16 // AES-GCM-128 tag
        let ciphertextLength = Int(length) - iv.count - tagLength

        guard let ciphertext = parser.read(length: ciphertextLength),
              let mac = parser.read(length: tagLength) else {
            throw KeyProviderError.invalidNanoTDFHeader
        }

        let payload = Payload(length: length, iv: iv, ciphertext: ciphertext, mac: mac)

        return NanoTDF(header: header, payload: payload, signature: nil)
    }
}

/// Key provider errors
public enum KeyProviderError: Error, LocalizedError {
    case invalidNanoTDFHeader
    case keyDerivationFailed
    case policyValidationFailed(String)
    case sessionInvalid

    public var errorDescription: String? {
        switch self {
        case .invalidNanoTDFHeader:
            "Invalid NanoTDF header"
        case .keyDerivationFailed:
            "Failed to derive segment key"
        case let .policyValidationFailed(reason):
            "Policy validation failed: \(reason)"
        case .sessionInvalid:
            "Session is invalid or expired"
        }
    }
}
