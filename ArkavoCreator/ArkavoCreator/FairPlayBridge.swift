import ArkavoMediaKit
import Foundation

// MARK: - HLS Manifest for FairPlay

/// Lightweight HLS manifest structure for FairPlay key exchange
/// Conforms to FairPlayManifestProtocol for use with TDFContentKeyDelegate
public struct HLSManifestLite: FairPlayManifestProtocol, Sendable {
    public let kasURL: String
    public let wrappedKey: String
    public let algorithm: String
    public let iv: String
    public let assetID: String

    public init(
        kasURL: String,
        wrappedKey: String,
        algorithm: String,
        iv: String,
        assetID: String
    ) {
        self.kasURL = kasURL
        self.wrappedKey = wrappedKey
        self.algorithm = algorithm
        self.iv = iv
        self.assetID = assetID
    }
}

// MARK: - Type Alias for Convenience

/// Type alias for TDFContentKeyDelegate using HLSManifestLite
public typealias HLSContentKeyDelegate = TDFContentKeyDelegate<HLSManifestLite>
