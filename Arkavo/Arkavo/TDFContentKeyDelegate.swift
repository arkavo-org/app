import AVFoundation
import ArkavoSocial
import Foundation

// MARK: - FairPlay Errors

/// Errors that can occur during FairPlay key exchange
enum FairPlayError: Error, LocalizedError {
    case sessionStartFailed(String)
    case certificateFetchFailed(String)
    case spcGenerationFailed(String)
    case ckcRequestFailed(String)
    case invalidCKCResponse(String)
    case manifestEncodingFailed(String)

    var errorDescription: String? {
        switch self {
        case let .sessionStartFailed(reason):
            "Failed to start FairPlay session: \(reason)"
        case let .certificateFetchFailed(reason):
            "Failed to fetch FairPlay certificate: \(reason)"
        case let .spcGenerationFailed(reason):
            "Failed to generate SPC: \(reason)"
        case let .ckcRequestFailed(reason):
            "Failed to request CKC: \(reason)"
        case let .invalidCKCResponse(reason):
            "Invalid CKC response: \(reason)"
        case let .manifestEncodingFailed(reason):
            "Failed to encode TDF manifest: \(reason)"
        }
    }
}

// MARK: - TDFContentKeyDelegate

/// AVContentKeySessionDelegate for FairPlay DRM with TDF content
///
/// Handles the FairPlay key exchange process:
/// 1. Receives key request from AVPlayer
/// 2. Generates SPC (Server Playback Context)
/// 3. Posts SPC + TDF manifest to server
/// 4. Receives CKC (Content Key Context) from server
/// 5. Provides CKC to AVPlayer for hardware decryption
///
/// The TDF manifest contains the RSA-wrapped DEK. The server:
/// - Unwraps DEK using its RSA private key
/// - Re-wraps DEK using FairPlay SDK
/// - Returns CKC for Secure Enclave decryption
final class TDFContentKeyDelegate: NSObject, AVContentKeySessionDelegate, Sendable {
    private let tdfManifest: TDFManifestLite
    private let serverURL: URL
    private let userId: String
    private let sessionId: LockIsolated<String?>
    private let fairPlayCertificate: LockIsolated<Data?>

    /// Initialize with TDF manifest and optional user ID
    /// - Parameters:
    ///   - manifest: The TDF manifest containing encryption info
    ///   - userId: User identifier for session (defaults to "anonymous")
    ///   - serverURL: FairPlay server URL (defaults to 100.arkavo.net)
    init(
        manifest: TDFManifestLite,
        userId: String = "anonymous",
        serverURL: URL = URL(string: "https://100.arkavo.net")!
    ) {
        self.tdfManifest = manifest
        self.userId = userId
        self.serverURL = serverURL
        self.sessionId = LockIsolated(nil)
        self.fairPlayCertificate = LockIsolated(nil)
        super.init()
    }

    // MARK: - AVContentKeySessionDelegate

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        shouldRetry keyRequest: AVContentKeyRequest,
        reason retryReason: AVContentKeyRequest.RetryReason
    ) -> Bool {
        switch retryReason {
        case .timedOut, .receivedResponseWithExpiredLease:
            return true
        default:
            return false
        }
    }

    nonisolated func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError error: Error
    ) {
        print("FairPlay key request failed: \(error.localizedDescription)")
    }

    // MARK: - Key Request Handling

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) {
        Task {
            do {
                // 1. Start session if needed
                if sessionId.value == nil {
                    let newSessionId = try await startSession()
                    sessionId.withLock { $0 = newSessionId }
                }

                // 2. Get FairPlay certificate (cached after first fetch)
                let certificate: Data
                if let cached = fairPlayCertificate.value {
                    certificate = cached
                } else {
                    certificate = try await fetchCertificate()
                    fairPlayCertificate.withLock { $0 = certificate }
                }

                // 3. Generate SPC with content identifier
                let contentId = tdfManifest.assetID.data(using: .utf8) ?? Data()
                let spcData = try await keyRequest.makeStreamingContentKeyRequestData(
                    forApp: certificate,
                    contentIdentifier: contentId
                )

                // 4. Request CKC from server
                guard let currentSessionId = sessionId.value else {
                    throw FairPlayError.sessionStartFailed("Session ID not available")
                }
                let ckcData = try await requestCKC(
                    spcData: spcData,
                    sessionId: currentSessionId
                )

                // 5. Provide CKC to AVPlayer
                let keyResponse = AVContentKeyResponse(
                    fairPlayStreamingKeyResponseData: ckcData
                )
                keyRequest.processContentKeyResponse(keyResponse)

            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    // MARK: - Server Communication

    /// Start a FairPlay playback session
    private func startSession() async throws -> String {
        let url = serverURL.appendingPathComponent("media/v1/session/start")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "userId": userId,
            "assetId": tdfManifest.assetID,
            "protocol": "fairplay"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FairPlayError.sessionStartFailed("HTTP \(statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = json["sessionId"] as? String
        else {
            throw FairPlayError.sessionStartFailed("Invalid session response")
        }

        return sessionId
    }

    /// Fetch FairPlay certificate from server
    private func fetchCertificate() async throws -> Data {
        let url = serverURL.appendingPathComponent("media/v1/certificate")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw FairPlayError.certificateFetchFailed("HTTP \(statusCode)")
        }

        guard !data.isEmpty else {
            throw FairPlayError.certificateFetchFailed("Empty certificate data")
        }

        return data
    }

    /// Request CKC from server with SPC and TDF manifest
    private func requestCKC(spcData: Data, sessionId: String) async throws -> Data {
        let url = serverURL.appendingPathComponent("media/v1/key-request")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode manifest as base64 JSON
        let manifestJSON: [String: Any] = [
            "encryptionInformation": [
                "keyAccess": [[
                    "type": "wrapped",
                    "url": tdfManifest.kasURL,
                    "wrappedKey": tdfManifest.wrappedKey
                ]],
                "method": [
                    "algorithm": tdfManifest.algorithm,
                    "iv": tdfManifest.iv
                ]
            ]
        ]

        guard let manifestData = try? JSONSerialization.data(withJSONObject: manifestJSON) else {
            throw FairPlayError.manifestEncodingFailed("Failed to serialize manifest")
        }
        let manifestBase64 = manifestData.base64EncodedString()

        let body: [String: Any] = [
            "sessionId": sessionId,
            "userId": userId,
            "assetId": tdfManifest.assetID,
            "spcData": spcData.base64EncodedString(),
            "tdfManifest": manifestBase64
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw FairPlayError.ckcRequestFailed("HTTP \(statusCode): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ckcBase64 = json["wrappedKey"] as? String,
              let ckcData = Data(base64Encoded: ckcBase64)
        else {
            throw FairPlayError.invalidCKCResponse("Missing or invalid wrappedKey in response")
        }

        return ckcData
    }
}

// MARK: - LockIsolated Helper

/// Thread-safe wrapper for mutable state
final class LockIsolated<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withLock<T>(_ operation: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation(&_value)
    }
}
