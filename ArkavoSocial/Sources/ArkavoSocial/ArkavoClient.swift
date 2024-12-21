import AuthenticationServices
import CryptoKit
import Foundation
import OpenTDFKit

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
public enum ArkavoClientState: Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case error(Error)

    public static func == (lhs: ArkavoClientState, rhs: ArkavoClientState) -> Bool {
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
public protocol ArkavoClientDelegate: AnyObject {
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
    private let curve: KeyExchangeCurve
    private var keyPair: CurveKeyPair?
    private var sharedSecret: SharedSecret?
    private var salt: Data?
    private var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var sessionSymmetricKey: SymmetricKey?
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let delegateQueue = OperationQueue()
    private let socketDelegate: WebSocketDelegate
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var messageHandlers: [UInt8: CheckedContinuation<Data, Error>] = [:]
    private var natsMessageHandler: ((Data) -> Void)?
    private var natsEventHandler: ((Data) -> Void)?

    public var currentState: ArkavoClientState = .disconnected {
        didSet {
            delegate?.clientDidChangeState(self, state: currentState)
        }
    }

    public func getSessionSymmetricKey() -> SymmetricKey? {
        sessionSymmetricKey
    }

    public weak var delegate: ArkavoClientDelegate?
    private let presentationProvider: ASAuthorizationControllerPresentationContextProviding
    public var currentToken: String? {
        // TODO: Check if the token has expired
        KeychainManager.getAuthenticationToken()
    }

    public init(authURL: URL,
                websocketURL: URL,
                relyingPartyID: String,
                curve: KeyExchangeCurve = .p256,
                presentationProvider: ASAuthorizationControllerPresentationContextProviding? = nil)
    {
        self.authURL = authURL
        self.websocketURL = websocketURL
        self.relyingPartyID = relyingPartyID
        self.curve = curve
        socketDelegate = WebSocketDelegate()

        #if os(iOS)
            self.presentationProvider = presentationProvider ?? DefaultIOSPresentationProvider()
        #elseif os(macOS)
            self.presentationProvider = presentationProvider ?? DefaultMacPresentationProvider()
        #else
            self.presentationProvider = presentationProvider ?? DefaultPresentationProvider()
        #endif

        super.init()

        socketDelegate.setStateHandler { [weak self] newState in
            Task { @MainActor [weak self] in
                guard let self else { return }
                print("WebSocket state changing to: \(newState)")
                self.currentState = newState
                
                // Resume the continuation when connected
                switch newState {
                case .connected:
                    if let continuation = self.connectionContinuation {
                        self.connectionContinuation = nil
                        continuation.resume(returning: ())
                    }
                case .error(let error):
                    if let continuation = self.connectionContinuation {
                        self.connectionContinuation = nil
                        continuation.resume(throwing: error)
                    }
                    // Also handle any pending message handlers
                    for handler in self.messageHandlers.values {
                        handler.resume(throwing: error)
                    }
                    self.messageHandlers.removeAll()
                case .disconnected:
                    // Clean up any pending handlers on disconnect
                    let error = ArkavoError.connectionFailed("Connection disconnected")
                    for handler in self.messageHandlers.values {
                        handler.resume(throwing: error)
                    }
                    self.messageHandlers.removeAll()
                case .connecting:
                    print("connecting")
                case .authenticating:
                    print("authenticating")
                }
            }
        }

        // Start receiving messages when connection is established
        socketDelegate.onConnect = { [weak self] in
            self?.receiveMessage()
        }
    }

    // MARK: - Public Methods

    @MainActor
    public func connect(accountName: String) async throws {
        // Check current state more thoroughly
        switch currentState {
        case .disconnected:
            // OK to proceed
            break
        case .error:
            // First disconnect if we're in error state
            await disconnect()
        case .connected:
            print("Already connected, no need to reconnect")
            return
        case .connecting, .authenticating:
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
            // swap keys
            try await sendInitialMessages()
        } catch {
            print("connect error: \(error)")
            currentState = .error(error)
            throw error
        }
    }

    private func waitForConnection() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { [weak self] continuation in
                    guard let self else {
                        continuation.resume(throwing: ArkavoError.connectionFailed("Client deallocated"))
                        return
                    }
                    Task { @MainActor in
                        self.connectionContinuation = continuation
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                throw ArkavoError.connectionFailed("Connection timeout")
            }

            try await group.next()
            group.cancelAll()
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

        print("Sending WebSocket message:")
        print("Message type: 0x\(String(format: "%02X", data.first ?? 0))")
        print("Message length: \(data.count)")

        try await webSocket.send(.data(data))
    }

    private func waitForMessage(type: ArkavoMessageType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                self.messageHandlers[type.rawValue] = continuation
            }
        }
    }

    private func sendInitialMessages() async throws {
        print("Beginning sendInitialMessages")
        guard let webSocket else {
            print("Error: WebSocket is nil")
            throw ArkavoError.notConnected
        }

        // Create key pair for the selected curve
        print("Creating key pair for curve: \(curve)")
        keyPair = try createKeyPair()
        print("Successfully created key pair")

        // Send public key
        let publicKeyMessage = PublicKeyMessage(publicKey: keyPair!.publicKeyData)
        print("Sending public key message, key length: \(publicKeyMessage.publicKey.count)")
        try await webSocket.send(.data(publicKeyMessage.toData()))
        print("Successfully sent public key message")

        // Wait for public key response
        do {
            print("Waiting for public key response...")
            let publicKeyData = try await waitForMessage(type: .publicKey)
            print("Received public key response, length: \(publicKeyData.count)")

            print("Processing public key response...")
            try handlePublicKeyResponse(data: publicKeyData)
            print("Successfully processed public key response")
            print("Salt length: \(salt?.count ?? 0)")
            print("Shared secret established: \(sharedSecret != nil)")
        } catch {
            print("Error handling public key response: \(error)")
            currentState = .error(error)
            throw error
        }

        // Send KAS key message
        print("Sending KAS key message")
        let kasKeyMessage = KASKeyMessage()
        try await webSocket.send(.data(kasKeyMessage.toData()))
        print("Successfully sent KAS key message")

        // Wait for KAS key response
        do {
            print("Waiting for KAS key response...")
            let kasKeyData = try await waitForMessage(type: .kasKey)
            print("Received KAS key response, length: \(kasKeyData.count)")

            print("Processing KAS key response...")
            try handleKASKeyResponse(data: kasKeyData)
            print("Successfully processed KAS key response")
        } catch {
            print("Error handling KAS key response: \(error)")
            currentState = .error(error)
            throw error
        }

        print("sendInitialMessages completed successfully")
    }

    // Helper method for sending messages and awaiting responses
    private func sendAndWait(_ message: some ArkavoMessage) async throws -> Data {
        try await webSocket?.send(.data(message.toData()))
        return try await waitForMessage(type: message.messageType)
    }

    // MARK: - Private Methods

    private func createKeyPair() throws -> CurveKeyPair {
        switch curve {
        case .p256:
            P256KeyPair(privateKey: P256.KeyAgreement.PrivateKey())
        case .p384:
            P384KeyPair(privateKey: P384.KeyAgreement.PrivateKey())
        case .p521:
            P521KeyPair(privateKey: P521.KeyAgreement.PrivateKey())
        }
    }

    private func handlePublicKeyResponse(data: Data) throws {
        print("handlePublicKeyResponse - Received data length: \(data.count)")

        guard data.first == 0x01 else {
            print("Error: Invalid message type byte: \(String(format: "0x%02X", data.first ?? 0))")
            throw ArkavoError.invalidResponse
        }

        let responseData = data.dropFirst()
        let expectedLength = curve.compressedKeySize + 32 // compressed public key + salt
        print("Expected response length: \(expectedLength), Actual length: \(responseData.count)")

        guard responseData.count == expectedLength else {
            print("Error: Response data length mismatch")
            throw ArkavoError.messageError("Invalid public key response length")
        }

        // Set session salt
        salt = responseData.suffix(32)
        let publicKeyData = responseData.prefix(curve.compressedKeySize)
        print("Extracted salt length: \(salt?.count ?? 0)")
        print("Extracted public key length: \(publicKeyData.count)")

        // Compute shared secret using the appropriate curve
        print("Computing shared secret...")
        sharedSecret = try keyPair?.computeSharedSecret(withPublicKeyData: publicKeyData)

        // Derive session symmetric key
        if let sharedSecret, let salt {
            sessionSymmetricKey = deriveSessionSymmetricKey(sharedSecret: sharedSecret, salt: salt)
        }

        print("Shared secret computation: \(sharedSecret != nil ? "successful" : "failed")")
    }

    // Helper method to derive the session symmetric key
    private func deriveSessionSymmetricKey(sharedSecret: SharedSecret, salt: Data) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("rewrappedKey".utf8),
            outputByteCount: 32
        )
    }

    // Helper method to decrypt rewrapped keys
    public func decryptRewrappedKey(nonce: Data, rewrappedKey: Data, authTag: Data) throws -> SymmetricKey {
        guard let sessionKey = sessionSymmetricKey else {
            throw ArkavoError.invalidState
        }

        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: rewrappedKey,
            tag: authTag
        )

        let decryptedDataSharedSecret = try AES.GCM.open(sealedBox, using: sessionKey)
        let sharedSecretKey = SymmetricKey(data: decryptedDataSharedSecret)

        return deriveSymmetricKey(
            sharedSecretKey: sharedSecretKey,
            salt: Data("L1L".utf8),
            info: Data("encryption".utf8),
            outputByteCount: 32
        )
    }

    private func handleKASKeyResponse(data: Data) throws {
        print("handleKASKeyResponse - Received data length: \(data.count)")

        guard data.first == 0x02 else {
            print("Error: Invalid message type byte: \(String(format: "0x%02X", data.first ?? 0))")
            throw ArkavoError.invalidResponse
        }

        let kasPublicKeyData = data.dropFirst()
        print("KAS public key length: \(kasPublicKeyData.count), Expected length: \(curve.compressedKeySize)")

        guard kasPublicKeyData.count == curve.compressedKeySize else {
            print("Error: KAS public key length mismatch")
            throw ArkavoError.messageError("Invalid KAS public key length")
        }

        // Validate KAS public key format
        print("Validating KAS public key format...")
        do {
            switch curve {
            case .p256:
                kasPublicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: kasPublicKeyData)
            case .p384:
                _ = try P384.KeyAgreement.PublicKey(compressedRepresentation: kasPublicKeyData)
            case .p521:
                _ = try P521.KeyAgreement.PublicKey(compressedRepresentation: kasPublicKeyData)
            }
            print("KAS public key validation successful")
        } catch {
            print("Error validating KAS public key: \(error)")
            throw error
        }
    }

    // Helper method to derive a symmetric key
    public func deriveSymmetricKey(sharedSecretKey: SymmetricKey, salt: Data, info: Data, outputByteCount: Int = 32) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: sharedSecretKey,
            salt: salt,
            info: info,
            outputByteCount: outputByteCount
        )
    }

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

//        print("\nRequest Headers:")
//        dump(request.allHTTPHeaderFields ?? [:])

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

    public func setNATSMessageHandler(_ handler: @escaping (Data) -> Void) {
        natsMessageHandler = handler
    }

    public func setNATSEventHandler(_ handler: @escaping (Data) -> Void) {
        natsEventHandler = handler
    }

    private func receiveMessage() {
        print("receiveMessage")
        guard let webSocket else {
            print("WebSocket is nil, cannot receive message")
            return
        }

        webSocket.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case let .success(message):
                    print("\n=== Received WebSocket Message ===")
                    print("Message type: \(message)")
                    switch message {
                    case let .data(data):
                        await self.handleIncomingMessage(data)
                    case let .string(string):
                        print("Received string message: \(string)")
                        if let data = string.data(using: .utf8) {
                            self.delegate?.clientDidReceiveMessage(self, message: data)
                        }
                    @unknown default:
                        print("Received unknown message type")
                    }

                case let .failure(error):
                    print("WebSocket receive error: \(error)")
                    self.currentState = .error(error)
                    self.delegate?.clientDidReceiveError(self, error: error)

                    // Resume any waiting continuations with error
                    for continuation in self.messageHandlers.values {
                        continuation.resume(throwing: error)
                    }
                    self.messageHandlers.removeAll()
                }

                // Continue receiving messages if still connected
                if self.currentState == .connected {
                    self.receiveMessage()
                }
            }
        }
    }

    // New message handling function
    private func handleIncomingMessage(_ data: Data) async {
        guard let messageType = data.first else {
            print("Invalid message: empty data")
            return
        }

        print("Received data message:")
        print("Length: \(data.count) bytes")
        print("Message type: 0x\(String(format: "%02X", messageType))")
        print("Raw data (hex): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        let messageData = data.dropFirst() // Remove message type byte

        // Handle continuation-based messages first
        if let continuation = messageHandlers.removeValue(forKey: messageType) {
            continuation.resume(returning: data)
            return
        }

        // Then handle via delegate
        delegate?.clientDidReceiveMessage(self, message: data)
    }

    private func handleRewrappedKeyMessage(_ data: Data) {
        print("ArkavoClient Handling rewrapped key message of length: \(data.count)")
        guard data.count == 93 else {
            if data.count == 33 {
                // DENY -- Notify the app with the identifier
                delegate?.clientDidReceiveMessage(self, message: data)
                return
            }
            print("RewrappedKeyMessage not the expected 93 bytes: \(data.count)")
            return
        }

        let identifier = data.prefix(33)
        let keyData = data.suffix(60)
        // Parse key data components
        let nonce = keyData.prefix(12)
        let encryptedKeyLength = keyData.count - 12 - 16 // Total - nonce - tag

        guard encryptedKeyLength >= 0 else {
            print("Invalid encrypted key length: \(encryptedKeyLength)")
            return
        }

        let rewrappedKey = keyData.prefix(keyData.count - 16).suffix(encryptedKeyLength)
        let authTag = keyData.suffix(16)

        // Process the rewrapped key...
        // (Implementation specific to your needs)
        delegate?.clientDidReceiveMessage(self, message: data)
    }

    // Add methods to send NATS messages
    public func sendNATSMessage(_ payload: Data) async throws {
        let message = NATSMessage(message: payload)
        try await sendMessage(message.toData())
    }

    public func sendNATSEvent(_ payload: Data) async throws {
        let message = NATSEvent(message: payload)
        try await sendMessage(message.toData())
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

    public func encryptAndSendPayload(
        payload: Data,
        policyData: Data
    ) async throws -> Data {
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = try KasMetadata(
            resourceLocator: kasRL,
            publicKey: kasPublicKey,
            curve: .secp256r1
        )

        var policy = Policy(
            type: .embeddedPlaintext,
            body: EmbeddedPolicyBody(body: policyData),
            remote: nil,
            binding: nil
        )

        // Create NanoTDF
        let nanoTDF = try await createNanoTDF(
            kas: kasMetadata,
            policy: &policy,
            plaintext: payload
        )

        // Send via NATS message
        let natsMessage = NATSMessage(message: nanoTDF.toData())
        try await sendMessage(natsMessage.toData())

        return nanoTDF.toData()
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

private actor WebSocketStateHandler {
    var stateHandler: ((ArkavoClientState) -> Void)?

    func updateHandler(_ handler: @escaping (ArkavoClientState) -> Void) {
        stateHandler = handler
    }

    func handleState(_ state: ArkavoClientState) async {
        await stateHandler?(state)
    }
}

private final class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    private let stateQueue = DispatchQueue(label: "com.arkavo.websocket.state")
    private let stateHandler = WebSocketStateHandler()
    private var _onConnect: (() -> Void)?

    var onConnect: (() -> Void)? {
        get { stateQueue.sync { _onConnect } }
        set { stateQueue.sync { _onConnect = newValue } }
    }

    func setStateHandler(_ handler: @Sendable @escaping (ArkavoClientState) -> Void) {
        Task {
            await stateHandler.updateHandler(handler)
        }
    }

    public func urlSession(_: URLSession,
                           webSocketTask _: URLSessionWebSocketTask,
                           didOpenWithProtocol protocol: String?)
    {
        print("WebSocket did connect with protocol: \(`protocol` ?? "none")")
        Task {
            await stateHandler.handleState(.connected)
        }
    }

    public func urlSession(_: URLSession,
                           task _: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        Task {
            if let error {
                print("WebSocket did complete with error: \(error)")
                await stateHandler.handleState(.error(error))
            } else {
                print("WebSocket did complete normally")
                await stateHandler.handleState(.disconnected)
            }
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

// MARK: - Supporting Types

// Message type identifiers
public enum ArkavoMessageType: UInt8 {
    case publicKey = 0x01
    case kasKey = 0x02
    case rewrap = 0x03
    case rewrappedKey = 0x04
    case natsMessage = 0x05
    case natsEvent = 0x06
}

// Protocol for messages
protocol ArkavoMessage {
    var messageType: ArkavoMessageType { get }
    func payload() -> Data
}

// Extension to handle common message formatting
extension ArkavoMessage {
    func toData() -> Data {
        var data = Data()
        data.append(messageType.rawValue)
        data.append(payload())
        return data
    }
}

// Concrete message implementations
struct PublicKeyMessage: ArkavoMessage {
    let messageType: ArkavoMessageType = .publicKey
    let publicKey: Data

    func payload() -> Data {
        publicKey
    }
}

struct KASKeyMessage: ArkavoMessage {
    let messageType: ArkavoMessageType = .kasKey

    func payload() -> Data {
        Data()
    }
}

struct RewrapMessage: ArkavoMessage {
    let messageType: ArkavoMessageType = .rewrap
    let header: Header

    func payload() -> Data {
        header.toData()
    }
}

struct RewrappedKeyMessage: ArkavoMessage {
    let messageType: ArkavoMessageType = .rewrappedKey
    let rewrappedKey: Data

    func payload() -> Data {
        rewrappedKey
    }
}

struct NATSMessage: ArkavoMessage {
    let messageType: ArkavoMessageType = .natsMessage
    let message: Data

    func payload() -> Data {
        message
    }
}

struct NATSEvent: ArkavoMessage {
    let messageType: ArkavoMessageType = .natsEvent
    let message: Data

    func payload() -> Data {
        message
    }
}

/// Supported elliptic curves for key exchange
public enum KeyExchangeCurve {
    case p256
    case p384
    case p521

    var keySize: Int {
        switch self {
        case .p256: 32
        case .p384: 48
        case .p521: 66
        }
    }

    var compressedKeySize: Int {
        // Compressed public key is 1 byte prefix + key size
        keySize + 1
    }
}

/// Protocol for curve-specific key operations
private protocol CurveKeyPair {
    var publicKeyData: Data { get }
    func computeSharedSecret(withPublicKeyData: Data) throws -> SharedSecret
}

// Concrete implementations for each curve
private struct P256KeyPair: CurveKeyPair {
    let privateKey: P256.KeyAgreement.PrivateKey

    var publicKeyData: Data {
        privateKey.publicKey.compressedRepresentation
    }

    func computeSharedSecret(withPublicKeyData data: Data) throws -> SharedSecret {
        let publicKey = try P256.KeyAgreement.PublicKey(compressedRepresentation: data)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }
}

private struct P384KeyPair: CurveKeyPair {
    let privateKey: P384.KeyAgreement.PrivateKey

    var publicKeyData: Data {
        privateKey.publicKey.compressedRepresentation
    }

    func computeSharedSecret(withPublicKeyData data: Data) throws -> SharedSecret {
        let publicKey = try P384.KeyAgreement.PublicKey(compressedRepresentation: data)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }
}

private struct P521KeyPair: CurveKeyPair {
    let privateKey: P521.KeyAgreement.PrivateKey

    var publicKeyData: Data {
        privateKey.publicKey.compressedRepresentation
    }

    func computeSharedSecret(withPublicKeyData data: Data) throws -> SharedSecret {
        let publicKey = try P521.KeyAgreement.PublicKey(compressedRepresentation: data)
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }
}
