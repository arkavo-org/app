import Combine
import CryptoKit
import Foundation
import OpenTDFKit

class ArkavoService {
    public static var kasPublicKey: P256.KeyAgreement.PublicKey?
    let webSocketManager: WebSocketManager
    private var cancellables = Set<AnyCancellable>()
    private var isReconnecting = false
    private var hasInitialConnection = false
    let nanoTDFManager = NanoTDFManager()
    let authenticationManager = AuthenticationManager()
    var thoughtService: ThoughtService?
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        var videoStreamViewModel: VideoStreamViewModel?
    #endif
    var token: String?

    init() {
        webSocketManager = WebSocketManager.shared
    }

    func setupCallbacks() {
        thoughtService = ThoughtService(self)
        webSocketManager.setKASPublicKeyCallback { publicKey in
            if ArkavoService.kasPublicKey != nil {
                return
            }
            DispatchQueue.main.async {
                print("Received KAS Public Key")
                ArkavoService.kasPublicKey = publicKey
            }
        }
        webSocketManager.setRewrapCallback { id, symmetricKey in
            self.handleRewrapCallback(id: id, symmetricKey: symmetricKey)
        }
        webSocketManager.setCustomMessageCallback { [weak self] data in
            guard let self else { return }
//            print("Received Custom Message: \(data.base64EncodedString())")
            Task {
                await self.handleIncomingNATSMessage(data: data)
            }
        }
    }

    private func handleIncomingNATSMessage(data: Data) async {
//        print("NATS payload size: \(data.count)")
        guard data.count > 4 else {
            print("Invalid NATS message: \(data.base64EncodedString())")
            return
        }
        do {
            // FIXME: copy of data after first byte
            let subData = data.subdata(in: 1 ..< data.count)
            // Create a NanoTDF from the payload
            let parser = BinaryParser(data: subData)
            let header = try parser.parseHeader()
            let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
            let nanoTDF = NanoTDF(header: header, payload: payload, signature: nil)
            sendRewrapNanoTDF(nano: nanoTDF)
        } catch let error as ParsingError {
            handleParsingError(error)
        } catch {
            print("Unexpected error: \(error.localizedDescription)")
        }
    }

    /// Sends a rewrap message with the provided header.
    func sendRewrapNanoTDF(nano: NanoTDF) {
        // Use the nanoTDFManager to handle the incoming NanoTDF
        let id = nano.header.ephemeralPublicKey
//            print("ephemeralPublicKey: \(id.base64EncodedString())")
        nanoTDFManager.addNanoTDF(nano, withIdentifier: id)
        webSocketManager.sendRewrapMessage(header: nano.header)
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
        // Create a Task to handle the asynchronous work
        Task {
            do {
                // Decrypt payload within the Task
                let payload = try nano.getPayloadPlaintext(symmetricKey: symmetricKey)

                // Determine payload type based on policy metadata
                let policy = ArkavoPolicy(nano.header.policy)

                // Handle different policy types
                switch policy.type {
                case .accountProfile:
                    // TODO: Handle account profile
                    break
                case .streamProfile:
                    // TODO: Handle stream profile
                    break
                case .thought:
                    await handleThought(payload: payload, policy: policy, nano: nano)
                case .videoFrame:
                    await handleVideoFrame(payload: payload)
                }
            } catch {
                print("Unexpected error during nanoTDF decryption: \(error)")
            }
        }
    }

    private func handleThought(payload: Data, policy: ArkavoPolicy, nano: NanoTDF) async {
        guard let thoughtService else { return }
        do {
            try await thoughtService.handle(payload, policy: policy, nano: nano)
        } catch {
//            print("Error handling thought: \(error)")
            // FIXME: hack since only .thought and .videoFrame is supported, assume failed .thought
            #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
                await handleVideoFrame(payload: payload)
            #endif
        }
    }

    private func handleVideoFrame(payload: Data) async {
        #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
            await MainActor.run {
                videoStreamViewModel?.receiveVideoFrame(payload)
            }
        #endif
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

    private func handleParsingError(_ error: ParsingError) {
        switch error {
        case .invalidFormat:
            print("Invalid NanoTDF format")
        case .invalidEphemeralKey:
            print("Invalid NanoTDF ephemeral key")
        case .invalidPayload:
            print("Invalid NanoTDF payload")
        case .invalidMagicNumber:
            print("Invalid NanoTDF magic number")
        case .invalidVersion:
            print("Invalid NanoTDF version")
        case .invalidKAS:
            print("Invalid NanoTDF kas")
        case .invalidECCMode:
            print("Invalid NanoTDF ecc mode")
        case .invalidPayloadSigMode:
            print("Invalid NanoTDF payload signature mode")
        case .invalidPolicy:
            print("Invalid NanoTDF policy")
        case .invalidPublicKeyLength:
            print("Invalid NanoTDF public key length")
        case .invalidSignatureLength:
            print("Invalid NanoTDF signature length")
        case .invalidSigning:
            print("Invalid NanoTDF signing")
        }
    }
}
