import ArkavoAgent
import ArkavoSocial
import OSLog
import SwiftUI

extension AgentAuthorizationRequest {
    /// Display-friendly short DID (first and last 8 chars)
    var shortDID: String {
        guard did.count > 24 else { return did }
        let prefix = did.prefix(20)
        let suffix = did.suffix(8)
        return "\(prefix)...\(suffix)"
    }
}

/// View for authorizing an agent from QR code scan
struct AgentAuthorizationView: View {
    let request: AgentAuthorizationRequest
    let onAuthorize: () -> Void
    let onCancel: () -> Void
    var identity: any AgentAuthorizing = ArkavoIdentityClient()

    @State private var isAuthorizing = false
    @State private var error: String?
    @StateObject private var contactService = UnifiedContactService()
    @EnvironmentObject var agentService: AgentService

    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "AgentAuth")

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Agent icon
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .padding(.top, 32)

                // Title
                Text("Authorize Agent")
                    .font(.title)
                    .fontWeight(.bold)

                // Agent details card
                VStack(alignment: .leading, spacing: 16) {
                    if let name = request.name {
                        HStack {
                            Text("Name")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(name)
                                .fontWeight(.medium)
                        }
                    }

                    HStack {
                        Text("DID")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(request.shortDID)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                    }

                    if !request.entitlements.isEmpty {
                        Divider()

                        Text("Requested Capabilities")
                            .foregroundStyle(.secondary)

                        ForEach(request.entitlements, id: \.self) { entitlement in
                            HStack {
                                Image(systemName: iconForEntitlement(entitlement))
                                    .foregroundStyle(.blue)
                                Text(displayNameForEntitlement(entitlement))
                            }
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)

                // Warning text
                Text("This will allow the agent to interact with Arkavo services on your behalf.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                // Error message
                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: authorize) {
                        HStack {
                            if isAuthorizing {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isAuthorizing ? "Authorizing..." : "Authorize Agent")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isAuthorizing)

                    Button("Cancel", action: onCancel)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func authorize() {
        isAuthorizing = true
        error = nil

        // Extract values for sendability
        let agentDID = request.did
        let agentName = request.name ?? "Authorized Agent"
        let rpcEndpoint = request.rpcEndpoint
        // A missing device DID can't abort cloud authorization -- it only
        // matters for the best-effort local RPC pairing step below, which is
        // never allowed to fail the whole flow.
        let deviceDID = (try? KeychainManager.getDIDKey().did) ?? ""

        logger.log("[AgentAuth] Authorizing agent: \(agentDID)")

        Task {
            do {
                // Cloud authorization always happens first and is mandatory;
                // local RPC pairing (if the QR code advertised an endpoint)
                // is attempted afterwards on a best-effort basis.
                let flow = AgentAuthorizationFlow(identity: identity, transportFactory: AgentAuthorizationFlow.defaultTransportFactory)
                let result = try await flow.run(request: request, deviceDID: deviceDID)

                switch result.rpcOutcome {
                case .succeeded:
                    logger.log("[AgentAuth] Agent paired via local RPC")
                case .skipped:
                    logger.log("[AgentAuth] Agent authorized via cloud (no RPC endpoint)")
                case .failed(let message):
                    logger.warning("[AgentAuth] Local RPC pairing failed after cloud authorization; delegation stands: \(message)")
                }

                // Configure contact service if needed
                contactService.configure(agentService: agentService)

                // Create a Profile contact for this delegated agent
                // Pass the RPC endpoint so we can connect directly later
                let entitlements = AgentEntitlements(from: result.canonicalEntitlements)
                try await contactService.addDelegatedAgent(
                    agentID: agentDID, // Use DID as agent ID for delegated agents
                    name: agentName,
                    did: agentDID,
                    endpoint: rpcEndpoint, // Store endpoint for future connections
                    entitlements: entitlements
                )
                logger.log("[AgentAuth] Created contact for delegated agent with endpoint: \(rpcEndpoint ?? "none")")

                await MainActor.run {
                    isAuthorizing = false
                    onAuthorize()
                }
            } catch {
                logger.error("[AgentAuth] Authorization failed: \(String(describing: error))")
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isAuthorizing = false
                }
            }
        }
    }

    private func iconForEntitlement(_ entitlement: String) -> String {
        if entitlement.contains("chat") {
            return "bubble.left.and.bubble.right"
        } else if entitlement.contains("tools") {
            return "wrench.and.screwdriver"
        } else if entitlement.contains("read") {
            return "eye"
        } else if entitlement.contains("write") {
            return "pencil"
        } else {
            return "checkmark.circle"
        }
    }

    private func displayNameForEntitlement(_ entitlement: String) -> String {
        // Convert "agent.capability.chat" to "Chat"
        let parts = entitlement.split(separator: ".")
        if let last = parts.last {
            return String(last).capitalized
        }
        return entitlement
    }
}

#Preview {
    AgentAuthorizationView(
        request: AgentAuthorizationRequest(
            did: "did:key:z6MkhaXgBZDvotDkL5257faiztiGiC2QtKLGpbnnEGta2doK",
            name: "arkavo-edge-macbook",
            entitlements: ["agent.capability.chat", "agent.capability.tools"]
        ),
        onAuthorize: { print("Authorized") },
        onCancel: { print("Cancelled") }
    )
    .environmentObject(AgentService())
}
