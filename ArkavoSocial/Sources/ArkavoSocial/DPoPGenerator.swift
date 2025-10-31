import Foundation
import CryptoKit

/// Generates DPoP (Demonstration of Proof-of-Possession) headers for HTTP requests
/// Implements RFC 9449 - OAuth 2.0 Demonstrating Proof of Possession (DPoP)
public actor DPoPGenerator {

    /// Errors that can occur during DPoP generation
    public enum DPoPError: Error {
        case invalidURL
        case signingFailed
        case encodingFailed
        case noSigningKey
    }

    private let signingKey: P256.Signing.PrivateKey
    private let publicKeyJWK: [String: Any]

    /// Initializes the DPoP generator with a signing key
    /// - Parameter signingKey: The P-256 private key for signing DPoP proofs
    public init(signingKey: P256.Signing.PrivateKey) {
        self.signingKey = signingKey

        // Create JWK representation of public key
        let publicKey = signingKey.publicKey
        let x963Representation = publicKey.x963Representation

        // Extract x and y coordinates (skip the first byte which is 0x04 for uncompressed)
        let coordinates = x963Representation.dropFirst()
        let x = coordinates.prefix(32)
        let y = coordinates.suffix(32)

        self.publicKeyJWK = [
            "kty": "EC",
            "crv": "P-256",
            "x": Data(x).base64URLEncodedString(),
            "y": Data(y).base64URLEncodedString()
        ]
    }

    /// Generates a DPoP proof for an HTTP request
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - url: The target URL
    ///   - accessToken: Optional access token hash (for binding)
    /// - Returns: The DPoP proof JWT string
    public func generateDPoPProof(
        method: String,
        url: URL,
        accessToken: String? = nil
    ) async throws -> String {

        // Generate a unique jti (JWT ID) for this proof
        let jti = UUID().uuidString

        // Current timestamp
        let iat = Int(Date().timeIntervalSince1970)

        // Create the DPoP header
        var header: [String: Any] = [
            "typ": "dpop+jwt",
            "alg": "ES256",
            "jwk": publicKeyJWK
        ]

        // Create the DPoP claims
        var claims: [String: Any] = [
            "jti": jti,
            "htm": method.uppercased(),
            "htu": url.absoluteString,
            "iat": iat
        ]

        // Add access token hash if provided (for token binding)
        if let accessToken {
            let tokenHash = SHA256.hash(data: accessToken.data(using: .utf8)!)
            claims["ath"] = Data(tokenHash).base64URLEncodedString()
        }

        // Encode header and claims
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let claimsData = try? JSONSerialization.data(withJSONObject: claims) else {
            throw DPoPError.encodingFailed
        }

        let headerB64 = headerData.base64URLEncodedString()
        let claimsB64 = claimsData.base64URLEncodedString()

        // Create signing input
        let signingInput = "\(headerB64).\(claimsB64)"
        guard let signingData = signingInput.data(using: .utf8) else {
            throw DPoPError.encodingFailed
        }

        // Sign the JWT
        let signature = try signingKey.signature(for: signingData)

        // Convert DER signature to raw format (R || S)
        let rawSignature = try convertDERSignatureToRaw(signature.derRepresentation)

        let signatureB64 = rawSignature.base64URLEncodedString()

        // Return the complete JWT
        return "\(signingInput).\(signatureB64)"
    }

    /// Validates a DPoP proof (for testing/verification)
    /// - Parameters:
    ///   - proof: The DPoP proof JWT
    ///   - method: Expected HTTP method
    ///   - url: Expected URL
    /// - Returns: True if valid, false otherwise
    public func validateDPoPProof(
        proof: String,
        method: String,
        url: URL
    ) async throws -> Bool {
        let parts = proof.split(separator: ".")
        guard parts.count == 3 else {
            return false
        }

        // Decode header and claims
        guard let headerData = Data(base64URLEncoded: String(parts[0])),
              let claimsData = Data(base64URLEncoded: String(parts[1])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let claims = try? JSONSerialization.jsonObject(with: claimsData) as? [String: Any] else {
            return false
        }

        // Verify header
        guard header["typ"] as? String == "dpop+jwt",
              header["alg"] as? String == "ES256" else {
            return false
        }

        // Verify claims
        guard let htm = claims["htm"] as? String,
              let htu = claims["htu"] as? String,
              htm == method.uppercased(),
              htu == url.absoluteString else {
            return false
        }

        // Verify timestamp (within 60 seconds)
        if let iat = claims["iat"] as? Int {
            let now = Int(Date().timeIntervalSince1970)
            if abs(now - iat) > 60 {
                return false
            }
        }

        // TODO: Verify signature with public key from JWK
        // For now, return true if structure is valid
        return true
    }

    /// Converts DER signature to raw format (R || S) for JWT
    private func convertDERSignatureToRaw(_ der: Data) throws -> Data {
        // DER format for ECDSA signature is:
        // 0x30 [total-length] 0x02 [R-length] [R] 0x02 [S-length] [S]

        var index = 0

        // Check SEQUENCE tag
        guard der[index] == 0x30 else {
            throw DPoPError.signingFailed
        }
        index += 1

        // Skip total length
        index += 1

        // Parse R
        guard der[index] == 0x02 else {
            throw DPoPError.signingFailed
        }
        index += 1

        let rLength = Int(der[index])
        index += 1

        var r = der[index..<(index + rLength)]
        index += rLength

        // Remove leading zero if present (padding for sign bit)
        if r.first == 0x00 {
            r = r.dropFirst()
        }

        // Pad to 32 bytes if needed
        if r.count < 32 {
            r = Data(repeating: 0, count: 32 - r.count) + r
        }

        // Parse S
        guard der[index] == 0x02 else {
            throw DPoPError.signingFailed
        }
        index += 1

        let sLength = Int(der[index])
        index += 1

        var s = der[index..<(index + sLength)]

        // Remove leading zero if present
        if s.first == 0x00 {
            s = s.dropFirst()
        }

        // Pad to 32 bytes if needed
        if s.count < 32 {
            s = Data(repeating: 0, count: 32 - s.count) + s
        }

        // Concatenate R || S
        return r + s
    }
}

// MARK: - Base64URL Extension

private extension Data {
    /// Encodes data as Base64URL (RFC 4648)
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes Base64URL encoded string
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            return nil
        }

        self = data
    }
}
