import CommonCrypto
import CryptoKit
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
        let dek = try generateDEK()

        // 2. Generate random 16-byte IV
        let iv = try generateIV()

        // 3. Encrypt video with AES-128-CBC
        let ciphertext = try encryptCBC(plaintext: videoData, key: dek, iv: iv)

        // 4. Fetch KAS RSA public key
        let rsaPublicKeyPEM = try await fetchKASRSAPublicKey()

        // 5. Wrap DEK with RSA-2048 OAEP (SHA-1 per OpenTDF spec)
        let wrappedKey = try wrapDEKWithRSA(dek: dek, publicKeyPEM: rsaPublicKeyPEM)

        // 6. Build Standard TDF manifest.json
        let manifest = try buildManifest(wrappedKey: wrappedKey, iv: iv, assetID: assetID)

        return ProtectedVideo(manifest: manifest, encryptedPayload: ciphertext, iv: iv)
    }

    // MARK: - Key Generation

    /// Generate 16-byte DEK for AES-128
    private func generateDEK() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw VideoProtectionError.keyGenerationFailed
        }
        return Data(bytes)
    }

    /// Generate 16-byte IV
    private func generateIV() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw VideoProtectionError.ivGenerationFailed
        }
        return Data(bytes)
    }

    // MARK: - AES-128-CBC Encryption

    /// Encrypt data with AES-128-CBC using PKCS7 padding
    private func encryptCBC(plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw VideoProtectionError.invalidKeySize
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw VideoProtectionError.invalidIVSize
        }

        // Calculate buffer size with padding
        let bufferSize = plaintext.count + kCCBlockSizeAES128
        var ciphertext = Data(count: bufferSize)
        var numBytesEncrypted = 0

        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                plaintext.withUnsafeBytes { plaintextBytes in
                    ciphertext.withUnsafeMutableBytes { ciphertextBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            plaintextBytes.baseAddress,
                            plaintext.count,
                            ciphertextBytes.baseAddress,
                            bufferSize,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw VideoProtectionError.encryptionFailed(status: status)
        }

        ciphertext.removeSubrange(numBytesEncrypted...)
        return ciphertext
    }

    // MARK: - RSA Key Wrapping

    /// Fetch RSA public key from KAS
    private func fetchKASRSAPublicKey() async throws -> String {
        var components = URLComponents(url: kasURL, resolvingAgainstBaseURL: true)!
        components.path = "/kas/v2/kas_public_key"
        components.queryItems = [URLQueryItem(name: "algorithm", value: "rsa")]

        guard let url = components.url else {
            throw VideoProtectionError.invalidKASURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw VideoProtectionError.kasKeyFetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicKey = json["publicKey"] as? String
        else {
            throw VideoProtectionError.invalidKASResponse
        }

        return publicKey
    }

    /// Wrap DEK with RSA-2048 OAEP using SHA-1 (per OpenTDF spec)
    private func wrapDEKWithRSA(dek: Data, publicKeyPEM: String) throws -> String {
        let publicKey = try loadRSAPublicKey(fromPEM: publicKeyPEM)

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA1, // SHA-1 per OpenTDF spec
            dek as CFData,
            &error
        ) as Data? else {
            throw VideoProtectionError.keyWrapFailed(error?.takeRetainedValue())
        }

        // Verify wrapped key size (256 bytes for RSA-2048)
        guard encrypted.count == 256 else {
            throw VideoProtectionError.invalidWrappedKeySize
        }

        return encrypted.base64EncodedString()
    }

    /// Load RSA public key from PEM format
    private func loadRSAPublicKey(fromPEM pem: String) throws -> SecKey {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: stripped) else {
            throw VideoProtectionError.invalidPEM
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw VideoProtectionError.invalidKeyData(error?.takeRetainedValue())
        }

        // Validate minimum RSA key size (2048 bits)
        guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let keySize = attrs[kSecAttrKeySizeInBits as String] as? Int,
              keySize >= 2048
        else {
            throw VideoProtectionError.weakRSAKey
        }

        return key
    }

    // MARK: - Manifest Building

    /// Build Standard TDF manifest.json per arkavo-rs/docs/standard_tdf_fairplay_integration.md
    private func buildManifest(wrappedKey: String, iv: Data, assetID: String) throws -> Data {
        let manifest: [String: Any] = [
            "encryptionInformation": [
                "type": "split",
                "keyAccess": [[
                    "type": "wrapped",
                    "url": kasURL.absoluteString,
                    "protocol": "kas",
                    "wrappedKey": wrappedKey,
                ]],
                "method": [
                    "algorithm": "AES-128-CBC",
                    "iv": iv.base64EncodedString(),
                ],
            ],
            "payload": [
                "type": "reference",
                "url": "0.payload",
                "mimeType": "video/mp4",
            ],
        ]

        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
    }
}

/// Video protection errors
public enum VideoProtectionError: Error, LocalizedError {
    case keyGenerationFailed
    case ivGenerationFailed
    case invalidKeySize
    case invalidIVSize
    case encryptionFailed(status: CCCryptorStatus)
    case invalidKASURL
    case kasKeyFetchFailed
    case invalidKASResponse
    case invalidPEM
    case invalidKeyData(CFError?)
    case keyWrapFailed(CFError?)
    case invalidWrappedKeySize
    case weakRSAKey

    public var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            "Failed to generate content encryption key"
        case .ivGenerationFailed:
            "Failed to generate initialization vector"
        case .invalidKeySize:
            "Invalid AES-128 key size (expected 16 bytes)"
        case .invalidIVSize:
            "Invalid IV size (expected 16 bytes)"
        case let .encryptionFailed(status):
            "AES-CBC encryption failed with status \(status)"
        case .invalidKASURL:
            "Invalid KAS URL"
        case .kasKeyFetchFailed:
            "Failed to fetch RSA public key from KAS"
        case .invalidKASResponse:
            "Invalid response from KAS key endpoint"
        case .invalidPEM:
            "Invalid PEM format for RSA public key"
        case let .invalidKeyData(error):
            "Invalid RSA key data: \(error?.localizedDescription ?? "unknown")"
        case let .keyWrapFailed(error):
            "RSA key wrapping failed: \(error?.localizedDescription ?? "unknown")"
        case .invalidWrappedKeySize:
            "Invalid wrapped key size (expected 256 bytes for RSA-2048)"
        case .weakRSAKey:
            "RSA key too weak (minimum 2048 bits required)"
        }
    }
}
