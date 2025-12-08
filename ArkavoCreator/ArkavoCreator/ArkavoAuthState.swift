import ArkavoKit
import SwiftUI

/// Shared authentication state for Arkavo across the app
@MainActor
@Observable
final class ArkavoAuthState {
    static let shared = ArkavoAuthState()

    private(set) var isAuthenticated: Bool = false
    private(set) var isLoading: Bool = false
    var accountName: String = ""
    private(set) var errorMessage: String?

    var showingLoginSheet: Bool = false

    private var client: ArkavoClient {
        ViewModelFactory.shared.serviceLocator.resolve() as ArkavoClient
    }

    private init() {
        // Use shared Arkavo handle (from Arkavo app registration) first, then fall back to local handle
        if let handle = KeychainManager.getArkavoHandle() ?? KeychainManager.getHandle() {
            accountName = handle
        }
    }

    /// Check stored credentials and attempt auto-login
    func checkStoredCredentials() async {
        guard KeychainManager.getAuthenticationToken() != nil else {
            print("[ArkavoAuthState] No stored token found")
            return
        }

        // Check for handle: shared Arkavo handle first, then UserDefaults
        let storedName = KeychainManager.getArkavoHandle()
            ?? UserDefaults.standard.string(forKey: "arkavo_account_name")

        guard let storedName else {
            print("[ArkavoAuthState] No stored account name found")
            return
        }

        print("[ArkavoAuthState] Found stored credentials for: \(storedName)")
        isLoading = true
        errorMessage = nil

        do {
            try await client.connect(accountName: storedName)
            isAuthenticated = true
            accountName = storedName
            print("[ArkavoAuthState] Auto-login successful")
        } catch {
            print("[ArkavoAuthState] Auto-login failed: \(error)")
            // Clear invalid credentials
            KeychainManager.deleteAuthenticationToken()
            UserDefaults.standard.removeObject(forKey: "arkavo_account_name")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Login with the specified account name
    func login(accountName: String) async {
        guard !accountName.isEmpty else { return }

        print("[ArkavoAuthState] Starting login for: \(accountName)")
        isLoading = true
        errorMessage = nil

        do {
            try await client.connect(accountName: accountName)
            self.accountName = accountName
            isAuthenticated = true
            showingLoginSheet = false

            // Save for future sessions
            UserDefaults.standard.set(accountName, forKey: "arkavo_account_name")
            print("[ArkavoAuthState] Login successful")
        } catch {
            print("[ArkavoAuthState] Login failed: \(error)")
            errorMessage = "Login failed. Please try again."
        }

        isLoading = false
    }

    /// Register a new account with passkey on this device
    func register(accountName: String) async {
        guard !accountName.isEmpty else {
            print("[ArkavoAuthState] Registration attempted with empty account name")
            return
        }

        print("[ArkavoAuthState] Starting registration for: \(accountName)")
        isLoading = true
        errorMessage = nil

        do {
            // Generate DID using Secure Enclave (or get existing one)
            let did = try client.generateDID()
            print("[ArkavoAuthState] Generated/retrieved DID: \(did)")

            // Register with the server
            print("[ArkavoAuthState] Registering with server...")
            let token = try await client.registerUser(handle: accountName, did: did)

            // Save the token
            try KeychainManager.saveAuthenticationToken(token)
            print("[ArkavoAuthState] Registration successful, token saved")

            // Save credentials to shared keychain for other Arkavo apps
            try KeychainManager.saveArkavoCredentials(handle: accountName, did: did)
            print("[ArkavoAuthState] Saved credentials to shared keychain")

            // Now connect with the new passkey
            try await client.connect(accountName: accountName)
            self.accountName = accountName
            isAuthenticated = true
            showingLoginSheet = false

            // Save for future sessions
            UserDefaults.standard.set(accountName, forKey: "arkavo_account_name")
            print("[ArkavoAuthState] Connected successfully")
        } catch {
            print("[ArkavoAuthState] Registration failed: \(error)")
            errorMessage = "Registration failed: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Logout and clear credentials
    func logout() async {
        print("[ArkavoAuthState] Logging out")
        await client.disconnect()

        KeychainManager.deleteAuthenticationToken()
        UserDefaults.standard.removeObject(forKey: "arkavo_account_name")

        isAuthenticated = false
        accountName = ""
        print("[ArkavoAuthState] Logout complete")
    }
}

/// Reusable Arkavo login sheet view
struct ArkavoLoginSheet: View {
    @Bindable var authState: ArkavoAuthState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Login to Arkavo")
                .font(.title2)
                .bold()

            Text("Enter your account name to continue")
                .foregroundColor(.secondary)

            TextField("Account Name", text: $authState.accountName)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 300)
                .disabled(authState.isLoading)

            HStack(spacing: 16) {
                Button("Cancel") {
                    authState.showingLoginSheet = false
                }
                .buttonStyle(.plain)
                .disabled(authState.isLoading)

                Button {
                    Task {
                        await authState.login(accountName: authState.accountName)
                    }
                } label: {
                    if authState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(authState.accountName.isEmpty || authState.isLoading)
            }

            if let errorMessage = authState.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Divider()
                .padding(.vertical, 8)

            Text("New to Arkavo?")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                Task {
                    await authState.register(accountName: authState.accountName)
                }
            } label: {
                if authState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Create Account")
                }
            }
            .buttonStyle(.bordered)
            .disabled(authState.accountName.isEmpty || authState.isLoading)
        }
        .padding()
        .frame(width: 400)
    }
}
