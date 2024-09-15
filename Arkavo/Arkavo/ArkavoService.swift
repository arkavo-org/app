import Combine
import CryptoKit
import Foundation
import OpenTDFKit

class ArkavoService {
    let webSocketManager: WebSocketManager
    private var cancellables = Set<AnyCancellable>()
    private var isReconnecting = false
    private var hasInitialConnection = false
    let nanoTDFManager = NanoTDFManager()
    let authenticationManager = AuthenticationManager()
    let thoughtService: ThoughtService
    var kasPublicKey: P256.KeyAgreement.PublicKey?
    var token: String?

    init(_ webSocketManager: WebSocketManager) {
        self.webSocketManager = webSocketManager
        thoughtService = ThoughtService(nanoTDFManager: nanoTDFManager, webSocketManager: webSocketManager)
    }

    func setupCallbacks() {
        webSocketManager.setKASPublicKeyCallback { publicKey in
            if self.kasPublicKey != nil {
                return
            }
            DispatchQueue.main.async {
                print("Received KAS Public Key")
                self.kasPublicKey = publicKey
            }
        }
        webSocketManager.setRewrapCallback { id, symmetricKey in
            self.handleRewrapCallback(id: id, symmetricKey: symmetricKey)
        }
    }

    func handleRewrapCallback(id: Data?, symmetricKey: SymmetricKey?) {
        guard let id else {
            print("missing id")
            return
        }
        guard let nano = nanoTDFManager.getNanoTDF(withIdentifier: id) else {
            print("missing nanoTDF")
            return
        }
        nanoTDFManager.removeNanoTDF(withIdentifier: id)
        guard let symmetricKey else {
            print("DENY")
            return
        }
        // dispatch
        DispatchQueue.global(qos: .default).async {
            do {
                // determine payload type based on policy metadata
                let policy = ArkavoPolicy(nano.header.policy)
                // decrypt payload
                let payload = try nano.getPayloadPlaintext(symmetricKey: symmetricKey)
                // TODO: route to appropriate service
                switch policy.type {
                case .accountProfile:
                    // TODO:
                    break
                case .streamProfile:
                    // TODO:
                    break
                case .thought:
                    try self.thoughtService.handle(payload, policy: policy, nano: nano.toData())
                case .videoFrame:
                    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                        DispatchQueue.main.async {
                            videoStreamViewModel.receiveVideoFrame(payload)
                        }
                    #endif
                }
                // TODO: register service for each payload type

                // Try to deserialize as a Thought first
//                if let thought = try? ThoughtService.deserialize(from: payload) {
//                    DispatchQueue.main.async {
//                        // Update the ThoughtStreamView
//                        thoughtStreamViewModel.receiveThought(thought)
//                    }
//                } else if let city = try? City.deserialize(from: payload) {
//                    // If it's not a Thought, try to deserialize as a City
//                    DispatchQueue.main.async {
//                        streamMapView?.addCityToCluster(city)
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
//                            streamMapView?.removeCityFromCluster(city)
//                        }
//                    }
//                } else {
                #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                    // If it's neither a Thought nor a City, assume it's a video frame
                    DispatchQueue.main.async {
                        videoStreamViewModel.receiveVideoFrame(payload)
                    }
                #endif
//                }
            } catch {
                print("Unexpected error during nanoTDF decryption: \(error)")
            }
        }
    }

    func setupWebSocketManager(token: String) {
        self.token = token
        // Subscribe to connection state changes
        webSocketManager.$connectionState
            .sink { state in
                if state == .connected, !self.hasInitialConnection {
                    DispatchQueue.main.async {
                        print("Initial connection established. Sending public key and KAS key message.")
                        self.hasInitialConnection = self.webSocketManager.sendPublicKey() && self.webSocketManager.sendKASKeyMessage()
                    }
                } else if state == .disconnected {
                    self.hasInitialConnection = false
                }
            }
            .store(in: &cancellables)
        webSocketManager.setupWebSocket(token: token)
        webSocketManager.connect()
    }

    func resetWebSocketManager() {
        isReconnecting = true
        hasInitialConnection = false
        webSocketManager.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Increased delay to 1 second
            self.setupWebSocketManager(token: self.token!)
            self.isReconnecting = false
        }
    }
}
