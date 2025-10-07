import AVFoundation
import CryptoKit
import Foundation
import OpenTDFKit

/// Encrypts HLS segments with TDF3
public actor HLSSegmentEncryptor {
    private let keyProvider: TDF3KeyProvider
    private let policy: MediaDRMPolicy

    public init(keyProvider: TDF3KeyProvider, policy: MediaDRMPolicy) {
        self.keyProvider = keyProvider
        self.policy = policy
    }

    /// Encrypt a video segment with TDF3
    public func encryptSegment(
        segmentData: Data,
        assetID: String,
        segmentIndex: Int,
        duration: Double
    ) async throws -> (encryptedData: Data, metadata: SegmentMetadata) {
        // Generate wrapped segment key
        let (nanoTDF, symmetricKey) = try await keyProvider.generateWrappedSegmentKey(
            assetID: assetID,
            segmentIndex: segmentIndex,
            policy: policy
        )

        // Encrypt segment data
        let encryptedSegment = try await TDF3SegmentKey.encryptSegment(
            data: segmentData,
            key: symmetricKey
        )

        // Combine ciphertext and tag for HLS
        var encryptedData = encryptedSegment.ciphertext
        encryptedData.append(encryptedSegment.tag)

        // Encode NanoTDF header as base64
        let headerBase64 = nanoTDF.toData().base64EncodedString()

        // Create segment URL (placeholder - would be actual CDN URL)
        let segmentURL = URL(string: "https://cdn.arkavo.net/\(assetID)/segment_\(segmentIndex).ts")!

        // Create metadata
        let metadata = SegmentMetadata(
            index: segmentIndex,
            duration: duration,
            url: segmentURL,
            nanoTDFHeader: headerBase64,
            iv: encryptedSegment.nonce,
            assetID: assetID
        )

        return (encryptedData, metadata)
    }

    /// Decrypt a segment (for playback)
    public func decryptSegment(
        encryptedData: Data,
        nanoTDFHeader: String
    ) async throws -> Data {
        // Decode NanoTDF header
        guard let headerData = Data(base64Encoded: nanoTDFHeader) else {
            throw EncryptorError.invalidHeader
        }

        // Parse NanoTDF - use full encrypted data since header is embedded
        // Parse header first
        let parser = BinaryParser(data: headerData)
        let header = try parser.parseHeader()

        // Create a minimal NanoTDF with just the header for key unwrapping
        let nanoTDF = NanoTDF(
            header: header,
            payload: Payload(length: 0, iv: Data(), ciphertext: Data(), mac: Data()),
            signature: nil
        )

        // Unwrap segment key
        let symmetricKey = try await keyProvider.unwrapSegmentKey(nanoTDF: nanoTDF)

        // Split encrypted data (last 16 bytes are the tag)
        guard encryptedData.count > 16 else {
            throw EncryptorError.invalidData
        }

        let ciphertext = encryptedData.prefix(encryptedData.count - 16)
        let tag = encryptedData.suffix(16)

        // Extract IV from NanoTDF header
        let iv = nanoTDF.payload.iv

        // Decrypt
        let encryptedSegment = EncryptedSegment(
            ciphertext: Data(ciphertext),
            nonce: iv,
            tag: Data(tag)
        )

        return try await TDF3SegmentKey.decryptSegment(
            encryptedSegment: encryptedSegment,
            key: symmetricKey
        )
    }

    /// Batch encrypt multiple segments
    public func encryptSegments(
        segments: [(data: Data, duration: Double)],
        assetID: String,
        startIndex: Int = 0
    ) async throws -> [(encryptedData: Data, metadata: SegmentMetadata)] {
        var results: [(Data, SegmentMetadata)] = []

        for (index, segment) in segments.enumerated() {
            let segmentIndex = startIndex + index
            let result = try await encryptSegment(
                segmentData: segment.data,
                assetID: assetID,
                segmentIndex: segmentIndex,
                duration: segment.duration
            )
            results.append(result)
        }

        return results
    }
}

/// Encryptor errors
public enum EncryptorError: Error, LocalizedError {
    case invalidHeader
    case invalidData
    case encryptionFailed
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .invalidHeader: "Invalid NanoTDF header"
        case .invalidData: "Invalid encrypted data"
        case .encryptionFailed: "Segment encryption failed"
        case .decryptionFailed: "Segment decryption failed"
        }
    }
}
