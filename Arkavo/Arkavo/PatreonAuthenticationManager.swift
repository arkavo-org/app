import AuthenticationServices
import Security
import SwiftUI

class AuthenticationWindowController: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? ASPresentationAnchor()
    }
}

@MainActor
class PatreonAuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: Error?
    private let client: PatreonClient
    private var authSession: ASWebAuthenticationSession?
    private let config: PatreonConfig
    private let windowController = AuthenticationWindowController()

    init(client: PatreonClient, config: PatreonConfig) {
        self.client = client
        self.config = config
        checkExistingAuth()
    }

    private func checkExistingAuth() {
        // Check keychain for existing tokens
        if KeychainManager.getAccessToken() != nil {
            isAuthenticated = true
        }
    }

    func startOAuthFlow() {
        isLoading = true
        error = nil
        let scopes = [
            "identity",
//            "identity.memberships",
//            "identity[email]",
//            "campaigns",
//            "campaigns.members"
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
        print("authURL: \(authURL.absoluteString)")
        let callbackURLScheme = URL(string: PatreonClient.redirectURI)?.scheme ?? "arkavo"

        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackURLScheme
        ) { [weak self] callbackURL, error in
            guard let self else { return }
            print("Callback received - URL: \(String(describing: callbackURL))")
            print("Error if any: \(String(describing: error))")

            if let callbackURL {
                print("Query Items: \(String(describing: URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems))")
            }
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

        authSession?.presentationContextProvider = windowController
        authSession?.prefersEphemeralWebBrowserSession = false

        authSession?.start()
    }

    private func exchangeCodeForTokens(_ code: String) async {
        do {
            let token = try await client.exchangeCode(code)

            // Save tokens
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
    }
}

// MARK: - Auth ViewModel Extension

extension PatreonAuthViewModel {
    @MainActor
    var authURL: URL? {
        guard isLoading else { return nil }

        let scopes = [
            "identity",
            "identity.memberships",
            "identity[email]",
            "campaigns",
            "campaigns.members",
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

        return components.url
    }

    @MainActor
    func handleAuthCode(_ code: String) async {
        do {
            let token = try await client.exchangeCode(code)

            // Save tokens
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
            // Item already exists, update it
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
}

extension KeychainManager {
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
    }
}

// MARK: - Auth Manager

class PatreonAuthManager: ObservableObject {
    private let serviceIdentifier = "com.arkavo.Arkavo"
    private let clientId = ArkavoConfiguration.patreonClientId
    private let clientSecret = ArkavoConfiguration.patreonClientSecret
    @Published var isAuthenticated = false
    private var authSession: ASWebAuthenticationSession?

    init() {
        // Check for existing tokens on launch
        isAuthenticated = getAccessToken() != nil
    }

    func startOAuthFlow() {
        let scopes = ["identity", "identity[email]", "campaigns", "campaigns.members"]
        let scopeString = scopes.joined(separator: "%20")

        let urlString = "https://www.patreon.com/oauth2/authorize?" +
            "response_type=code&" +
            "client_id=\(clientId)&" +
            "redirect_uri=\(PatreonClient.redirectURI)&" +
            "scope=\(scopeString)"

        guard let url = URL(string: urlString) else { return }
        print("OAuth URL: %@", url)
        authSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "arkavor"
        ) { [weak self] callbackURL, error in
            guard let self,
                  let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                  .queryItems?
                  .first(where: { $0.name == "code" })?
                  .value
            else {
                print("OAuth error:", error?.localizedDescription ?? "Unknown error")
                return
            }

            exchangeCodeForTokens(code)
        }

        authSession?.presentationContextProvider = NSApplication.shared.keyWindow as? ASWebAuthenticationPresentationContextProviding
        authSession?.start()
    }

    private func exchangeCodeForTokens(_ code: String) {
        let url = URL(string: "https://www.patreon.com/api/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let params = [
            "code": code,
            "grant_type": "authorization_code",
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": PatreonClient.redirectURI,
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data,
                  let authResponse = try? JSONDecoder().decode(PatreonAuthResponse.self, from: data)
            else {
                print("Token exchange error:", error?.localizedDescription ?? "Unknown error")
                return
            }

            self?.saveTokens(authResponse)

            DispatchQueue.main.async {
                self?.isAuthenticated = true
            }
        }.resume()
    }

    // MARK: - Token Management

    private func saveTokens(_ auth: PatreonAuthResponse) {
        do {
            // Save access token
            let accessTokenData = auth.accessToken.data(using: .utf8)!
            try KeychainManager.save(accessTokenData,
                                     service: serviceIdentifier,
                                     account: "patreon_access_token")

            // Save refresh token
            let refreshTokenData = auth.refreshToken.data(using: .utf8)!
            try KeychainManager.save(refreshTokenData,
                                     service: serviceIdentifier,
                                     account: "patreon_refresh_token")

            // Save expiration date
            let expirationDate = Date().addingTimeInterval(TimeInterval(auth.expiresIn))
            UserDefaults.standard.set(expirationDate, forKey: "patreon_token_expiration")
        } catch {
            print("Error saving tokens:", error)
        }
    }

    func getAccessToken() -> String? {
        guard let expirationDate = UserDefaults.standard.object(forKey: "patreon_token_expiration") as? Date,
              expirationDate > Date()
        else {
            // Token expired, try to refresh
            refreshTokens()
            return nil
        }

        do {
            let data = try KeychainManager.load(service: serviceIdentifier,
                                                account: "patreon_access_token")
            return String(data: data, encoding: .utf8)
        } catch {
            print("Error retrieving access token:", error)
            return nil
        }
    }

    private func refreshTokens() {
        guard let refreshTokenData = try? KeychainManager.load(
            service: serviceIdentifier,
            account: "patreon_refresh_token"
        ),
            let refreshToken = String(data: refreshTokenData, encoding: .utf8)
        else { return }

        let url = URL(string: "https://www.patreon.com/api/oauth2/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data,
                  let authResponse = try? JSONDecoder().decode(PatreonAuthResponse.self, from: data)
            else {
                print("Token refresh error:", error?.localizedDescription ?? "Unknown error")
                DispatchQueue.main.async {
                    self?.isAuthenticated = false
                }
                return
            }

            self?.saveTokens(authResponse)
        }.resume()
    }

    func logout() {
        do {
            try KeychainManager.delete(service: serviceIdentifier,
                                       account: "patreon_access_token")
            try KeychainManager.delete(service: serviceIdentifier,
                                       account: "patreon_refresh_token")
            UserDefaults.standard.removeObject(forKey: "patreon_token_expiration")
            isAuthenticated = false
        } catch {
            print("Error logging out:", error)
        }
    }
}

// MARK: - Auth View

struct PatreonAuthView: View {
    @StateObject private var authManager = PatreonAuthManager()

    var body: some View {
        VStack(spacing: 20) {
            if authManager.isAuthenticated {
                Text("Authenticated!")
                    .font(.headline)
                Button("Logout") {
                    authManager.logout()
                }
            } else {
                Text("Please login to continue")
                    .font(.headline)
                Button("Login with Patreon") {
                    authManager.startOAuthFlow()
                }
            }
        }
        .frame(width: 300, height: 200)
    }
}

struct PatreonAuthView_Previews: PreviewProvider {
    static var previews: some View {
        PatreonAuthView()
    }
}
