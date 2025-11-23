import ArkavoSocial
import Foundation
import OpenTDFKit

@MainActor
class EncryptionManager: ObservableObject {
    @Published var encryptionEnabled = true
    @Published var isEncrypting = false
    @Published var encryptionError: String?

    private let arkavoClient: ArkavoClient
    private var groupPolicies: [String: Data] = [:]

    init(arkavoClient: ArkavoClient) {
        self.arkavoClient = arkavoClient
    }

    /// Generate or retrieve policy for a group
    func getPolicy(for groupId: String) throws -> Data {
        // Check if we already have a policy for this group
        if let existingPolicy = groupPolicies[groupId] {
            return existingPolicy
        }

        // Create a new policy for the group
        let policy = try createGroupPolicy(groupId: groupId)
        groupPolicies[groupId] = policy
        return policy
    }

    /// Create a policy for a group
    private func createGroupPolicy(groupId: String) throws -> Data {
        // Create a simple embedded policy
        // In production, this would include access control lists, attributes, etc.
        let policyJSON: [String: Any] = [
            "uuid": UUID().uuidString,
            "body": [
                "dataAttributes": [],
                "dissem": ["group_\(groupId)"]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: policyJSON)
    }

    /// Encrypt a message payload
    func encryptMessage(_ message: Data, groupId: String) async throws -> Data {
        isEncrypting = true
        encryptionError = nil

        defer {
            isEncrypting = false
        }

        do {
            let policyData = try getPolicy(for: groupId)

            // Use ArkavoClient's encryption with embedded policy
            let encryptedData = try await arkavoClient.encryptAndSendPayload(
                payload: message,
                policyData: policyData
            )

            print("Message encrypted successfully: \(encryptedData.count) bytes")
            return encryptedData
        } catch {
            encryptionError = "Encryption failed: \(error.localizedDescription)"
            print("Encryption error: \(error)")
            throw error
        }
    }

    /// Encrypt a message using remote policy
    func encryptMessageRemote(_ message: Data, remotePolicyBody: String) async throws -> Data {
        isEncrypting = true
        encryptionError = nil

        defer {
            isEncrypting = false
        }

        do {
            let encryptedData = try await arkavoClient.encryptRemotePolicy(
                payload: message,
                remotePolicyBody: remotePolicyBody
            )

            print("Message encrypted with remote policy: \(encryptedData.count) bytes")
            return encryptedData
        } catch {
            encryptionError = "Encryption failed: \(error.localizedDescription)"
            print("Encryption error: \(error)")
            throw error
        }
    }

    /// Decrypt a NanoTDF message
    func decryptMessage(_ encryptedData: Data) async throws -> Data {
        do {
            print("Decrypting message: \(encryptedData.count) bytes")

            // Use ArkavoClient's decryption which handles the KAS rewrap protocol
            let decryptedData = try await arkavoClient.decryptNanoTDF(encryptedData)

            print("Message decrypted successfully: \(decryptedData.count) bytes")
            return decryptedData
        } catch {
            encryptionError = "Decryption failed: \(error.localizedDescription)"
            print("Decryption error: \(error)")
            throw error
        }
    }

    /// Send rewrap request to KAS
    private func sendRewrapRequest(_ request: RewrapRequest, to kasURL: URL) async throws -> RewrapResponse {
        var urlRequest = URLRequest(url: kasURL.appendingPathComponent("/rewrap"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw EncryptionError.rewrapFailed
        }

        let decoder = JSONDecoder()
        return try decoder.decode(RewrapResponse.self, from: data)
    }

    /// Toggle encryption on/off
    func toggleEncryption() {
        encryptionEnabled.toggle()
        print("Encryption \(encryptionEnabled ? "enabled" : "disabled")")
    }

    /// Set encryption state
    func setEncryption(enabled: Bool) {
        encryptionEnabled = enabled
    }

    /// Clear all cached policies
    func clearPolicies() {
        groupPolicies.removeAll()
    }

    /// Update policy for a specific group
    func updatePolicy(for groupId: String, policy: Data) {
        groupPolicies[groupId] = policy
        print("Updated policy for group: \(groupId)")
    }

    /// Get all group IDs with policies
    var groupsWithPolicies: [String] {
        Array(groupPolicies.keys)
    }
}

// MARK: - Policy Models

struct GroupPolicy: Codable {
    let uuid: String
    let body: PolicyBody
    let created: Date

    struct PolicyBody: Codable {
        let dataAttributes: [String]
        let dissemination: [String]

        enum CodingKeys: String, CodingKey {
            case dataAttributes = "data_attributes"
            case dissemination = "dissem"
        }
    }

    init(groupId: String) {
        self.uuid = UUID().uuidString
        self.body = PolicyBody(
            dataAttributes: [],
            dissemination: ["group_\(groupId)"]
        )
        self.created = Date()
    }
}

// MARK: - Encryption Status

enum EncryptionStatus {
    case disabled
    case encrypting
    case encrypted
    case failed(String)

    var description: String {
        switch self {
        case .disabled:
            return "Encryption disabled"
        case .encrypting:
            return "Encrypting..."
        case .encrypted:
            return "Encrypted"
        case .failed(let error):
            return "Encryption failed: \(error)"
        }
    }

    var icon: String {
        switch self {
        case .disabled:
            return "lock.open"
        case .encrypting:
            return "lock.rotation"
        case .encrypted:
            return "lock.shield.fill"
        case .failed:
            return "lock.trianglebadge.exclamationmark"
        }
    }
}

// MARK: - Encryption Errors

enum EncryptionError: Error, LocalizedError {
    case missingKASURL
    case rewrapFailed
    case decryptionFailed
    case invalidNanoTDF

    var errorDescription: String? {
        switch self {
        case .missingKASURL:
            return "KAS URL not configured"
        case .rewrapFailed:
            return "Failed to rewrap key with KAS"
        case .decryptionFailed:
            return "Failed to decrypt message"
        case .invalidNanoTDF:
            return "Invalid NanoTDF format"
        }
    }
}

// MARK: - Rewrap Models

struct RewrapRequest: Codable {
    let ephemeralPublicKey: String
    let policy: String
    let kasURL: String

    enum CodingKeys: String, CodingKey {
        case ephemeralPublicKey = "ephemeral_public_key"
        case policy
        case kasURL = "kas_url"
    }
}

struct RewrapResponse: Codable {
    let symmetricKey: Data
    let policyUUID: String

    enum CodingKeys: String, CodingKey {
        case symmetricKey = "symmetric_key"
        case policyUUID = "policy_uuid"
    }
}
