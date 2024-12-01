import ArkavoSocial
import Foundation
import SwiftUI

class RedditClient: ObservableObject {
    @Published var isAuthenticated = false
    @Published var showingWebView = false
    @Published var username = ""

    private let clientId = Secrets.redditClientId
    private let redirectUri = "arkavocreator://oauth/reddit"
    private var accessToken: String?

    var authURL: URL {
        var components = URLComponents(string: "https://www.reddit.com/api/v1/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: UUID().uuidString),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "duration", value: "permanent"),
            URLQueryItem(name: "scope", value: "identity read"),
        ]
        return components.url!
    }

    func startOAuth() {
        print("authManager.authURL = \(authURL)")
        showingWebView = true
    }

    func handleCallback(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            return
        }
        print("Reddit code received: \(code)")
        exchangeCodeForToken(code)
        showingWebView = false
    }

    private func exchangeCodeForToken(_ code: String) {
        let tokenURL = URL(string: "https://www.reddit.com/api/v1/access_token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"

        let authString = "\(clientId):" // Note the colon at the end
        let authData = authString.data(using: .utf8)!.base64EncodedString()
        request.setValue("Basic \(authData)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let parameters = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
        ]

        let formBody = parameters.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }.joined(separator: "&")

        request.httpBody = formBody.data(using: .utf8)
        // Debug prints
        print("Token exchange request:")
        print("URL: \(tokenURL)")
        print("Auth header: Basic \(authData)")
        print("Body: \(formBody)")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error {
                print("Network error: \(error.localizedDescription)")
                return
            }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let refreshToken = json["refresh_token"] as? String
            else {
                if let data, let errorString = String(data: data, encoding: .utf8) {
                    print("Token exchange error: \(errorString)")
                }
                return
            }

            // Save tokens to Keychain
//            try? KeychainManager.saveTokens(accessToken: accessToken, refreshToken: refreshToken)

            DispatchQueue.main.async {
                self?.accessToken = accessToken
                self?.isAuthenticated = true
                self?.fetchUsername()
            }
        }.resume()
    }

    func logout() {
//        KeychainManager.delete(service: "com.arkavo.reddit", account: "access_token")
//        KeychainManager.delete(service: "com.arkavo.reddit", account: "refresh_token")

        accessToken = nil
        isAuthenticated = false
        username = ""
    }

    private func fetchUsername() {
        guard let accessToken else { return }

        let url = URL(string: "https://oauth.reddit.com/api/v1/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let username = json["name"] as? String
            else {
                return
            }

            DispatchQueue.main.async {
                self?.username = username
            }
        }.resume()
    }
}

// WebView.swift
import SwiftUI
@preconcurrency import WebKit

struct WebView: NSViewRepresentable {
    let url: URL
    let callbackHandler: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context _: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url,
               url.scheme == "arkavocreator"
            {
                parent.callbackHandler(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
