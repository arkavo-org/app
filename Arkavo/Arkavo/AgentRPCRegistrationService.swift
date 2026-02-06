import ArkavoAgent
import ArkavoSocial
import Foundation

/// Handles WebSocket-based agent registration using JSON-RPC
/// Uses the registration.challenge and registration.verify methods
actor AgentRPCRegistrationService {
    private let transport: any AgentTransportProtocol

    init(transport: any AgentTransportProtocol) {
        self.transport = transport
    }

    /// Performs the full registration flow: challenge -> sign -> verify
    /// - Parameter deviceId: The device's DID key for registration
    /// - Returns: true if registration succeeded
    func register(deviceId: String) async throws -> Bool {
        // Step 1: Request challenge from agent
        let challengeRequest = AgentRequest(
            method: "registration.challenge",
            params: AnyCodable(["device_id": deviceId])
        )
        let challengeResponse = try await transport.sendRequest(challengeRequest)

        guard case .success(_, let result) = challengeResponse,
              let dict = result.value as? [String: Any],
              let challengeId = dict["challenge_id"] as? String,
              let challengeB64 = dict["challenge"] as? String else {
            throw RegistrationError.invalidChallengeResponse
        }

        // Step 2: Decode base64 challenge
        guard let challengeData = Data(base64Encoded: challengeB64) else {
            throw RegistrationError.invalidChallengeFormat
        }

        // Step 3: Sign challenge with device's DID key
        let (publicKey, signature) = try signChallenge(challengeData)

        // Step 4: Send verify request
        let verifyRequest = AgentRequest(
            method: "registration.verify",
            params: AnyCodable([
                "challenge_id": challengeId,
                "device_id": deviceId,
                "public_key": publicKey,
                "signature": signature
            ])
        )
        let verifyResponse = try await transport.sendRequest(verifyRequest)

        guard case .success(_, let verifyResult) = verifyResponse,
              let verifyDict = verifyResult.value as? [String: Any],
              let success = verifyDict["success"] as? Bool else {
            throw RegistrationError.invalidVerifyResponse
        }

        return success
    }

    private func signChallenge(_ data: Data) throws -> (publicKey: String, signature: String) {
        let signature = try KeychainManager.signWithDIDKey(message: data)
        let (_, publicKey, _) = try KeychainManager.getDIDKey()

        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw RegistrationError.noSigningKey
        }

        return (
            publicKey: publicKeyData.base64EncodedString(),
            signature: signature.base64EncodedString()
        )
    }
}

/// Protocol for transport abstraction (enables testing)
protocol AgentTransportProtocol: Sendable {
    func sendRequest(_ request: AgentRequest) async throws -> AgentResponse
}

extension AgentWebSocketTransport: AgentTransportProtocol {}

/// Errors that can occur during RPC registration
enum RegistrationError: LocalizedError, Equatable {
    case invalidChallengeResponse
    case invalidChallengeFormat
    case invalidVerifyResponse
    case noSigningKey
    case registrationFailed
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidChallengeResponse:
            return "Invalid challenge response from agent"
        case .invalidChallengeFormat:
            return "Challenge data is not valid base64"
        case .invalidVerifyResponse:
            return "Invalid verification response from agent"
        case .noSigningKey:
            return "No signing key available"
        case .registrationFailed:
            return "Registration verification failed"
        case .connectionFailed(let details):
            return "Connection failed: \(details)"
        }
    }
}
