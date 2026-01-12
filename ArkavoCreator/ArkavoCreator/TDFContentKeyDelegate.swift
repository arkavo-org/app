import AVFoundation
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

// MARK: - HLS Manifest for FairPlay

/// Lightweight HLS manifest structure for FairPlay key exchange
struct HLSManifestLite: Sendable {
    let kasURL: String
    let wrappedKey: String
    let algorithm: String
    let iv: String
    let assetID: String
}

// MARK: - State Actor for Thread Safety

/// Actor to manage FairPlay session state
private actor FairPlayState {
    var sessionId: String?
    var fairPlayCertificate: Data?

    func setSessionId(_ id: String) {
        sessionId = id
    }

    func setCertificate(_ cert: Data) {
        fairPlayCertificate = cert
    }
}

// MARK: - TDFContentKeyDelegate

/// AVContentKeySessionDelegate for FairPlay DRM with TDF content (macOS)
///
/// Handles the FairPlay key exchange process:
/// 1. Receives key request from AVPlayer
/// 2. Generates SPC (Server Playback Context)
/// 3. Posts SPC + TDF manifest to server
/// 4. Receives CKC (Content Key Context) from server
/// 5. Provides CKC to AVPlayer for hardware decryption
final class TDFContentKeyDelegate: NSObject, AVContentKeySessionDelegate, @unchecked Sendable {
    private let manifest: HLSManifestLite
    private let serverURL: URL
    private let userId: String
    private let authToken: String
    private let state = FairPlayState()

    /// Initialize with HLS manifest and authentication
    /// - Parameters:
    ///   - manifest: The HLS manifest containing encryption info
    ///   - authToken: Authentication token for KAS
    ///   - userId: User identifier for session (defaults to "anonymous")
    ///   - serverURL: FairPlay server URL (defaults to 100.arkavo.net)
    init(
        manifest: HLSManifestLite,
        authToken: String,
        userId: String = "anonymous",
        serverURL: URL = URL(string: "https://100.arkavo.net")!
    ) {
        self.manifest = manifest
        self.authToken = authToken
        self.userId = userId
        self.serverURL = serverURL
        super.init()
    }

    // MARK: - AVContentKeySessionDelegate

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        handleKeyRequest(keyRequest)
    }

    func contentKeySession(
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

    func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError error: Error
    ) {
        print("❌ FairPlay key request failed: \(error.localizedDescription)")
    }

    // MARK: - Key Request Handling

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) {
        Task {
            do {
                // 1. Start session if needed
                var currentSessionId = await state.sessionId
                if currentSessionId == nil {
                    let newSessionId = try await startSession()
                    await state.setSessionId(newSessionId)
                    currentSessionId = newSessionId
                }

                // 2. Get FairPlay certificate (cached after first fetch)
                var certificate = await state.fairPlayCertificate
                if certificate == nil {
                    certificate = try await fetchCertificate()
                    if let cert = certificate {
                        await state.setCertificate(cert)
                    }
                }

                guard let cert = certificate else {
                    throw FairPlayError.certificateFetchFailed("Certificate is nil")
                }

                // 3. Generate SPC with content identifier
                let contentId = manifest.assetID.data(using: .utf8) ?? Data()
                let spcData = try await keyRequest.makeStreamingContentKeyRequestData(
                    forApp: cert,
                    contentIdentifier: contentId
                )
                print("🔐 Generated SPC: \(spcData.count) bytes")

                // 4. Request CKC from server
                guard let activeSessionId = currentSessionId else {
                    throw FairPlayError.sessionStartFailed("Session ID not available")
                }

                let ckcData = try await requestCKC(
                    spcData: spcData,
                    sessionId: activeSessionId
                )
                print("🔐 Received CKC: \(ckcData.count) bytes")

                // 5. Provide CKC to AVPlayer
                let keyResponse = AVContentKeyResponse(
                    fairPlayStreamingKeyResponseData: ckcData
                )
                keyRequest.processContentKeyResponse(keyResponse)
                print("✅ FairPlay key delivered to AVPlayer")

            } catch {
                print("❌ FairPlay error: \(error)")
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
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "userId": userId,
            "assetId": manifest.assetID,
            "protocol": "fairplay"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🔐 Starting FairPlay session...")
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

        print("✅ FairPlay session started: \(sessionId)")
        return sessionId
    }

    /// Fetch FairPlay certificate from server
    private func fetchCertificate() async throws -> Data {
        let url = serverURL.appendingPathComponent("media/v1/certificate")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        print("🔐 Fetching FairPlay certificate...")
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

        print("✅ FairPlay certificate fetched: \(data.count) bytes")
        return data
    }

    /// Request CKC from server with SPC and TDF manifest
    private func requestCKC(spcData: Data, sessionId: String) async throws -> Data {
        let url = serverURL.appendingPathComponent("media/v1/key-request")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        // Encode manifest as base64 JSON
        let manifestJSON: [String: Any] = [
            "encryptionInformation": [
                "keyAccess": [[
                    "type": "wrapped",
                    "url": manifest.kasURL,
                    "wrappedKey": manifest.wrappedKey
                ]],
                "method": [
                    "algorithm": manifest.algorithm,
                    "iv": manifest.iv
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
            "assetId": manifest.assetID,
            "spcData": spcData.base64EncodedString(),
            "tdfManifest": manifestBase64
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        print("🔐 Requesting CKC from server...")
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
