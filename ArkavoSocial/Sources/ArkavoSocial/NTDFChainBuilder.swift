import Foundation
import OpenTDFKit
import CryptoKit

/// Signed payload structure that wraps data with a cryptographic signature
public struct SignedPayload: Codable, Sendable {
    /// The actual payload data (could be nested NanoTDF, user data, etc.)
    public let data: Data
    /// ECDSA signature over (claims + data)
    public let signature: Data
    /// Public key used for signing (compressed format)
    public let publicKey: Data
    /// Timestamp when signature was created
    public let timestamp: Date
    /// Algorithm used (always "ES256" for P-256)
    public let algorithm: String

    public init(data: Data, signature: Data, publicKey: Data, timestamp: Date = Date(), algorithm: String = "ES256") {
        self.data = data
        self.signature = signature
        self.publicKey = publicKey
        self.timestamp = timestamp
        self.algorithm = algorithm
    }

    /// Serializes to JSON for inclusion in NanoTDF payload
    public func toData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Parses from JSON payload
    public static func from(data: Data) throws -> SignedPayload {
        try JSONDecoder().decode(SignedPayload.self, from: data)
    }

    /// Verifies the signature against the provided claims
    public func verify(claims: Data) throws -> Bool {
        // Reconstruct the signed message: claims + data
        let message = claims + data

        // Parse the public key
        let pubKey = try P256.Signing.PublicKey(compressedRepresentation: publicKey)

        // Create signature object
        let sig = try P256.Signing.ECDSASignature(derRepresentation: signature)

        // Verify
        return pubKey.isValidSignature(sig, for: message)
    }
}

/// Builds NTDF Profile v1.2 Chain of Trust by nesting NanoTDF containers
/// According to the spec, NanoTDF payloads can contain arbitrary data, including other NanoTDFs
public actor NTDFChainBuilder {

    private let deviceAttestationManager = DeviceAttestationManager()

    /// Creates a 3-link NTDF Chain of Trust for authorization with automatic device attestation
    /// Chain structure: Terminal Link (outer) → Intermediate Link (NPE) → Origin Link (PE)
    ///
    /// - Parameters:
    ///   - userId: User identifier for PE claims
    ///   - authLevel: Authentication level achieved (biometric, webauthn, etc.)
    ///   - appVersion: Application version string
    ///   - kasPublicKey: KAS public key for encryption
    /// - Returns: The complete 3-link chain ready for transmission to IdP to obtain Terminal Link
    public func createAuthorizationChain(
        userId: String,
        authLevel: PEClaims.AuthLevel,
        appVersion: String,
        kasPublicKey: P256.KeyAgreement.PublicKey
    ) async throws -> NTDFAuthorizationChain {

        // Generate PE claims
        let peClaims = PEClaims(
            userId: userId,
            authLevel: authLevel,
            timestamp: Date()
        )

        // Generate NPE claims with device attestation
        let npeClaims = try await deviceAttestationManager.generateNPEClaims(appVersion: appVersion)

        return try await createAuthorizationChain(
            peClaims: peClaims,
            npeClaims: npeClaims,
            kasPublicKey: kasPublicKey
        )
    }

    /// Creates a 3-link NTDF Chain of Trust for authorization
    /// Chain structure: Terminal Link (outer) → Intermediate Link (NPE) → Origin Link (PE)
    ///
    /// - Parameters:
    ///   - peClaims: Person Entity claims
    ///   - npeClaims: Non-Person Entity claims
    ///   - kasPublicKey: KAS public key for encryption
    /// - Returns: The complete 3-link chain ready for transmission to IdP to obtain Terminal Link
    public func createAuthorizationChain(
        peClaims: PEClaims,
        npeClaims: NPEClaims,
        kasPublicKey: P256.KeyAgreement.PublicKey
    ) async throws -> NTDFAuthorizationChain {

        let originClaims = try peClaims.toData()
        let intermediateClaims = try npeClaims.toData()

        // Step 1: Create Origin Link (PE - innermost)
        // This attests to the authenticated user
        let originLink = try await createOriginLink(
            claims: originClaims,
            kasPublicKey: kasPublicKey
        )

        // Step 2: Create Intermediate Link (NPE)
        // This attests to the device/app and wraps the Origin Link
        let intermediateLink = try await createIntermediateLink(
            claims: intermediateClaims,
            innerLink: originLink,
            kasPublicKey: kasPublicKey
        )

        return NTDFAuthorizationChain(
            originLink: originLink,
            intermediateLink: intermediateLink
        )
    }

    /// Creates the Origin Link (PE attestation)
    /// This is the innermost link containing user identity claims
    private func createOriginLink(
        claims: Data,
        kasPublicKey: P256.KeyAgreement.PublicKey
    ) async throws -> NanoTDF {

        let kasMetadata = try KasMetadata(
            resourceLocator: ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!,
            publicKey: kasPublicKey,
            curve: .secp256r1
        )

        // Policy for Origin Link - embedded plaintext with PE claims
        var policy = Policy(
            type: .embeddedPlaintext,
            body: EmbeddedPolicyBody(body: claims),
            remote: nil,
            binding: nil
        )

        // Create signed payload
        let userData = Data("PE".utf8)  // Could be actual user data
        let signedPayload = try await createSignedPayload(
            data: userData,
            claims: claims
        )

        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &policy,
            plaintext: try signedPayload.toData()
        )

        return nanoTDF
    }

    /// Creates the Intermediate Link (NPE attestation)
    /// This wraps the Origin Link in its payload, creating the chain
    private func createIntermediateLink(
        claims: Data,
        innerLink: NanoTDF,
        kasPublicKey: P256.KeyAgreement.PublicKey
    ) async throws -> NanoTDF {

        let kasMetadata = try KasMetadata(
            resourceLocator: ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!,
            publicKey: kasPublicKey,
            curve: .secp256r1
        )

        // Policy for Intermediate Link - embedded plaintext with NPE claims
        // The policy contains device/app attestation data
        var policy = Policy(
            type: .embeddedPlaintext,
            body: EmbeddedPolicyBody(body: claims),
            remote: nil,
            binding: nil
        )

        // KEY INSIGHT: The payload is the serialized Origin Link NanoTDF
        // This creates the chain by nesting
        let innerLinkData = innerLink.toData()

        // Create signed payload wrapping the inner link
        let signedPayload = try await createSignedPayload(
            data: innerLinkData,
            claims: claims
        )

        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &policy,
            plaintext: try signedPayload.toData()
        )

        return nanoTDF
    }

    /// Creates a signed payload wrapping data with claims
    private func createSignedPayload(
        data: Data,
        claims: Data
    ) async throws -> SignedPayload {
        // Get DID key from keychain for signing
        let didKey = try KeychainManager.getDIDKey()

        // Message to sign: claims + data
        let message = claims + data

        // Sign with DID private key
        let signature = try KeychainManager.signWithDIDKey(message: message)

        // Get public key
        let publicKey = didKey.publicKey

        // Convert SecKey public key to P256 compressed representation
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw NTDFChainError.signingFailed
        }

        // Convert uncompressed (65 bytes) to compressed (33 bytes)
        let compressedPublicKey: Data
        if publicKeyData.count == 65 {
            // First byte is 0x04 (uncompressed), next 32 bytes are x, last 32 are y
            let x = publicKeyData[1..<33]
            let y = publicKeyData[33..<65]
            let yLastByte = y.last!
            let prefix: UInt8 = (yLastByte & 1) == 0 ? 0x02 : 0x03
            compressedPublicKey = Data([prefix]) + x
        } else {
            compressedPublicKey = publicKeyData
        }

        return SignedPayload(
            data: data,
            signature: signature,
            publicKey: compressedPublicKey
        )
    }

    /// Extracts and validates a nested NanoTDF from the payload
    public func extractInnerLink(
        outerLink: NanoTDF,
        keyStore: KeyStore
    ) async throws -> NanoTDF {
        // Decrypt the outer link's payload
        let decryptedPayload = try await outerLink.getPlaintext(using: keyStore)

        // Parse as SignedPayload
        let signedPayload = try SignedPayload.from(data: decryptedPayload)

        // Verify signature (claims are in the policy)
        let claims = outerLink.header.policy.body?.body ?? Data()
        guard try signedPayload.verify(claims: claims) else {
            throw NTDFChainError.signatureVerificationFailed
        }

        // Extract inner link data
        return try await parseNanoTDF(data: signedPayload.data)
    }

    /// Parses a NanoTDF from raw data
    /// Note: This requires BinaryParser which may need to be public in OpenTDFKit
    private func parseNanoTDF(data: Data) async throws -> NanoTDF {
        // TODO: OpenTDFKit needs to expose BinaryParser.parse() as public
        // For now, this is a placeholder
        throw NTDFChainError.parsingNotAvailable
    }
}

/// Represents a complete NTDF authorization chain
/// This is sent to the IdP to obtain the Terminal Link
public struct NTDFAuthorizationChain: Sendable {
    /// The innermost link (PE attestation)
    public let originLink: NanoTDF

    /// The middle link (NPE attestation) containing the Origin Link
    public let intermediateLink: NanoTDF

    /// Serializes the chain for transmission to IdP
    /// The IdP will wrap this in a Terminal Link
    public func toData() -> Data {
        // Send the Intermediate Link (which contains Origin Link in its payload)
        intermediateLink.toData()
    }
}

/// Errors specific to NTDF chain operations
public enum NTDFChainError: Error {
    case invalidChain
    case parsingNotAvailable
    case invalidClaims
    case signatureVerificationFailed
    case signingFailed
}

/// Person Entity (PE) claims for Origin Link
public struct PEClaims: Codable, Sendable {
    public let userId: String
    public let authLevel: AuthLevel
    public let timestamp: Date

    public enum AuthLevel: String, Codable, Sendable {
        case biometric
        case password
        case mfa
        case webauthn
    }

    public init(userId: String, authLevel: AuthLevel, timestamp: Date = Date()) {
        self.userId = userId
        self.authLevel = authLevel
        self.timestamp = timestamp
    }

    public func toData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

/// Non-Person Entity (NPE) claims for Intermediate Link
public struct NPEClaims: Codable, Sendable {
    public let platformCode: PlatformCode
    public let platformState: PlatformState
    public let deviceId: String
    public let appVersion: String
    public let timestamp: Date

    public enum PlatformCode: String, Codable, Sendable {
        case iOS
        case macOS
        case tvOS
        case watchOS
    }

    public enum PlatformState: String, Codable, Sendable {
        case secure
        case jailbroken
        case debugMode
        case unknown
    }

    public init(
        platformCode: PlatformCode,
        platformState: PlatformState,
        deviceId: String,
        appVersion: String,
        timestamp: Date = Date()
    ) {
        self.platformCode = platformCode
        self.platformState = platformState
        self.deviceId = deviceId
        self.appVersion = appVersion
        self.timestamp = timestamp
    }

    public func toData() throws -> Data {
        try JSONEncoder().encode(self)
    }
}
