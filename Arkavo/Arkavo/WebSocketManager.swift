import Foundation
import Combine
import CryptoKit
import OpenTDFKit
import Foundation
import Combine
import CryptoKit

struct NATSMessage {
    let messageType: Data
    let payload: Data
    
    init(payload: Data) {
        self.messageType = Data([0x05])
        self.payload = payload
    }
    
    init(data: Data) {
        self.messageType = data.prefix(1)
        self.payload = data.suffix(from: 1)
    }
    
    func toData() -> Data {
        var data = Data()
        data.append(messageType)
        data.append(payload)
        return data
    }
}

class WebSocketManager: ObservableObject {
    @Published private(set) var webSocket: KASWebSocket?
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published var lastError: String?
    private var cancellables = Set<AnyCancellable>()
    private var kasPublicKeyCallback: ((P256.KeyAgreement.PublicKey) -> Void)?
    private var rewrapCallback: ((Data, SymmetricKey?) -> Void)?
    private var customMessageCallback: ((Data) -> Void)?

    func setupWebSocket(token: String) {
        let url = URL(string: "wss://kas.arkavo.net")!
        print("Connecting to: \(url)")
        print("Token: \(token)")
        webSocket = KASWebSocket(kasUrl: url, token: token)
        
        // Set the callbacks on the new webSocket instance
        if let kasCallback = kasPublicKeyCallback {
            webSocket?.setKASPublicKeyCallback(kasCallback)
        }
        if let rewrapCB = rewrapCallback {
            webSocket?.setRewrapCallback(rewrapCB)
        }
        webSocket?.setCustomMessageCallback { [weak self] data in
            self?.customMessageCallback?(data)
        }
        
        webSocket?.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.connectionState = state
                if state == .disconnected {
                    self?.lastError = "WebSocket disconnected"
                }
            }
            .store(in: &cancellables)
    }
    
    func connect() {
        lastError = nil
        webSocket?.connect()
    }
    
    func close() {
        webSocket?.disconnect()
        cancellables.removeAll()
        webSocket = nil
        connectionState = .disconnected
    }
    
    func setKASPublicKeyCallback(_ callback: @escaping (P256.KeyAgreement.PublicKey) -> Void) {
        kasPublicKeyCallback = callback
        webSocket?.setKASPublicKeyCallback(callback)
    }
    
    func setRewrapCallback(_ callback: @escaping (Data, SymmetricKey?) -> Void) {
        rewrapCallback = callback
        webSocket?.setRewrapCallback(callback)
    }
    
    func sendPublicKey() {
        guard connectionState == .connected else {
            lastError = "Cannot send public key: WebSocket not connected"
            return
        }
        webSocket?.sendPublicKey()
    }
    
    func sendKASKeyMessage() {
        guard connectionState == .connected else {
            lastError = "Cannot send KAS key message: WebSocket not connected"
            return
        }
        webSocket?.sendKASKeyMessage()
    }
    
    func sendRewrapMessage(header: Header) {
        guard connectionState == .connected else {
            lastError = "Cannot send rewrap message: WebSocket not connected"
            return
        }
        webSocket?.sendRewrapMessage(header: header)
    }
    
    func setCustomMessageCallback(_ callback: @escaping (Data) -> Void) {
        customMessageCallback = callback
        webSocket?.setCustomMessageCallback { [weak self] data in
            self?.customMessageCallback?(data)
        }
    }

    func sendCustomMessage(_ message: Data, completion: @escaping (Error?) -> Void) {
        guard connectionState == .connected else {
            lastError = "Cannot send custom message: WebSocket not connected"
            completion(NSError(domain: "WebSocketManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "WebSocket not connected"]))
            return
        }
        webSocket?.sendCustomMessage(message, completion: completion)
    }
}
