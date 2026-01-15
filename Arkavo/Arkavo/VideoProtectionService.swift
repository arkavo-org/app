import ArkavoMediaKit
import Foundation

/// TDF3-based content protection service for FairPlay-compatible video encryption
///
/// Uses Standard TDF format (manifest.json + encrypted payload) with:
/// - AES-128-CBC for content encryption (FairPlay compatible)
/// - RSA-2048 OAEP (SHA-1) for DEK wrapping (OpenTDF spec)
///
/// The backend at /media/v1/key-request accepts the tdfManifest,
/// extracts the wrapped DEK, unwraps it, and re-wraps for FairPlay CKC delivery.
public actor VideoProtectionService {
    private let kasURL: URL

    /// Protected video result containing TDF3 manifest and encrypted payload
    public struct ProtectedVideo: Sendable {
        /// TDF3 manifest.json containing wrapped DEK and encryption parameters
        public let manifest: Data
        /// AES-128-CBC encrypted video content
        public let encryptedPayload: Data
        /// 16-byte initialization vector used for encryption
        public let iv: Data
    }

    /// Initialize with KAS URL for key fetching
    /// - Parameter kasURL: KAS server URL (e.g., https://kas.arkavo.net)
    public init(kasURL: URL) {
        self.kasURL = kasURL
    }

    /// Protect video content using TDF3 format for FairPlay delivery
    ///
    /// Flow:
    /// 1. Generate 16-byte DEK (AES-128)
    /// 2. Generate random 16-byte IV
    /// 3. Encrypt video with AES-128-CBC
    /// 4. Fetch KAS RSA public key
    /// 5. Wrap DEK with RSA-2048 OAEP (SHA-1)
    /// 6. Build Standard TDF manifest.json
    ///
    /// - Parameters:
    ///   - videoData: Raw video data to encrypt
    ///   - assetID: Asset identifier for tracking
    /// - Returns: Protected video with manifest and encrypted payload
    public func protectVideo(
        videoData: Data,
        assetID: String
    ) async throws -> ProtectedVideo {
        // 1. Generate 16-byte DEK (AES-128 for FairPlay)
        let dek = try TDFProtectionCore.generateDEK()

        // 2. Generate random 16-byte IV
        let iv = try TDFProtectionCore.generateIV()

        // 3. Encrypt video with AES-128-CBC
        let ciphertext = try TDFProtectionCore.encryptCBC(plaintext: videoData, key: dek, iv: iv)

        // 4. Fetch KAS RSA public key
        let rsaPublicKeyPEM = try await TDFProtectionCore.fetchKASRSAPublicKey(kasURL: kasURL)

        // 5. Wrap DEK with RSA-2048 OAEP (SHA-1 per OpenTDF spec)
        let wrappedKey = try TDFProtectionCore.wrapDEKWithRSA(dek: dek, publicKeyPEM: rsaPublicKeyPEM)

        // 6. Build Standard TDF manifest.json
        let manifest = try TDFProtectionCore.buildManifest(
            kasURL: kasURL,
            wrappedKey: wrappedKey,
            iv: iv,
            includeMetadata: false
        )

        return ProtectedVideo(manifest: manifest, encryptedPayload: ciphertext, iv: iv)
    }
}
