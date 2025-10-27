import Foundation

/// Configuration for DRM media server and FairPlay Streaming
public struct DRMConfiguration: Sendable {
    /// Media server base URL
    public let serverURL: URL

    /// FairPlay Streaming application certificate data
    public let fpsCertificate: Data

    /// Session heartbeat interval (seconds)
    public let heartbeatInterval: TimeInterval

    /// Session timeout (seconds)
    public let sessionTimeout: TimeInterval

    /// Default configuration using test certificate and production server
    /// Returns nil if certificate cannot be loaded
    public static var `default`: DRMConfiguration? {
        guard let serverURL = URL(string: "https://100.arkavo.net") else {
            return nil
        }

        return try? DRMConfiguration(
            serverURL: serverURL,
            heartbeatInterval: 30,
            sessionTimeout: 300
        )
    }

    /// Initialize with custom parameters
    /// - Parameters:
    ///   - serverURL: Media server base URL
    ///   - fpsCertificateData: Optional FPS certificate data (uses bundled test cert if nil)
    ///   - heartbeatInterval: How often to send heartbeat (default: 30s)
    ///   - sessionTimeout: Session expiration time (default: 300s)
    public init(
        serverURL: URL,
        fpsCertificateData: Data? = nil,
        heartbeatInterval: TimeInterval = 30,
        sessionTimeout: TimeInterval = 300
    ) throws {
        self.serverURL = serverURL
        self.heartbeatInterval = heartbeatInterval
        self.sessionTimeout = sessionTimeout

        // Load certificate
        if let providedCert = fpsCertificateData {
            self.fpsCertificate = providedCert
        } else {
            // Load bundled test certificate
            self.fpsCertificate = try Self.loadBundledCertificate()
        }
    }

    /// Load the bundled FPS test certificate
    private static func loadBundledCertificate() throws -> Data {
        // Try to find the certificate in the module bundle
        guard let bundleURL = Bundle.module.url(
            forResource: "test_fps_certificate_v26",
            withExtension: "bin"
        ) else {
            throw DRMConfigurationError.certificateNotFound
        }

        do {
            let certData = try Data(contentsOf: bundleURL)
            guard !certData.isEmpty else {
                throw DRMConfigurationError.certificateEmpty
            }
            return certData
        } catch {
            throw DRMConfigurationError.certificateLoadFailed(error)
        }
    }
}

/// DRM configuration errors
public enum DRMConfigurationError: Error, LocalizedError {
    case certificateNotFound
    case certificateEmpty
    case certificateLoadFailed(Error)
    case invalidServerURL

    public var errorDescription: String? {
        switch self {
        case .certificateNotFound:
            "FairPlay Streaming certificate not found in bundle"
        case .certificateEmpty:
            "FairPlay Streaming certificate is empty"
        case .certificateLoadFailed(let error):
            "Failed to load FairPlay Streaming certificate: \(error.localizedDescription)"
        case .invalidServerURL:
            "Invalid media server URL"
        }
    }
}
