// RedditAuthManager.swift

import AuthenticationServices
import Foundation
import Security

class RedditAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let clientId = "5Yf5m-g6oyKSWjMZO1nCHQ"
    private let redirectUri = "arkavo://oath/callback"
    private let clientSecret = "" // not needed for this flow
    private let tokenKeychainKey = "com.arkavo.redditToken"
    private var authenticationSession: ASWebAuthenticationSession?
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
            else {
                fatalError("No window found in the current window scene")
            }
            return window
        #elseif os(macOS)
            guard let window = NSApplication.shared.windows.first
            else {
                fatalError("No window found in the application")
            }
            return window
        #else
            fatalError("Unsupported platform")
        #endif
    }
    
    func startOAuthFlow() async throws -> Bool {
        let state = UUID().uuidString
        let authURL = URL(string: "https://www.reddit.com/api/v1/authorize.compact")!
        
        var components = URLComponents(url: authURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "duration", value: "permanent"),
            URLQueryItem(name: "scope", value: "read identity")
        ]
        
        return try await withCheckedThrowingContinuation { continuation in
            authenticationSession = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: "arkavo"
            ) { [weak self] callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
                      let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                      returnedState == state
                else {
                    continuation.resume(throwing: NSError(domain: "RedditAuthError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL"]))
                    return
                }
                
                Task {
                    do {
                        try await self?.exchangeCodeForToken(code: code)
                        continuation.resume(returning: true)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            authenticationSession?.presentationContextProvider = self
            authenticationSession?.prefersEphemeralWebBrowserSession = true
            authenticationSession?.start()
        }
    }
    
    private func exchangeCodeForToken(code: String) async throws {
        let tokenURL = URL(string: "https://www.reddit.com/api/v1/access_token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        
        let credentials = "\(clientId):\(clientSecret)".data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri
        ]
        
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let token = try JSONDecoder().decode(RedditToken.self, from: data)
        try saveToken(token)
    }
    
    private func saveToken(_ token: RedditToken) throws {
        let tokenData = try JSONEncoder().encode(token)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecValueData as String: tokenData
        ]
        
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainError", code: Int(status))
        }
    }
    
    func getToken() throws -> RedditToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: tokenKeychainKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = try? JSONDecoder().decode(RedditToken.self, from: tokenData)
        else {
            return nil
        }
        
        return token
    }
}

// RedditToken.swift
struct RedditToken: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

// RedditScanner.swift
class RedditScanner {
    private let authManager: RedditAuthManager
    private let apiBaseURL = "https://oauth.reddit.com"
    
    init(authManager: RedditAuthManager) {
        self.authManager = authManager
    }
    
    func scanContent() async throws {
        guard let token = try await authManager.getToken() else {
            throw NSError(domain: "RedditScannerError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No valid token"])
        }
        
        var request = URLRequest(url: URL(string: "\(apiBaseURL)/hot")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Arkavo/1.0", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        print("data \(data)")
        // Process the response data
        // Implement content scanning logic here
    }
}
