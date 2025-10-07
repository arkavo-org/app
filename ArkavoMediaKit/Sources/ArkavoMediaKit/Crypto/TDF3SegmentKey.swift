import CryptoKit
import Foundation
import OpenTDFKit

/// Manages TDF3 encryption keys for HLS segments
public actor TDF3SegmentKey {
    /// Generate a unique symmetric key for a segment
    public static func generateSegmentKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    /// Encrypt segment data with AES-256-GCM
    public static func encryptSegment(
        data: Data,
        key: SymmetricKey,
        iv: Data? = nil
    ) async throws -> EncryptedSegment {
        let nonce: AES.GCM.Nonce
        if let iv, iv.count == 12 {
            nonce = try AES.GCM.Nonce(data: iv)
        } else {
            nonce = AES.GCM.Nonce()
        }

        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext.withUnsafeBytes({ Data($0) }) as Data?,
              let tag = sealedBox.tag.withUnsafeBytes({ Data($0) }) as Data?
        else {
            throw TDF3SegmentKeyError.encryptionFailed
        }

        return EncryptedSegment(
            ciphertext: ciphertext,
            nonce: Data(nonce),
            tag: tag
        )
    }

    /// Decrypt segment data with AES-256-GCM
    public static func decryptSegment(
        encryptedSegment: EncryptedSegment,
        key: SymmetricKey
    ) async throws -> Data {
        let nonce = try AES.GCM.Nonce(data: encryptedSegment.nonce)

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encryptedSegment.ciphertext,
            tag: encryptedSegment.tag
        )

        return try AES.GCM.open(sealedBox, using: key)
    }

    /// Wrap segment key with TDF3/NanoTDF
    public static func wrapSegmentKey(
        segmentKey: SymmetricKey,
        kasMetadata: KasMetadata,
        policy: MediaDRMPolicy,
        assetID: String,
        segmentIndex: Int
    ) async throws -> NanoTDF {
        // Convert policy to TDF3 policy format
        var tdf3Policy = try convertToTDF3Policy(
            mediaPolicy: policy,
            assetID: assetID,
            segmentIndex: segmentIndex
        )

        // Extract segment key data
        let keyData = segmentKey.withUnsafeBytes { Data($0) }

        // Create NanoTDF wrapping the segment key
        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &tdf3Policy,
            plaintext: keyData
        )

        return nanoTDF
    }

    /// Unwrap segment key from NanoTDF
    public static func unwrapSegmentKey(
        nanoTDF: NanoTDF,
        keyStore: KeyStore
    ) async throws -> SymmetricKey {
        // Decrypt NanoTDF to get segment key data
        let keyData = try await nanoTDF.getPlaintext(using: keyStore)

        // Convert back to SymmetricKey
        return SymmetricKey(data: keyData)
    }

    /// Convert MediaDRMPolicy to TDF3 Policy structure
    private static func convertToTDF3Policy(
        mediaPolicy: MediaDRMPolicy,
        assetID: String,
        segmentIndex: Int
    ) throws -> Policy {
        var attributes: [String] = []

        // Add asset and segment attributes
        attributes.append("asset:\(assetID)")
        attributes.append("segment:\(segmentIndex)")

        // Add rental window attributes
        if let rental = mediaPolicy.rentalWindow {
            attributes.append("rental:purchase_window:\(Int(rental.purchaseWindow))")
            attributes.append("rental:playback_window:\(Int(rental.playbackWindow))")
        }

        // Add concurrency limit
        if let maxStreams = mediaPolicy.maxConcurrentStreams {
            attributes.append("concurrency:max:\(maxStreams)")
        }

        // Add geo restrictions
        if let allowed = mediaPolicy.allowedRegions, !allowed.isEmpty {
            attributes.append("geo:allowed:\(allowed.joined(separator: ","))")
        }
        if let blocked = mediaPolicy.blockedRegions, !blocked.isEmpty {
            attributes.append("geo:blocked:\(blocked.joined(separator: ","))")
        }

        // Add HDCP level
        if let hdcp = mediaPolicy.hdcpLevel {
            attributes.append("hdcp:\(hdcp.rawValue)")
        }

        // Create TDF3 Policy with remote ResourceLocator
        // The remote policy is stored as a ResourceLocator pointing to the policy service
        let policyLocator = ResourceLocator(
            protocol: "https",
            body: "policy.arkavo.net/\(assetID)?attrs=\(attributes.joined(separator: ";"))"
        )

        // Note: Policy binding will be calculated by createNanoTDF
        return Policy(
            type: .remote,
            body: nil,
            remote: policyLocator,
            binding: nil
        )
    }
}

/// Encrypted segment data
public struct EncryptedSegment: Sendable {
    public let ciphertext: Data
    public let nonce: Data
    public let tag: Data

    public init(ciphertext: Data, nonce: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.tag = tag
    }
}

/// TDF3 segment key errors
public enum TDF3SegmentKeyError: Error, LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case invalidKey
    case policyConversionFailed

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed: "Segment encryption failed"
        case .decryptionFailed: "Segment decryption failed"
        case .invalidKey: "Invalid encryption key"
        case .policyConversionFailed: "Failed to convert policy"
        }
    }
}

extension EncryptedSegment: Codable {}
