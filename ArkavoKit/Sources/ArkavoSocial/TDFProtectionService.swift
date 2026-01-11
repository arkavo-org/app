import CommonCrypto
import CryptoKit
import Foundation
import ZIPFoundation

/// TDF3-based content protection service for FairPlay-compatible video encryption
///
/// Uses Standard TDF format (ZIP archive containing manifest.json + 0.payload) with:
/// - AES-128-CBC for content encryption (FairPlay compatible)
/// - RSA-2048 OAEP (SHA-1) for DEK wrapping (OpenTDF spec)
public actor TDFProtectionService {
    private let kasURL: URL

    /// Initialize with KAS URL for key fetching
    /// - Parameter kasURL: KAS server URL (e.g., https://100.arkavo.net)
    public init(kasURL: URL) {
        self.kasURL = kasURL
    }

    /// Protect content using Standard TDF format for FairPlay delivery
    /// - Parameters:
    ///   - data: Raw data to encrypt
    ///   - assetID: Unique asset identifier for the manifest
    ///   - mimeType: MIME type of the content (default: video/quicktime)
    /// - Returns: TDF ZIP archive data containing manifest.json and 0.payload
    public func protect(
        data: Data,
        assetID: String,
        mimeType: String = "video/quicktime"
    ) async throws -> Data {
        // 1. Generate 16-byte DEK (AES-128 for FairPlay)
        let dek = try generateDEK()

        // 2. Generate random 16-byte IV
        let iv = try generateIV()

        // 3. Encrypt data with AES-128-CBC
        let ciphertext = try encryptCBC(plaintext: data, key: dek, iv: iv)

        // 4. Fetch KAS RSA public key
        let rsaPublicKeyPEM = try await fetchKASRSAPublicKey()

        // 5. Wrap DEK with RSA-2048 OAEP (SHA-1 per OpenTDF spec)
        let wrappedKey = try wrapDEKWithRSA(dek: dek, publicKeyPEM: rsaPublicKeyPEM)

        // 6. Build Standard TDF manifest.json
        let manifest = try buildManifest(wrappedKey: wrappedKey, iv: iv, assetID: assetID, mimeType: mimeType)

        // 7. Create TDF ZIP archive containing manifest.json and 0.payload
        let tdfArchive = try createTDFArchive(manifest: manifest, payload: ciphertext)

        return tdfArchive
    }

    // MARK: - TDF Archive Creation

    private func createTDFArchive(manifest: Data, payload: Data) throws -> Data {
        let archivePath = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).tdf")

        defer {
            try? FileManager.default.removeItem(at: archivePath)
        }

        // Create ZIP archive using ZIPFoundation
        guard let archive = Archive(url: archivePath, accessMode: .create) else {
            throw TDFProtectionError.archiveCreationFailed
        }

        // Add manifest.json
        try archive.addEntry(
            with: "manifest.json",
            type: .file,
            uncompressedSize: Int64(manifest.count),
            provider: { position, size in
                manifest.subdata(in: Int(position)..<Int(position) + size)
            }
        )

        // Add 0.payload
        try archive.addEntry(
            with: "0.payload",
            type: .file,
            uncompressedSize: Int64(payload.count),
            provider: { position, size in
                payload.subdata(in: Int(position)..<Int(position) + size)
            }
        )

        // Read the archive data
        return try Data(contentsOf: archivePath)
    }

    // MARK: - Key Generation

    private func generateDEK() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw TDFProtectionError.keyGenerationFailed
        }
        return Data(bytes)
    }

    private func generateIV() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw TDFProtectionError.ivGenerationFailed
        }
        return Data(bytes)
    }

    // MARK: - AES-128-CBC Encryption

    private func encryptCBC(plaintext: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw TDFProtectionError.invalidKeySize
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw TDFProtectionError.invalidIVSize
        }

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
            throw TDFProtectionError.encryptionFailed(status: status)
        }

        ciphertext.removeSubrange(numBytesEncrypted...)
        return ciphertext
    }

    // MARK: - RSA Key Wrapping

    private func fetchKASRSAPublicKey() async throws -> String {
        var components = URLComponents(url: kasURL, resolvingAgainstBaseURL: true)!
        components.path = "/kas/v2/kas_public_key"
        components.queryItems = [URLQueryItem(name: "algorithm", value: "rsa")]

        guard let url = components.url else {
            throw TDFProtectionError.invalidKASURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw TDFProtectionError.kasKeyFetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicKey = json["public_key"] as? String
        else {
            throw TDFProtectionError.invalidKASResponse
        }

        return publicKey
    }

    private func wrapDEKWithRSA(dek: Data, publicKeyPEM: String) throws -> String {
        let publicKey = try loadRSAPublicKey(fromPEM: publicKeyPEM)

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA1,
            dek as CFData,
            &error
        ) as Data? else {
            throw TDFProtectionError.keyWrapFailed(error?.takeRetainedValue())
        }

        guard encrypted.count == 256 else {
            throw TDFProtectionError.invalidWrappedKeySize
        }

        return encrypted.base64EncodedString()
    }

    private func loadRSAPublicKey(fromPEM pem: String) throws -> SecKey {
        let stripped = pem
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = Data(base64Encoded: stripped) else {
            throw TDFProtectionError.invalidPEM
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else {
            throw TDFProtectionError.invalidKeyData(error?.takeRetainedValue())
        }

        guard let attrs = SecKeyCopyAttributes(key) as? [String: Any],
              let keySize = attrs[kSecAttrKeySizeInBits as String] as? Int,
              keySize >= 2048
        else {
            throw TDFProtectionError.weakRSAKey
        }

        return key
    }

    // MARK: - Manifest Building

    private func buildManifest(wrappedKey: String, iv: Data, assetID: String, mimeType: String) throws -> Data {
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
                "mimeType": mimeType,
            ],
            "meta": [
                "assetId": assetID,
                "protectedAt": ISO8601DateFormatter().string(from: Date()),
            ],
        ]

        return try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
    }
}

/// TDF protection errors
public enum TDFProtectionError: Error, LocalizedError, Sendable {
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
    case archiveCreationFailed
    case invalidTDFArchive

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
        case .archiveCreationFailed:
            "Failed to create TDF ZIP archive"
        case .invalidTDFArchive:
            "Invalid TDF archive format"
        }
    }
}
