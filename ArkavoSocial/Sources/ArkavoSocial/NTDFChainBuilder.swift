import Foundation
import OpenTDFKit
import CryptoKit

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

        // The "payload" is the actual user data or a marker
        // For authorization tokens, this could be empty or contain additional context
        let payload = Data("PE".utf8)

        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &policy,
            plaintext: payload
        )

        // TODO: Sign the Origin Link once OpenTDFKit exposes SignatureAndPayloadConfig
        // For now, signatures are optional in the spec
        // try await addSignatureToNanoTDF(nanoTDF: &nanoTDF, privateKey: signingKey, config: config)

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

        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &policy,
            plaintext: innerLinkData  // Nested NanoTDF as payload
        )

        // TODO: Sign the Intermediate Link once OpenTDFKit exposes SignatureAndPayloadConfig
        // For now, signatures are optional in the spec
        // try await addSignatureToNanoTDF(nanoTDF: &nanoTDF, privateKey: signingKey, config: config)

        return nanoTDF
    }

    /// Extracts and validates a nested NanoTDF from the payload
    public func extractInnerLink(
        outerLink: NanoTDF,
        keyStore: KeyStore
    ) async throws -> NanoTDF {
        // Decrypt the outer link's payload
        let innerLinkData = try await outerLink.getPlaintext(using: keyStore)

        // Parse the inner NanoTDF
        return try await parseNanoTDF(data: innerLinkData)
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
