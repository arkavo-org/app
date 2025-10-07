import Foundation

/// Cryptographic constants for ArkavoMediaKit
public enum CryptoConstants {
    /// AES-GCM tag length in bytes
    public static let aesgcmTagLength = 16

    /// Nonce length for AES-GCM in bytes
    public static let nonceLengthBytes = 12

    /// NanoTDF IV length in bytes (spec uses 3 bytes)
    public static let nanoTDFIVLength = 3

    /// NanoTDF length field size in bytes (UInt24)
    public static let nanoTDFLengthFieldSize = 3

    /// NanoTDF magic number "L1L" (version 12)
    public static let nanoTDFMagicV12: [UInt8] = [0x4C, 0x31, 0x4C] // "L1L"

    /// NanoTDF magic number "L1M" (version 13)
    public static let nanoTDFMagicV13: [UInt8] = [0x4C, 0x31, 0x4D] // "L1M"

    /// Supported NanoTDF versions
    public enum Version: UInt8 {
        case v12 = 12
        case v13 = 13
    }

    /// AES key sizes
    public enum AESKeySize {
        case bits128
        case bits192
        case bits256

        public var bytes: Int {
            switch self {
            case .bits128: 16
            case .bits192: 24
            case .bits256: 32
            }
        }
    }

    /// Maximum segment size (100 MB)
    public static let maxSegmentSize = 100 * 1024 * 1024

    /// Maximum playlist segments
    public static let maxPlaylistSegments = 10000
}
