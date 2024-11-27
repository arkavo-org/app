import AuthenticationServices
import Security
import SwiftUI

// MARK: - Platform-specific type aliases and protocols

#if os(macOS)
    typealias ASPresentationAnchorProtocol = ASPresentationAnchor
#else
    typealias ASPresentationAnchorProtocol = UIWindow
#endif

// MARK: - Authentication Context Provider

class AuthenticationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    #if os(macOS)
        func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
            NSApp.keyWindow ?? ASPresentationAnchor()
        }
    #else
        func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
            guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
                let window = windowScene.windows.first(where: { $0.isKeyWindow })
            else {
                let window = UIWindow()
                window.makeKeyAndVisible()
                return window
            }
            return window
        }
    #endif
}

// MARK: - Auth Models

struct PatreonAuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case tokenType = "token_type"
    }
}

// MARK: - Keychain Manager

class KeychainManager {
    enum KeychainError: Error {
        case duplicateItem
        case unknown(OSStatus)
        case itemNotFound
    }

    static func save(_ data: Data, service: String, account: String) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecValueData as String: data as AnyObject,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let attributes: [String: AnyObject] = [
                kSecValueData as String: data as AnyObject,
            ]

            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unknown(status)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }

    static func load(service: String, account: String) throws -> Data {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
            kSecReturnData as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    static func delete(service: String, account: String) throws {
        let query: [String: AnyObject] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service as AnyObject,
            kSecAttrAccount as String: account as AnyObject,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }

    // MARK: - Token Management Convenience Methods

    static func getAccessToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "access_token")
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error retrieving access token:", error)
            return nil
        }
    }

    static func getRefreshToken() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "refresh_token")
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error retrieving refresh token:", error)
            return nil
        }
    }

    static func saveTokens(accessToken: String, refreshToken: String) throws {
        try save(accessToken.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "access_token")
        try save(refreshToken.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "refresh_token")
    }

    static func deleteTokens() {
        try? delete(service: "com.arkavo.patreon", account: "access_token")
        try? delete(service: "com.arkavo.patreon", account: "refresh_token")
        try? delete(service: "com.arkavo.patreon", account: "campaign_id")
    }
}

extension KeychainManager {
    static func saveCampaignId(_ campaignId: String) throws {
        try save(campaignId.data(using: .utf8)!,
                 service: "com.arkavo.patreon",
                 account: "campaign_id")
    }

    static func getCampaignId() -> String? {
        do {
            let data = try load(service: "com.arkavo.patreon", account: "campaign_id")
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error retrieving campaign ID:", error)
            return nil
        }
    }

    static func deleteTokensAndCampaignId() {
        try? delete(service: "com.arkavo.patreon", account: "access_token")
        try? delete(service: "com.arkavo.patreon", account: "refresh_token")
        try? delete(service: "com.arkavo.patreon", account: "campaign_id")
    }
}

// MARK: - Auth ViewModel

@MainActor
class PatreonAuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: Error?
    private let client: PatreonClient
    private var authSession: ASWebAuthenticationSession?
    private let config: PatreonConfig
    private let contextProvider = AuthenticationContextProvider()

    init(client: PatreonClient, config: PatreonConfig) {
        self.client = client
        self.config = config
        checkExistingAuth()
    }

    private func checkExistingAuth() {
        if KeychainManager.getAccessToken() != nil {
            isAuthenticated = true
        }
    }

    func startOAuthFlow() {
        isLoading = true
        error = nil
        let scopes = [
            "identity",
        ]
        let scopeString = scopes.joined(separator: "%20")

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.patreon.com"
        components.path = "/oauth2/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: PatreonClient.redirectURI),
            URLQueryItem(name: "scope", value: scopeString),
        ]

        guard let authURL = components.url else {
            error = PatreonError.invalidURL
            isLoading = false
            return
        }

        let callbackURLScheme = URL(string: PatreonClient.redirectURI)?.scheme ?? "arkavo"

        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackURLScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.error = error
                    self.isLoading = false
                }
                return
            }

            guard let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                  .queryItems?
                  .first(where: { $0.name == "code" })?
                  .value
            else {
                Task { @MainActor in
                    self.error = PatreonError.authorizationFailed
                    self.isLoading = false
                }
                return
            }

            Task {
                await self.exchangeCodeForTokens(code)
            }
        }

        authSession?.presentationContextProvider = contextProvider
        authSession?.prefersEphemeralWebBrowserSession = false
        authSession?.start()
    }

    private func exchangeCodeForTokens(_ code: String) async {
        do {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.patreon.com"
            components.path = "/api/oauth2/token"

            guard let url = components.url else {
                throw PatreonError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let params = [
                "code": code,
                "grant_type": "authorization_code",
                "client_id": config.clientId,
                "client_secret": config.clientSecret,
                "redirect_uri": PatreonClient.redirectURI,
            ]

            let body = params
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw PatreonError.networkError
            }

            guard httpResponse.statusCode == 200 else {
                throw PatreonError.tokenExchangeFailed
            }

            let token = try JSONDecoder().decode(PatreonAuthResponse.self, from: data)

            try KeychainManager.saveTokens(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken
            )

            isAuthenticated = true
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    func logout() {
        KeychainManager.deleteTokens()
        isAuthenticated = false
        // Verify tokens are actually deleted
        if KeychainManager.getAccessToken() != nil || KeychainManager.getRefreshToken() != nil {
            print("Warning: Tokens were not properly deleted during logout")
        }
        // Reset authentication state
        isAuthenticated = false
        error = nil
        // Cancel any pending auth session
        authSession?.cancel()
        authSession = nil
    }
}

// MARK: - Auth View

struct PatreonAuthView: View {
    @StateObject var viewModel: PatreonAuthViewModel

    var body: some View {
        VStack(spacing: 20) {
            if viewModel.isAuthenticated {
                Text("Authenticated!")
                    .font(.headline)
                Button("Logout") {
                    viewModel.logout()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Please login to continue")
                    .font(.headline)
                Button("Login with Patreon") {
                    viewModel.startOAuthFlow()
                }
                .buttonStyle(.borderedProminent)
            }

            if viewModel.isLoading {
                ProgressView()
            }

            if let error = viewModel.error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: 300)
        .padding()
        #if os(macOS)
            .frame(height: 200)
        #endif
    }
}
