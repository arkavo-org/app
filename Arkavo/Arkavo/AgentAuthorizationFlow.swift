import ArkavoAgent
import ArkavoSocial
import Foundation

/// Seam so the cloud call to `ArkavoIdentityClient` can be swapped for a mock
/// in tests.
protocol AgentAuthorizing: Sendable {
    func authorizeAgent(did: String, name: String, entitlements: [String]) async throws
}

extension ArkavoIdentityClient: AgentAuthorizing {}

/// Errors specific to running the authorization flow itself, as opposed to
/// errors surfaced by the identity server or the local RPC transport.
enum AgentAuthorizationFlowError: LocalizedError, Equatable {
    /// None of the QR code's requested entitlements canonicalize to a
    /// delegable attribute value. There is nothing to delegate, so the flow
    /// refuses before making any network call.
    case noDelegableEntitlements

    var errorDescription: String? {
        switch self {
        case .noDelegableEntitlements:
            return "This agent didn't request any recognized capabilities, so there is nothing to authorize."
        }
    }
}

/// Outcome of the best-effort local RPC pairing step that follows a
/// successful cloud authorization.
enum AgentRPCPairingOutcome: Equatable {
    /// The request carried no `rpcEndpoint`; local pairing was not attempted.
    case skipped
    /// Local RPC pairing succeeded.
    case succeeded
    /// Local RPC pairing failed. The cloud delegation still stands -- this is
    /// a warning, not a rollback -- and the message is
    /// `error.localizedDescription` from whatever failed.
    case failed(String)
}

/// The result of a successful `AgentAuthorizationFlow.run`.
struct AgentAuthorizationResult: Equatable {
    /// The entitlements actually sent to (and accepted by) the identity
    /// server, after canonicalization. Callers should record delegated
    /// entitlements using this list, not the raw QR code strings.
    let canonicalEntitlements: [String]
    let rpcOutcome: AgentRPCPairingOutcome
}

/// Runs agent authorization: cloud delegation first, local RPC pairing
/// second and best-effort.
///
/// Order matters. A cloud authorization failure aborts the whole flow -- an
/// agent is never paired locally without a delegation at the identity
/// server. Once the delegation exists, a local RPC pairing failure is
/// reported back as a warning: the delegation stands and the user can
/// re-pair later.
struct AgentAuthorizationFlow {
    let identity: any AgentAuthorizing
    let transportFactory: (AgentEndpoint) async throws -> any AgentTransportProtocol

    /// - Parameter transportFactory: Builds (and connects) the transport used for
    ///   local RPC pairing. Callers outside tests should pass
    ///   `AgentAuthorizationFlow.defaultTransportFactory`.
    init(
        identity: any AgentAuthorizing,
        transportFactory: @escaping (AgentEndpoint) async throws -> any AgentTransportProtocol
    ) {
        self.identity = identity
        self.transportFactory = transportFactory
    }

    /// Connects a real `AgentWebSocketTransport` to `endpoint`. The production
    /// transport factory for `init`; kept out of a default parameter value
    /// because a default-value closure that constructs an actor trips Swift's
    /// "actor-isolated default value in a nonisolated context" check.
    static func defaultTransportFactory(_ endpoint: AgentEndpoint) async throws -> any AgentTransportProtocol {
        let transport = AgentWebSocketTransport()
        try await transport.connect(to: endpoint)
        return transport
    }

    @discardableResult
    func run(request: AgentAuthorizationRequest, deviceDID: String) async throws -> AgentAuthorizationResult {
        let canonicalEntitlements = AgentEntitlementCanonicalizer.canonicalize(request.entitlements)
        guard !canonicalEntitlements.isEmpty else {
            throw AgentAuthorizationFlowError.noDelegableEntitlements
        }

        let name = request.name ?? "Authorized Agent"

        // Cloud first. A failure here aborts the whole flow -- there is no
        // local pairing without a delegation.
        try await identity.authorizeAgent(did: request.did, name: name, entitlements: canonicalEntitlements)

        guard let rpcEndpoint = request.rpcEndpoint else {
            return AgentAuthorizationResult(canonicalEntitlements: canonicalEntitlements, rpcOutcome: .skipped)
        }

        do {
            let endpoint = AgentEndpoint(
                id: request.did,
                url: rpcEndpoint,
                metadata: AgentMetadata(name: name, purpose: "", model: "")
            )
            let transport = try await transportFactory(endpoint)
            defer { Task { await transport.close() } }

            let registrationService = AgentRPCRegistrationService(transport: transport)
            guard try await registrationService.register(deviceId: deviceDID) else {
                throw RegistrationError.registrationFailed
            }
            return AgentAuthorizationResult(canonicalEntitlements: canonicalEntitlements, rpcOutcome: .succeeded)
        } catch {
            return AgentAuthorizationResult(canonicalEntitlements: canonicalEntitlements, rpcOutcome: .failed(error.localizedDescription))
        }
    }
}
