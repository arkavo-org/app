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

    @State private var isAuthorizing = false
    @State private var error: String?

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
        let authRequest = request // Copy for sendability
        logger.log("[AgentAuth] Authorizing agent: \(authRequest.did)")

        Task {
            do {
                try await AgentAuthorizationService.shared.authorizeAgent(authRequest)
                logger.log("[AgentAuth] Agent authorized successfully")
                await MainActor.run {
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

/// Service for authorizing agents via the authnz-rs API
actor AgentAuthorizationService {
    static let shared = AgentAuthorizationService()

    private let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "AgentAuthService")
    private let baseURL = URL(string: "https://100.arkavo.net")!

    private init() {}

    /// Authorize an agent by registering it with the authnz-rs service
    func authorizeAgent(_ request: AgentAuthorizationRequest) async throws {
        logger.log("[AgentAuthService] Authorizing agent DID: \(request.did)")

        let url = baseURL.appendingPathComponent("agents/authorize")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Get auth token if available
        if let token = KeychainManager.getAuthenticationToken() {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "did": request.did,
            "name": request.name ?? "Unknown Agent",
            "entitlements": request.entitlements
        ]

        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentAuthorizationError.invalidResponse
        }

        logger.log("[AgentAuthService] Response status: \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200, 201:
            logger.log("[AgentAuthService] Agent authorized successfully")
            return
        case 401:
            throw AgentAuthorizationError.unauthorized
        case 409:
            // Agent already authorized - treat as success
            logger.log("[AgentAuthService] Agent already authorized")
            return
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AgentAuthorizationError.serverError(httpResponse.statusCode, message)
        }
    }
}

enum AgentAuthorizationError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Please sign in to authorize agents"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        }
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
}
