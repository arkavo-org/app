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
    private static let baseCount = UInt8(alphabet.count)

    static func encode(_ bytes: [UInt8]) -> String {
        var bytes = bytes
        var zerosCount = 0
        var length = 0

        for b in bytes {
            if b != 0 { break }
            zerosCount += 1
        }

        bytes.removeFirst(zerosCount)

        let size = bytes.count * 138 / 100 + 1

        var base58: [UInt8] = Array(repeating: 0, count: size)
        for b in bytes {
            var carry = Int(b)
            var i = 0

            for j in 0 ... base58.count - 1 where carry != 0 || i < length {
                carry += 256 * Int(base58[base58.count - 1 - j])
                base58[base58.count - 1 - j] = UInt8(carry % 58)
                carry /= 58
                i += 1
            }

            assert(carry == 0)

            length = i
        }

        var string = ""
        for _ in 0 ..< zerosCount {
            string += "1"
        }

        for b in base58[base58.count - length ..< base58.count].reversed() {
            string += String(alphabet[alphabet.index(alphabet.startIndex, offsetBy: Int(b))])
        }

        return string
    }

    static func decode(_ base58: String) -> [UInt8]? {
        var result = [UInt8]()
        var leadingZeros = 0
        var value: UInt = 0
        var base: UInt = 1

        for char in base58.reversed() {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            let index = alphabet.distance(from: alphabet.startIndex, to: digit)
            value += UInt(index) * base
            base *= UInt(baseCount)

            if value > UInt(UInt8.max) {
                var mod = value
                while mod > 0 {
                    result.insert(UInt8(mod & 0xFF), at: 0)
                    mod >>= 8
                }
                value = 0
                base = 1
            }
        }

        if value > 0 {
            result.insert(UInt8(value), at: 0)
        }

        for char in base58 {
            guard char == "1" else { break }
            leadingZeros += 1
        }

        result.insert(contentsOf: repeatElement(0, count: leadingZeros), at: 0)
        return result
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
