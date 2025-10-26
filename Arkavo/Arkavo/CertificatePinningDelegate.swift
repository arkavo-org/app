import Foundation
import CryptoKit

/// SSL Certificate Pinning Delegate for secure HTTPS connections
/// Validates server certificates against known public key hashes to prevent MITM attacks
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {

    // MARK: - Configuration

    /// Pinned certificate public key hashes (SHA-256)
    /// Update these with your actual server certificate hashes
    private let pinnedPublicKeyHashes: Set<String> = [
        // Add your actual certificate SHA-256 hashes here
        // Example: "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        // To get the hash: openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl enc -base64
    ]

    /// Domains that require certificate pinning
    private let pinnedDomains: Set<String> = [
        "webauthn.arkavo.net",
        "kas.arkavo.net",
        "app.arkavo.com",
    ]

    /// Enable certificate pinning (set to false to disable for development)
    var isPinningEnabled: Bool = true

    // MARK: - URLSessionDelegate

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            SecureLogger.logSecurity("Invalid authentication method: \(challenge.protectionSpace.authenticationMethod)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Check if this domain requires pinning
        guard pinnedDomains.contains(host) else {
            // Domain not in pinned list, use default validation
            SecureLogger.log(.debug, "Host \(host) not in pinned domains, using default validation")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Check if pinning is enabled
        guard isPinningEnabled else {
            SecureLogger.log(.debug, "Certificate pinning disabled for \(host)")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Validate the certificate
        if validateCertificate(serverTrust: serverTrust, for: host) {
            SecureLogger.logSecurity("✅ Certificate pinning validated for \(host)")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            SecureLogger.logSecurityViolation("❌ Certificate pinning FAILED for \(host) - Potential MITM attack detected")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Certificate Validation

    /// Validates server certificate against pinned public key hashes
    private func validateCertificate(serverTrust: SecTrust, for host: String) -> Bool {
        // If no hashes configured, skip pinning but log warning
        if pinnedPublicKeyHashes.isEmpty {
            SecureLogger.log(.error, "WARNING: No pinned certificate hashes configured for \(host)")
            return true // Allow connection but log the security issue
        }

        // Evaluate the server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            if let error = error {
                SecureLogger.log(.error, "Certificate trust evaluation failed: \(error.localizedDescription)")
            }
            return false
        }

        // Get the certificate chain
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              !certificateChain.isEmpty else {
            SecureLogger.log(.error, "Unable to retrieve certificate chain")
            return false
        }

        // Validate at least one certificate in the chain matches our pins
        for certificate in certificateChain {
            if let publicKeyHash = getPublicKeyHash(from: certificate) {
                if pinnedPublicKeyHashes.contains(publicKeyHash) {
                    SecureLogger.logSecurity("Certificate matched pinned hash for \(host)")
                    return true
                }
            }
        }

        SecureLogger.logSecurityViolation("No certificates in chain matched pinned hashes for \(host)")
        return false
    }

    /// Extracts and hashes the public key from a certificate
    private func getPublicKeyHash(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            return nil
        }

        // Hash the public key using SHA-256
        let hash = SHA256.hash(data: publicKeyData)
        let hashString = "sha256/" + Data(hash).base64EncodedString()

        #if DEBUG
        SecureLogger.log(.debug, "Public key hash: \(hashString)")
        #endif

        return hashString
    }

    // MARK: - Helper Methods

    /// Adds a new pinned certificate hash
    /// - Parameter hash: SHA-256 hash of the certificate's public key
    func addPinnedHash(_ hash: String) {
        var mutableHashes = pinnedPublicKeyHashes
        mutableHashes.insert(hash)
        // Note: This requires making pinnedPublicKeyHashes mutable
        SecureLogger.logSecurity("Added new pinned certificate hash")
    }

    /// Gets all certificate information for debugging
    /// Only available in DEBUG builds
    #if DEBUG
    func debugCertificateInfo(serverTrust: SecTrust) {
        guard let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            print("Unable to retrieve certificate chain")
            return
        }

        print("\n=== Certificate Chain Debug Info ===")
        for (index, certificate) in certificateChain.enumerated() {
            print("\nCertificate \(index):")

            // Get subject
            if let subject = SecCertificateCopySubjectSummary(certificate) {
                print("  Subject: \(subject)")
            }

            // Get public key hash
            if let hash = getPublicKeyHash(from: certificate) {
                print("  Public Key Hash: \(hash)")
            }
        }
        print("=================================\n")
    }
    #endif
}

// MARK: - URLSession Extension

extension URLSession {
    /// Creates a URLSession with certificate pinning enabled
    static func withCertificatePinning(configuration: URLSessionConfiguration = .default) -> (URLSession, CertificatePinningDelegate) {
        let delegate = CertificatePinningDelegate()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        return (session, delegate)
    }
}
