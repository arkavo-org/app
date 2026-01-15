import ArkavoMediaKit
import Foundation
import ZIPFoundation

/// TDF3-based content protection service for FairPlay-compatible video encryption (macOS)
///
/// Uses Standard TDF format (ZIP archive containing manifest.json + 0.payload) with:
/// - AES-128-CBC for content encryption (FairPlay compatible)
/// - RSA-2048 OAEP (SHA-1) for DEK wrapping (OpenTDF spec)
public actor RecordingProtectionService {
    private let kasURL: URL

    /// Initialize with KAS URL for key fetching
    /// - Parameter kasURL: KAS server URL (e.g., https://kas.arkavo.net)
    public init(kasURL: URL) {
        self.kasURL = kasURL
    }

    /// Protect video content using Standard TDF format for FairPlay delivery
    /// - Parameters:
    ///   - videoData: Raw video data to encrypt
    ///   - assetID: Unique asset identifier for the manifest
    /// - Returns: TDF ZIP archive data containing manifest.json and 0.payload
    public func protectVideo(
        videoData: Data,
        assetID: String
    ) async throws -> Data {
        // 1. Generate 16-byte DEK (AES-128 for FairPlay)
        let dek = try TDFProtectionCore.generateDEK()

        // 2. Generate random 16-byte IV
        let iv = try TDFProtectionCore.generateIV()

        // 3. Encrypt video with AES-128-CBC
        let ciphertext = try TDFProtectionCore.encryptCBC(plaintext: videoData, key: dek, iv: iv)

        // 4. Fetch KAS RSA public key
        let rsaPublicKeyPEM = try await TDFProtectionCore.fetchKASRSAPublicKey(kasURL: kasURL, algorithm: "rsa:2048")

        // 5. Wrap DEK with RSA-2048 OAEP (SHA-1 per OpenTDF spec)
        let wrappedKey = try TDFProtectionCore.wrapDEKWithRSA(dek: dek, publicKeyPEM: rsaPublicKeyPEM)

        // 6. Build Standard TDF manifest.json
        let manifest = try TDFProtectionCore.buildManifestWithKASPath(
            kasURL: kasURL,
            appendKASPath: true,
            wrappedKey: wrappedKey,
            iv: iv,
            assetID: assetID
        )

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
            throw RecordingProtectionError.archiveCreationFailed
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
}

/// Recording protection errors
public enum RecordingProtectionError: Error, LocalizedError {
    case archiveCreationFailed
    case invalidTDFArchive

    public var errorDescription: String? {
        switch self {
        case .archiveCreationFailed:
            "Failed to create TDF ZIP archive"
        case .invalidTDFArchive:
            "Invalid TDF archive format"
        }
    }
}

// MARK: - TDF Archive Reader

/// Utility to read manifest from a TDF ZIP archive
public enum TDFArchiveReader {
    /// Extract manifest.json from a TDF file
    /// - Parameter tdfURL: URL to the .tdf file
    /// - Returns: Parsed manifest as dictionary
    public static func extractManifest(from tdfURL: URL) throws -> [String: Any] {
        guard let archive = Archive(url: tdfURL, accessMode: .read) else {
            throw RecordingProtectionError.invalidTDFArchive
        }

        // Find manifest.json entry
        guard let manifestEntry = archive["manifest.json"] else {
            throw RecordingProtectionError.invalidTDFArchive
        }

        // Extract manifest data
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { data in
            manifestData.append(data)
        }

        guard let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw RecordingProtectionError.invalidTDFArchive
        }

        return manifest
    }

    /// Extract all files from a TDF archive to a directory
    /// - Parameters:
    ///   - tdfURL: URL to the .tdf file
    ///   - outputDirectory: Directory to extract files to
    /// - Returns: Array of extracted file URLs
    public static func extractAllFiles(from tdfURL: URL, to outputDirectory: URL) throws -> [URL] {
        guard let archive = Archive(url: tdfURL, accessMode: .read) else {
            throw RecordingProtectionError.invalidTDFArchive
        }

        var extractedFiles: [URL] = []

        for entry in archive {
            // Skip directories
            guard entry.type == .file else { continue }

            let destinationURL = outputDirectory.appendingPathComponent(entry.path)

            // Create parent directories if needed
            let parentDir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

            // Extract file
            var fileData = Data()
            _ = try archive.extract(entry) { data in
                fileData.append(data)
            }
            try fileData.write(to: destinationURL)

            extractedFiles.append(destinationURL)
        }

        return extractedFiles
    }
}
