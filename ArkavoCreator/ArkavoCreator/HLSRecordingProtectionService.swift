import ArkavoMediaKit
import Foundation

/// HLS-based TDF protection service for streaming playback (macOS)
///
/// Uses HLS segmentation with TDF encryption for:
/// - Streaming-compatible playback with seeking support
/// - Per-segment encryption with shared DEK
/// - FairPlay-compatible AES-128-CBC encryption
public actor HLSRecordingProtectionService {
    private let kasURL: URL

    /// Initialize with KAS URL for key fetching
    /// - Parameter kasURL: KAS server URL (e.g., https://kas.arkavo.net)
    public init(kasURL: URL) {
        self.kasURL = kasURL
    }

    /// Protect video content with HLS segmentation for streaming playback
    ///
    /// - Parameters:
    ///   - videoURL: URL to the source video file
    ///   - assetID: Unique asset identifier for the manifest
    /// - Returns: TDF ZIP archive data containing manifest, playlist, and encrypted segments
    public func protectVideoHLS(
        videoURL: URL,
        assetID: String
    ) async throws -> Data {
        // Create temporary directory for HLS conversion
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Fetch KAS RSA public key
        print("🔑 Fetching KAS RSA public key...")
        let rsaPublicKeyPEM = try await fetchKASRSAPublicKey()

        // 2. Convert video to HLS segments
        print("🎬 Converting video to HLS segments...")
        let converter = HLSConverter()
        let hlsResult = try await converter.convert(
            videoURL: videoURL,
            outputDirectory: tempDir,
            segmentDuration: 6.0
        )
        print("   Created \(hlsResult.segmentURLs.count) segments")

        // 3. Package into HLS TDF archive
        print("📦 Packaging HLS segments into TDF archive...")
        let packager = HLSTDFPackager(
            kasURL: kasURL,
            kasPublicKeyPEM: rsaPublicKeyPEM,
            keySize: .bits128,  // FairPlay compatible
            mode: .cbc          // FairPlay compatible
        )

        let tdfData = try await packager.package(
            hlsResult: hlsResult,
            assetID: assetID
        )
        print("✅ HLS TDF archive created: \(tdfData.count) bytes")

        return tdfData
    }

    // MARK: - Private Helpers

    private func fetchKASRSAPublicKey() async throws -> String {
        var components = URLComponents(url: kasURL, resolvingAgainstBaseURL: true)!
        components.path = "/kas/v2/kas_public_key"
        components.queryItems = [URLQueryItem(name: "algorithm", value: "rsa:2048")]

        guard let url = components.url else {
            throw HLSRecordingProtectionError.invalidKASURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw HLSRecordingProtectionError.kasKeyFetchFailed
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let publicKey = json["public_key"] as? String
        else {
            throw HLSRecordingProtectionError.invalidKASResponse
        }

        return publicKey
    }
}

/// HLS recording protection errors
public enum HLSRecordingProtectionError: Error, LocalizedError {
    case invalidKASURL
    case kasKeyFetchFailed
    case invalidKASResponse
    case conversionFailed(String)
    case packagingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKASURL:
            "Invalid KAS URL"
        case .kasKeyFetchFailed:
            "Failed to fetch RSA public key from KAS"
        case .invalidKASResponse:
            "Invalid response from KAS key endpoint"
        case let .conversionFailed(reason):
            "HLS conversion failed: \(reason)"
        case let .packagingFailed(reason):
            "TDF packaging failed: \(reason)"
        }
    }
}
