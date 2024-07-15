import Foundation
import Combine
import CryptoKit
import OpenTDFKit
import Foundation
import Combine
import CryptoKit

class WebSocketManager: ObservableObject {
    @Published private(set) var webSocket: KASWebSocket?
    @Published private(set) var connectionState: WebSocketConnectionState = .disconnected
    @Published var lastError: String?
    private var cancellables = Set<AnyCancellable>()
    
    private var kasPublicKeyCallback: ((P256.KeyAgreement.PublicKey) -> Void)?
    private var rewrapCallback: ((Data, SymmetricKey?) -> Void)?

    init() {
        setupWebSocket()
    }

    func setupWebSocket() {
        let url = URL(string: "wss://kas.arkavo.net")!
        webSocket = KASWebSocket(kasUrl: url)
        
        // Set the callbacks on the new webSocket instance
        if let kasCallback = kasPublicKeyCallback {
            webSocket?.setKASPublicKeyCallback(kasCallback)
        }
        if let rewrapCB = rewrapCallback {
            webSocket?.setRewrapCallback(rewrapCB)
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
}
