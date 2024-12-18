import AuthenticationServices
import CryptoKit
import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// Main errors that can occur in ArkavoClient operations
enum ArkavoError: Error {
    case invalidURL
    case authenticationFailed(String)
    case connectionFailed(String)
    case invalidResponse
    case messageError(String)
    case notConnected
    case invalidState
}

/// Represents the current state of the ArkavoClient
enum ArkavoClientState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(Error)

    static func == (lhs: ArkavoClientState, rhs: ArkavoClientState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.authenticating, .authenticating),
             (.connected, .connected):
            true
        case let (.error(lhsError), .error(rhsError)):
            lhsError.localizedDescription == rhsError.localizedDescription
        default:
            false
        }
    }
}

/// Protocol for handling ArkavoClient events
protocol ArkavoClientDelegate: AnyObject {
    func clientDidChangeState(_ client: ArkavoClient, state: ArkavoClientState)
    func clientDidReceiveMessage(_ client: ArkavoClient, message: Data)
    func clientDidReceiveError(_ client: ArkavoClient, error: Error)
}

/// Main ArkavoClient class handling WebAuthn authentication and WebSocket communication
@MainActor
public final class ArkavoClient: NSObject {
    private let authURL: URL // for WebAuthn
    private let websocketURL: URL // for WebSocket
    private let relyingPartyID: String
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let delegateQueue = OperationQueue()
    private let socketDelegate: WebSocketDelegate
    private var connectionContinuation: CheckedContinuation<Void, Error>?

    private var currentState: ArkavoClientState = .disconnected {
        didSet {
            delegate?.clientDidChangeState(self, state: currentState)
        }
    }

    weak var delegate: ArkavoClientDelegate?
    private let presentationProvider: ASAuthorizationControllerPresentationContextProviding
    public var currentToken: String? {
        KeychainManager.getAuthenticationToken()
    }

    public init(authURL: URL, websocketURL: URL, relyingPartyID: String, presentationProvider: ASAuthorizationControllerPresentationContextProviding? = nil) {
        self.authURL = authURL
        self.websocketURL = websocketURL
        self.relyingPartyID = relyingPartyID
        socketDelegate = WebSocketDelegate()

        #if os(iOS)
            self.presentationProvider = presentationProvider ?? DefaultIOSPresentationProvider()
        #elseif os(macOS)
            self.presentationProvider = presentationProvider ?? DefaultMacPresentationProvider()
        #else
            self.presentationProvider = presentationProvider ?? DefaultPresentationProvider()
        #endif

        super.init()

        // Set up state handler immediately after initialization
        socketDelegate.stateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                print("WebSocket state changing to: \(newState)")
                self.currentState = newState
            }
        }
    }

    // MARK: - Public Methods

    @MainActor
    public func connect(accountName: String) async throws {
        // Allow reconnection attempts from error or disconnected states
        switch currentState {
        case .disconnected:
            // OK to proceed
            break
        case .error:
            // OK to proceed
            break
        default:
            throw ArkavoError.invalidState
        }

        do {
            // First authenticate
            currentState = .authenticating
            let token = try await authenticateUser(accountName: accountName)
            try KeychainManager.saveAuthenticationToken(token)

            // Then establish WebSocket connection
            currentState = .connecting
            try await setupWebSocketConnection()
            // Wait for connection to complete
            try await waitForConnection()
        } catch {
            currentState = .error(error)
            throw error
        }
    }

    private func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.connectionContinuation = continuation
        }
    }

    public func disconnect() async {
        guard currentState == .connected else { return }

        currentState = .disconnected
        webSocket?.cancel()
        webSocket = nil
        session = nil
        KeychainManager.deleteAuthenticationToken()
    }

    public func sendMessage(_ data: Data) async throws {
        guard currentState == .connected, let webSocket else {
            throw ArkavoError.notConnected
        }

        try await webSocket.send(.data(data))
    }

    // MARK: - Private Methods

    private func authenticateUser(accountName: String) async throws -> String {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyID)

        let registrationOptions = try await fetchRegistrationOptions(accountName: accountName)

        let challengeData = Data(base64Encoded: registrationOptions.challenge.base64URLToBase64())!
        let userIDData = Data(base64Encoded: registrationOptions.userID.base64URLToBase64())!

        let credentialRequest = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: accountName,
            userID: userIDData
        )

        let credential = try await performAuthentication(request: credentialRequest)
        return try await completeRegistration(credential: credential)
    }

    private func setupWebSocketConnection() async throws {
        print("Current state before WebSocket setup: \(currentState)")
        guard currentState == .connecting else {
            print("Invalid state for WebSocket setup: \(currentState)")
            throw ArkavoError.invalidState
        }

        guard let token = KeychainManager.getAuthenticationToken() else {
            currentState = .error(ArkavoError.authenticationFailed("No authentication token"))
            throw ArkavoError.authenticationFailed("No authentication token")
        }

        let wsURL = websocketURL
        print("\nWebSocket Connection Attempt:")
        print("URL: \(wsURL)")

        var request = URLRequest(url: wsURL)
        request.setValue(token, forHTTPHeaderField: "X-Auth-Token")
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue("13", forHTTPHeaderField: "Sec-WebSocket-Version")

        print("\nRequest Headers:")
        dump(request.allHTTPHeaderFields ?? [:])

        let session = URLSession(configuration: .default, delegate: socketDelegate, delegateQueue: delegateQueue)
        self.session = session

        let webSocket = session.webSocketTask(with: request)
        self.webSocket = webSocket

        webSocket.sendPing { [weak self] error in
            Task { @MainActor in
                if let error {
                    print("Initial ping failed: \(error)")
                    self?.connectionContinuation?.resume(throwing: error)
                    self?.connectionContinuation = nil
                    self?.currentState = .error(error)
                } else {
                    print("Initial ping successful")
                }
            }
        }

        print("\nWebSocket Task Created: \(webSocket)")
        webSocket.resume()
        receiveMessage()
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case let .success(message):
                    switch message {
                    case let .data(data):
                        self.delegate?.clientDidReceiveMessage(self, message: data)
                    case let .string(string):
                        if let data = string.data(using: .utf8) {
                            self.delegate?.clientDidReceiveMessage(self, message: data)
                        }
                    @unknown default:
                        break
                    }
                    self.receiveMessage()

                case let .failure(error):
                    print("WebSocket receive error: \(error)")
                    self.currentState = .error(error)
                    self.delegate?.clientDidReceiveError(self, error: error)
                }
            }
        }
    }

    private func fetchRegistrationOptions(accountName: String) async throws -> (challenge: String, userID: String) {
        // Use auth URL for WebAuthn
        let url = authURL.appendingPathComponent("register/\(accountName)")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ... 299).contains(httpResponse.statusCode)
        else {
            throw ArkavoError.invalidResponse
        }

        let decoder = JSONDecoder()
        let options = try decoder.decode(RegistrationOptionsResponse.self, from: data)

        return (options.publicKey.challenge, options.publicKey.user.id)
    }

    private func performAuthentication(request: ASAuthorizationRequest) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AuthenticationDelegate(continuation: continuation)
            controller.delegate = delegate
            controller.presentationContextProvider = self

            // Retain delegate until authentication completes
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            controller.performRequests()
        }
    }

    private func completeRegistration(credential: ASAuthorizationPlatformPublicKeyCredentialRegistration) async throws -> String {
        // Use auth URL for WebAuthn
        var request = URLRequest(url: authURL.appendingPathComponent("register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let parameters: [String: Any] = [
            "id": credential.credentialID.base64URLEncodedString(),
            "rawId": credential.credentialID.base64URLEncodedString(),
            "response": [
                "clientDataJSON": credential.rawClientDataJSON.base64URLEncodedString(),
                "attestationObject": credential.rawAttestationObject!.base64URLEncodedString(),
            ],
            "type": "public-key",
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              let token = httpResponse.allHeaderFields["x-auth-token"] as? String
        else {
            throw ArkavoError.authenticationFailed("No authentication token received")
        }
        // Verify token format
        if !token.starts(with: "eyJ") {
            throw ArkavoError.authenticationFailed("Invalid token format")
        }
        return token
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension ArkavoClient: ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first
            else {
                fatalError("No window found in the current window scene")
            }
            return window
        #elseif os(macOS)
            guard let window = NSApplication.shared.windows.first else {
                fatalError("No window found in the application")
            }
            return window
        #else
            fatalError("Unsupported platform")
        #endif
    }
}

// MARK: - Helper Classes

private class AuthenticationDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>

    init(continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            continuation.resume(throwing: ArkavoError.authenticationFailed("Invalid credential type"))
            return
        }
        continuation.resume(returning: credential)
    }

    func authorizationController(controller _: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}

// MARK: - WebSocket Delegate

public final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.arkavo.websocket.state")
    private var _stateHandler: ((ArkavoClientState) -> Void)?

    var stateHandler: ((ArkavoClientState) -> Void)? {
        get {
            stateQueue.sync { _stateHandler }
        }
        set {
            stateQueue.sync { _stateHandler = newValue }
        }
    }

    public func urlSession(_: URLSession,
                           webSocketTask _: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?)
    {
        print("WebSocket did connect with protocol: \(`protocol` ?? "none")")

        DispatchQueue.main.async { [weak self] in
            print("Updating state to connected")
            self?.stateHandler?(.connected)
        }
    }

    public func urlSession(_: URLSession,
                           task _: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        if let error {
            print("WebSocket did complete with error: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.stateHandler?(.error(error))
            }
        } else {
            print("WebSocket did complete normally")
            DispatchQueue.main.async { [weak self] in
                self?.stateHandler?(.disconnected)
            }
        }
    }

    public func urlSession(_: URLSession,
                           webSocketTask _: URLSessionWebSocketTask,
                           didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                           reason: Data?)
    {
        print("WebSocket did close with code: \(closeCode)")
        if let reason, let reasonStr = String(data: reason, encoding: .utf8) {
            print("Close reason: \(reasonStr)")
        }

        DispatchQueue.main.async { [weak self] in
            self?.stateHandler?(.disconnected)
        }
    }
}

// MARK: - Supporting Types

private struct RegistrationOptionsResponse: Decodable {
    let publicKey: PublicKeyRegistrationOptions
}

private struct PublicKeyRegistrationOptions: Decodable {
    let challenge: String
    let user: User
}

private struct User: Decodable {
    let id: String
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    func base64URLToBase64() -> String {
        var result = replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while result.count % 4 != 0 {
            result += "="
        }
        return result
    }
}

// Default presentation providers
#if os(iOS)
    private class DefaultIOSPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
        func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first
            else {
                fatalError("No window found in the current window scene")
            }
            return window
        }
    }

#elseif os(macOS)
    private class DefaultMacPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
        func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
            guard let window = NSApplication.shared.windows.first else {
                fatalError("No window found in the application")
            }
            return window
        }
    }
#else
    private class DefaultPresentationProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
        func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
            fatalError("Unsupported platform")
        }
    }
#endif
