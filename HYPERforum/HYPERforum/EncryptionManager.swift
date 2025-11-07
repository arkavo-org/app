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
    func getPolicy(for groupId: String) -> Data {
        // Check if we already have a policy for this group
        if let existingPolicy = groupPolicies[groupId] {
            return existingPolicy
        }

        // Create a new policy for the group
        let policy = createGroupPolicy(groupId: groupId)
        groupPolicies[groupId] = policy
        return policy
    }

    /// Create a policy for a group
    private func createGroupPolicy(groupId: String) -> Data {
        // Create a simple embedded policy
        // In production, this would include access control lists, attributes, etc.
        let policyJSON: [String: Any] = [
            "uuid": UUID().uuidString,
            "body": [
                "dataAttributes": [],
                "dissem": ["group_\(groupId)"]
            ]
        ]

        do {
            return try JSONSerialization.data(withJSONObject: policyJSON)
        } catch {
            print("Error creating policy: \(error)")
            // Return minimal valid policy
            return Data("{}".utf8)
        }
    }

    /// Encrypt a message payload
    func encryptMessage(_ message: Data, groupId: String) async throws -> Data {
        isEncrypting = true
        encryptionError = nil

        defer {
            isEncrypting = false
        }

        do {
            let policyData = getPolicy(for: groupId)

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
        // Parse NanoTDF header to get rewrapped key information
        // This would use OpenTDFKit to parse the NanoTDF structure

        do {
            // For now, we'll assume the server handles decryption via rewrap
            // In a full implementation, this would:
            // 1. Parse NanoTDF header
            // 2. Extract ephemeral public key and policy
            // 3. Send rewrap request to KAS
            // 4. Decrypt payload with rewrapped key

            print("Decrypting message: \(encryptedData.count) bytes")

            // Placeholder: In real implementation, parse and decrypt
            // For now, return as-is (server-side decryption)
            return encryptedData
        } catch {
            print("Decryption error: \(error)")
            throw error
        }
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
