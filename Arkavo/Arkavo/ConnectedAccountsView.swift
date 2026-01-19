import ArkavoSocial
import SwiftUI

struct ConnectedAccountsView: View {
    @StateObject private var appleSignInService = AppleSignInService()
    @State private var isPatreonLinked = KeychainManager.isPatreonAccountLinked()
    @State private var showingAppleDisconnectAlert = false
    @State private var showingPatreonDisconnectAlert = false
    @State private var errorMessage: String?
    @State private var showingError = false

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
        }
        .navigationTitle("Connected Accounts")
        .alert("Disconnect Apple Account", isPresented: $showingAppleDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                disconnectApple()
            }
        } message: {
            Text("Are you sure you want to disconnect your Apple account? You can reconnect it later.")
        }
        .alert("Disconnect Patreon", isPresented: $showingPatreonDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                disconnectPatreon()
            }
        } message: {
            Text("Are you sure you want to disconnect your Patreon account?")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .task {
            await appleSignInService.verifyCredentialState()
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

            if isPatreonLinked {
                Button("Disconnect") {
                    showingPatreonDisconnectAlert = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
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
}

// Note: Notification.Name.patreonOAuthCallback is defined in ArkavoApp.swift

#Preview {
    NavigationStack {
        ConnectedAccountsView()
    }
}
