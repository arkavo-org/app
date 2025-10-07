import AVFoundation
import Foundation
import OpenTDFKit

#if canImport(UIKit) || canImport(AppKit)

/// AVContentKeySessionDelegate implementation for TDF3-protected media
@available(iOS 18.0, macOS 15.0, tvOS 18.0, *)
public class TDF3ContentKeyDelegate: NSObject, AVContentKeySessionDelegate, @unchecked Sendable {
    private let keyProvider: TDF3KeyProvider
    private let policy: MediaDRMPolicy
    private let deviceInfo: DeviceInfo
    private let sessionID: UUID

    public init(
        keyProvider: TDF3KeyProvider,
        policy: MediaDRMPolicy,
        deviceInfo: DeviceInfo,
        sessionID: UUID
    ) {
        self.keyProvider = keyProvider
        self.policy = policy
        self.deviceInfo = deviceInfo
        self.sessionID = sessionID
        super.init()
    }

    // MARK: - AVContentKeySessionDelegate

    public func contentKeySession(
        _ session: AVContentKeySession,
        didProvide keyRequest: AVContentKeyRequest
    ) {
        Task {
            do {
                try await handleKeyRequest(keyRequest)
            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    public func contentKeySession(
        _ session: AVContentKeySession,
        didProvideRenewingContentKeyRequest keyRequest: AVContentKeyRequest
    ) {
        Task {
            do {
                try await handleKeyRequest(keyRequest)
            } catch {
                keyRequest.processContentKeyResponseError(error)
            }
        }
    }

    public func contentKeySession(
        _ session: AVContentKeySession,
        contentKeyRequest keyRequest: AVContentKeyRequest,
        didFailWithError err: Error
    ) {
        print("Content key request failed: \(err.localizedDescription)")
    }

    // MARK: - Key Request Handling

    private func handleKeyRequest(_ keyRequest: AVContentKeyRequest) async throws {
        // Extract segment information from the key request identifier
        guard let identifier = keyRequest.identifier as? String,
              let url = URL(string: identifier)
        else {
            throw ContentKeyError.invalidIdentifier
        }

        // Parse segment index from URL
        // Expected format: tdf3://kas.arkavo.net/key?segment=N&asset=ID
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let segmentParam = components.queryItems?.first(where: { $0.name == "segment" }),
              let segmentIndexString = segmentParam.value,
              let segmentIndex = Int(segmentIndexString),
              let assetParam = components.queryItems?.first(where: { $0.name == "asset" }),
              let assetID = assetParam.value,
              let userParam = components.queryItems?.first(where: { $0.name == "user" }),
              let userID = userParam.value
        else {
            throw ContentKeyError.invalidURL
        }

        // Get NanoTDF header from somewhere (could be embedded in URL or loaded from manifest)
        // For now, we'll need to fetch it based on the segment
        guard let nanoTDFHeader = try await fetchNanoTDFHeader(
            assetID: assetID,
            segmentIndex: segmentIndex
        ) else {
            throw ContentKeyError.headerNotFound
        }

        // Create key access request
        let accessRequest = KeyAccessRequest(
            sessionID: sessionID,
            userID: userID,
            assetID: assetID,
            segmentIndex: segmentIndex,
            nanoTDFHeader: nanoTDFHeader
        )

        // Request key from provider
        let response = try await keyProvider.requestKey(
            request: accessRequest,
            policy: policy,
            deviceInfo: deviceInfo
        )

        // Create AVContentKeyResponse with the unwrapped key
        let keyResponse = AVContentKeyResponse(
            fairPlayStreamingKeyResponseData: response.wrappedKey
        )

        keyRequest.processContentKeyResponse(keyResponse)
    }

    /// Fetch NanoTDF header for a specific segment
    ///
    /// ⚠️ **IMPLEMENTATION REQUIRED**
    ///
    /// This method must be implemented to retrieve the NanoTDF header for a given segment.
    /// The header contains the encrypted DEK and policy information required for playback.
    ///
    /// ## Implementation Options:
    ///
    /// ### Option 1: Parse from HLS Manifest
    /// Extract the NanoTDF header embedded in the `#EXT-X-KEY` directive:
    /// ```
    /// #EXT-X-KEY:METHOD=AES-128,URI="tdf3://...",NANOTDF="base64header"
    /// ```
    ///
    /// ### Option 2: Fetch from Metadata Endpoint
    /// Query a separate metadata service:
    /// ```swift
    /// let url = URL(string: "https://metadata.arkavo.net/\(assetID)/segment/\(segmentIndex)/header")!
    /// let (data, _) = try await URLSession.shared.data(from: url)
    /// return String(data: data, encoding: .utf8)
    /// ```
    ///
    /// ### Option 3: Load from Local Cache
    /// For offline playback, retrieve from local storage:
    /// ```swift
    /// let cacheKey = "\(assetID)-\(segmentIndex)"
    /// return headerCache[cacheKey]
    /// ```
    ///
    /// - Parameters:
    ///   - assetID: Asset identifier
    ///   - segmentIndex: Segment index
    /// - Returns: Base64-encoded NanoTDF header
    /// - Throws: `ContentKeyError.headerNotFound` if header cannot be retrieved
    private func fetchNanoTDFHeader(assetID: String, segmentIndex: Int) async throws -> String? {
        // TODO: CRITICAL - Implement header fetching before production use
        // Currently throws to prevent silent failures
        throw ContentKeyError.notImplemented(
            "fetchNanoTDFHeader() requires implementation. " +
            "See method documentation for integration options."
        )
    }
}

/// Content key errors
public enum ContentKeyError: Error, LocalizedError, Sendable {
    case invalidIdentifier
    case invalidURL
    case headerNotFound
    case keyProcessingFailed
    case notImplemented(String)

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifier:
            "Invalid content key identifier"
        case .invalidURL:
            "Invalid key request URL"
        case .headerNotFound:
            "NanoTDF header not found for segment"
        case .keyProcessingFailed:
            "Failed to process content key"
        case let .notImplemented(message):
            "Not implemented: \(message)"
        }
    }
}

#endif
