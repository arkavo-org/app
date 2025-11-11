import Foundation
import MultipeerConnectivity

extension InputStream: @retroactive @unchecked Sendable {}
extension MCPeerID: @retroactive @unchecked Sendable {}

extension Data {
    static var didPostRetryConnection: Bool {
        get { UserDefaults.standard.bool(forKey: "notification_RetryConnection") }
        set { UserDefaults.standard.set(newValue, forKey: "notification_RetryConnection") }
    }

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

import UIKit

extension UIImage {
    func heifData(maxSizeBytes: Int = 1_048_576, initialQuality: CGFloat = 0.9) -> Data? {
        var compressionQuality = initialQuality
        var imageData: Data?

        while compressionQuality > 0.1 {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.heic" as CFString, 1, nil) else {
                return nil
            }

            let options: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: compressionQuality,
                kCGImageDestinationOptimizeColorForSharing: true,
            ]

            guard let cgImage else {
                return nil
            }

            CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

            if CGImageDestinationFinalize(destination) {
                imageData = data as Data
                if let imageData, imageData.count <= maxSizeBytes {
                    return imageData
                }
            }

            compressionQuality -= 0.1
        }

        // If we couldn't get it under the limit, return nil or consider other options
        return nil
    }
}

