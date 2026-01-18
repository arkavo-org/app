import Foundation

/// Represents a pending authorization request for a local agent scanned via QR or deep link.
/// Expected URL format: arkavo://agent/authorize?did=...&name=...&entitlements=scope1,scope2
public struct AgentAuthorizationRequest: Identifiable, Equatable {
    public let id: UUID
    public let did: String
    public let name: String?
    public let entitlements: [String]

    public init(id: UUID = UUID(), did: String, name: String?, entitlements: [String]) {
        self.id = id
        self.did = did
        self.name = name
        self.entitlements = entitlements
    }

    /// Builds an AgentAuthorizationRequest from URLComponents for paths like /authorize
    /// - Parameter components: The URLComponents from an incoming arkavo:// URL
    /// - Returns: A request if required fields are present; otherwise nil
    public static func from(components: URLComponents) -> AgentAuthorizationRequest? {
        // Validate host and path if provided by caller; be permissive here and only require DID
        let queryItems = components.queryItems ?? []
        guard let did = queryItems.first(where: { $0.name == "did" })?.value, !did.isEmpty else {
            return nil
        }
        let name = queryItems.first(where: { $0.name == "name" })?.value
        let entitlementsString = queryItems.first(where: { $0.name == "entitlements" })?.value ?? ""
        // Split by comma, trim whitespace, and remove empties
        let entitlements = entitlementsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return AgentAuthorizationRequest(did: did, name: name, entitlements: entitlements)
    }
}
