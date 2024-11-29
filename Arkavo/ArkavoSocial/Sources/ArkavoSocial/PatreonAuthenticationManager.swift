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

// MARK: - Auth ViewModel

@MainActor
public class PatreonAuthViewModel: ObservableObject {
    @Published public var isAuthenticated = false
    @Published public var isLoading = false
    @Published public var error: Error?
    private let client: PatreonClient
    private var authSession: ASWebAuthenticationSession?
    private let config: PatreonConfig
    private let contextProvider = AuthenticationContextProvider()

    public init(client: PatreonClient, config: PatreonConfig) {
        self.client = client
        self.config = config
        checkExistingAuth()
    }

    private func checkExistingAuth() {
        if KeychainManager.getAccessToken() != nil {
            isAuthenticated = true
        }
    }

    public func startOAuthFlow() {
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

    public func logout() {
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
