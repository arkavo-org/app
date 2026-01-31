import Foundation

/// Represents a pending authorization request for a local agent scanned via QR or deep link.
/// Expected URL format: arkavo://agent/authorize?did=...&name=...&entitlements=scope1,scope2&rpc=ws://host:port
public struct AgentAuthorizationRequest: Identifiable, Equatable {
    public let id: UUID
    public let did: String
    public let name: String?
    public let entitlements: [String]
    public let rpcEndpoint: String?

    public init(id: UUID = UUID(), did: String, name: String?, entitlements: [String], rpcEndpoint: String? = nil) {
        self.id = id
        self.did = did
        self.name = name
        self.entitlements = entitlements
        self.rpcEndpoint = rpcEndpoint
    }

    /// Validates that a DID string conforms to the expected format.
    /// A valid DID starts with "did:" and has at least 3 colon-separated parts (did:method:identifier).
    /// - Parameter did: The DID string to validate
    /// - Returns: true if the DID format is valid
    public static func isValidDID(_ did: String) -> Bool {
        guard did.hasPrefix("did:") else { return false }
        let parts = did.split(separator: ":")
        // Minimum: did:method:identifier (3 parts)
        return parts.count >= 3
    }

    /// Builds an AgentAuthorizationRequest from URLComponents for paths like /authorize
    /// - Parameter components: The URLComponents from an incoming arkavo:// URL
    /// - Returns: A request if required fields are present and valid; otherwise nil
    public static func from(components: URLComponents) -> AgentAuthorizationRequest? {
        let queryItems = components.queryItems ?? []
        guard let did = queryItems.first(where: { $0.name == "did" })?.value,
              !did.isEmpty,
              isValidDID(did) else {
            return nil
        }
        let name = queryItems.first(where: { $0.name == "name" })?.value
        let entitlementsString = queryItems.first(where: { $0.name == "entitlements" })?.value ?? ""
        // Split by comma, trim whitespace, and remove empties
        let entitlements = entitlementsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Parse optional RPC endpoint for local agent registration
        let rpcEndpoint = queryItems.first(where: { $0.name == "rpc" })?.value
        return AgentAuthorizationRequest(did: did, name: name, entitlements: entitlements, rpcEndpoint: rpcEndpoint)
    }
}
