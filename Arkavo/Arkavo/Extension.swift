import Compression
import Foundation

extension DateFormatter {
    static let shortDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension Data {
    var base58EncodedString: String {
        Base58.encode([UInt8](self))
    }

    init?(base58Encoded string: String) {
        guard let bytes = Base58.decode(string) else { return nil }
        self = Data(bytes)
    }

    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        for i in 0 ..< len {
            let j = hexString.index(hexString.startIndex, offsetBy: i * 2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j ..< k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        self = data
    }
}

enum Base58 {
    private static let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    private static let base = alphabet.count

    static func encode(_ bytes: [UInt8]) -> String {
        var bytes = bytes
        var zerosCount = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        var result = [UInt8]()
        for b in bytes {
            var carry = Int(b)
            for j in 0 ..< result.count {
                carry += Int(result[j]) << 8
                result[j] = UInt8(carry % base)
                carry /= base
            }
            while carry > 0 {
                result.append(UInt8(carry % base))
                carry /= base
            }
        }

        let prefix = String(repeating: alphabet.first!, count: zerosCount)
        let encoded = result.reversed().map { alphabet[alphabet.index(alphabet.startIndex, offsetBy: Int($0))] }
        return prefix + String(encoded)
    }

    static func decode(_ string: String) -> [UInt8]? {
        var result = [UInt8]()
        for char in string {
            guard let charIndex = alphabet.firstIndex(of: char) else { return nil }
            let index = alphabet.distance(from: alphabet.startIndex, to: charIndex)

            var carry = index
            for j in 0 ..< result.count {
                carry += Int(result[j]) * base
                result[j] = UInt8(carry & 0xFF)
                carry >>= 8
            }

            while carry > 0 {
                result.append(UInt8(carry & 0xFF))
                carry >>= 8
            }
        }

        for char in string {
            if char != alphabet.first! { break }
            result.append(0)
        }

        return result.reversed()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func hexEncodedString() -> String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

extension String {
    func base64URLToBase64() -> String {
        var base64 = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        return base64
    }

    var base58Decoded: Data? {
        Data(base58Encoded: self)
    }
}

// MARK: - Data Compression Extensions

extension Data {
    func compressed() throws -> Data {
        guard !isEmpty else { return self }

        let sourceSize = count
        let destinationSize = sourceSize + 64 * 1024 // Add headroom for compression
        var destinationBuffer = Data(count: destinationSize)

        let result = try destinationBuffer.withUnsafeMutableBytes { destinationPtr -> Int in
            guard let destinationAddress = destinationPtr.baseAddress else {
                throw CompressionError.invalidPointer
            }

            return try self.withUnsafeBytes { sourcePtr -> Int in
                guard let sourceAddress = sourcePtr.baseAddress else {
                    throw CompressionError.invalidPointer
                }

                return compression_encode_buffer(
                    destinationAddress.assumingMemoryBound(to: UInt8.self),
                    destinationSize,
                    sourceAddress.assumingMemoryBound(to: UInt8.self),
                    sourceSize,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.compressionFailed
        }

        return destinationBuffer.prefix(result)
    }

    func decompressed() throws -> Data {
        guard !isEmpty else { return self }

        let sourceSize = count
        let destinationSize = sourceSize * 4 // Estimate expanded size
        var destinationBuffer = Data(count: destinationSize)

        let result = try destinationBuffer.withUnsafeMutableBytes { destinationPtr -> Int in
            guard let destinationAddress = destinationPtr.baseAddress else {
                throw CompressionError.invalidPointer
            }

            return try self.withUnsafeBytes { sourcePtr -> Int in
                guard let sourceAddress = sourcePtr.baseAddress else {
                    throw CompressionError.invalidPointer
                }

                return compression_decode_buffer(
                    destinationAddress.assumingMemoryBound(to: UInt8.self),
                    destinationSize,
                    sourceAddress.assumingMemoryBound(to: UInt8.self),
                    sourceSize,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }

        guard result > 0 else {
            throw CompressionError.decompressionFailed
        }

        return destinationBuffer.prefix(result)
    }

    /// Get compression ratio
    var compressionRatio: Double {
        guard !isEmpty else { return 1.0 }
        do {
            let compressed = try compressed()
            return Double(compressed.count) / Double(count)
        } catch {
            return 1.0
        }
    }
}
