import ArkavoKit
import SwiftUI

/// Shared authentication state for Arkavo across the app
@MainActor
@Observable
final class ArkavoAuthState {
    static let shared = ArkavoAuthState()

    private(set) var isAuthenticated: Bool = false
    private(set) var isLoading: Bool = false
    private(set) var accountName: String = ""
    private(set) var errorMessage: String?

    var showingLoginSheet: Bool = false

    private var client: ArkavoClient {
        ViewModelFactory.shared.serviceLocator.resolve() as ArkavoClient
    }

    private init() {
        // Check if we have stored credentials on init
        if let handle = KeychainManager.getHandle() {
            accountName = handle
        }
    }

    /// Check stored credentials and attempt auto-login
    func checkStoredCredentials() async {
        guard let token = KeychainManager.getAuthenticationToken(),
              let storedName = UserDefaults.standard.string(forKey: "arkavo_account_name")
        else {
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
