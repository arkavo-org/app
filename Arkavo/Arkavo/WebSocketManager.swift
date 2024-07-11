import Foundation
import CryptoKit
import OpenTDFKit

class WebSocketManager: ObservableObject {
    @Published private(set) var webSocket: KASWebSocket?
    
    init() {
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        let url = URL(string: "wss://kas.arkavo.net")!
        webSocket = KASWebSocket(kasUrl: url)
    }
    
    func setRewrapCallback(callback: @escaping (Data?, SymmetricKey?) -> Void) {
        webSocket?.setRewrapCallback { identifier, symmetricKey in
            callback(identifier, symmetricKey)
        }
    }
    
    func setKASPublicKeyCallback(callback: @escaping (P256.KeyAgreement.PublicKey) -> Void) {
        webSocket?.setKASPublicKeyCallback { publicKey in
            callback(publicKey)
        }
    }
    
    func connect() {
        webSocket?.connect()
    }
    
    func sendPublicKey() {
        webSocket?.sendPublicKey()
    }
    
    func sendKASKeyMessage() {
        webSocket?.sendKASKeyMessage()
    }
    
    func sendRewrapMessage(header: Header) {
        webSocket?.sendRewrapMessage(header: header)
    }
    
    func close() {
        webSocket?.disconnect()
        webSocket = nil
    }
}
