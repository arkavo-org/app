import ArkavoSocial
import AuthenticationServices
import SwiftUI

struct ConnectedAccountsView: View {
    @StateObject private var appleSignInService = AppleSignInService()
    @StateObject private var membershipStore = PatreonMembershipStore()
    @State private var isPatreonLinked = KeychainManager.isPatreonAccountLinked()
    @State private var showingAppleDisconnectAlert = false
    @State private var showingPatreonDisconnectAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var isPatreonConnecting = false
    @State private var showingMemberships = false

    var body: some View {
        List {
            Section {
                appleAccountRow
                patreonAccountRow
            } header: {
                Text("Linked Accounts")
            } footer: {
                Text("Link accounts to enhance your profile. Your primary authentication remains via passkey.")
            }

            if isPatreonLinked {
                Section {
                    Button {
                        showingMemberships = true
                    } label: {
                        HStack {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.orange)
                                    .frame(width: 32)

                                if membershipStore.hasUnreadContent {
                                    UnreadDot()
                                        .offset(x: 4, y: -4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text("Supported Creators")
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    if membershipStore.hasUnreadContent {
                                        Text("\(membershipStore.totalUnreadCount) new")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.red)
                                            .cornerRadius(10)
                                    }
                                }

                                Text("View exclusive member content")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Access exclusive posts and content from creators you support on Patreon.")
                }
            }
        }
        .navigationTitle("Connected Accounts")
        .sheet(isPresented: $showingMemberships) {
            NavigationStack {
                PatreonMembershipsView()
            }
        }
        .alert("Disconnect Apple Account", isPresented: $showingAppleDisconnectAlert) {
            Button("Cancel", role: .cancel) { /* Dismisses alert */ }
            Button("Disconnect", role: .destructive) {
                disconnectApple()
            }
        } message: {
            Text("Are you sure you want to disconnect your Apple account? You can reconnect it later.")
        }
        .alert("Disconnect Patreon", isPresented: $showingPatreonDisconnectAlert) {
            Button("Cancel", role: .cancel) { /* Dismisses alert */ }
            Button("Disconnect", role: .destructive) {
                disconnectPatreon()
            }
        } message: {
            Text("Are you sure you want to disconnect your Patreon account?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { /* Dismisses alert */ }
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task {
            await appleSignInService.verifyCredentialState()
        }
        .task {
            if isPatreonLinked {
                await membershipStore.loadMembershipsWithUnread()
            }
        }
    }

    private var appleAccountRow: some View {
        HStack {
            Image(systemName: "apple.logo")
                .font(.title2)
                .foregroundStyle(.primary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple")
                    .font(.body)
                if appleSignInService.isLinked {
                    if let name = appleSignInService.linkedName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let email = appleSignInService.linkedEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if appleSignInService.isProcessing {
                ProgressView()
            } else if appleSignInService.isLinked {
                Button("Disconnect") {
                    showingAppleDisconnectAlert = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Connect") {
                    connectApple()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private var patreonAccountRow: some View {
        HStack {
            Image(systemName: "heart.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Patreon")
                    .font(.body)
                if isPatreonLinked {
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Not connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isPatreonConnecting {
                ProgressView()
            } else if isPatreonLinked {
                Button("Disconnect") {
                    showingPatreonDisconnectAlert = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Connect") {
                    connectPatreon()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func connectApple() {
        Task {
            do {
                try await appleSignInService.linkAppleAccount()
            } catch let error as AppleSignInError {
                if case .userCancelled = error {
                    return
                }
                errorMessage = error.localizedDescription
                showingError = true
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }

    private func disconnectApple() {
        appleSignInService.unlinkAppleAccount()
    }

    private func disconnectPatreon() {
        KeychainManager.deleteTokens()
        isPatreonLinked = false
    }

    private func connectPatreon() {
        isPatreonConnecting = true

        // Build Patreon OAuth URL
        // Uses "arkavo" client scheme for consumer app (vs "arkavocreator" for creator app)
        let redirectURI = ArkavoConfiguration.shared.oauthRedirectURL(for: "patreon", client: "arkavo")
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.patreon.com"
        components.path = "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Secrets.patreonClientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "identity identity.memberships"),
            URLQueryItem(name: "state", value: UUID().uuidString),
        ]

        guard let authURL = components.url else {
            isPatreonConnecting = false
            errorMessage = "Failed to build Patreon OAuth URL"
            showingError = true
            return
        }

        // Start ASWebAuthenticationSession
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "arkavo"
        ) { callbackURL, error in
            Task { @MainActor in
                isPatreonConnecting = false

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin
                {
                    // User cancelled, no error needed
                    return
                }

                if let error {
                    errorMessage = error.localizedDescription
                    showingError = true
                    return
                }

                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    // Check for error in callback
                    if let errorParam = URLComponents(url: callbackURL ?? URL(string: "arkavo://")!, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "error" })?.value
                    {
                        errorMessage = "Patreon OAuth failed: \(errorParam)"
                    } else {
                        errorMessage = "No authorization code received"
                    }
                    showingError = true
                    return
                }

                // Exchange code for tokens via backend
                await linkPatreonWithCode(code)
            }
        }

        // Configure and start session
        #if os(iOS)
            session.prefersEphemeralWebBrowserSession = false
        #endif
        session.start()
    }

    private func linkPatreonWithCode(_ code: String) async {
        do {
            // Call ArkavoClient to exchange code and link account
            try await ArkavoClient.linkPatreonAccount(authorizationCode: code)
            isPatreonLinked = true
        } catch {
            errorMessage = "Failed to link Patreon: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// Note: Notification.Name.patreonOAuthCallback is defined in ArkavoApp.swift

#Preview {
    NavigationStack {
        ConnectedAccountsView()
    }
}
