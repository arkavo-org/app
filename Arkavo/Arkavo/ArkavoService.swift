import Combine
import CryptoKit
import FlatBuffers
import Foundation
import OpenTDFKit

struct NATSMessage {
    let messageType: Data
    let payload: Data

    init(payload: Data) {
        messageType = Data([0x05])
        self.payload = payload
    }

    init(data: Data) {
        messageType = data.prefix(1)
        payload = data.suffix(from: 1)
    }

    func toData() -> Data {
        var data = Data()
        data.append(messageType)
        data.append(payload)
        return data
    }
}

struct NATSEvent {
    let messageType: Data
    let payload: Data

    init(payload: Data) {
        messageType = Data([0x06])
        self.payload = payload
    }

    init(data: Data) {
        messageType = data.prefix(1)
        payload = data.suffix(from: 1)
    }

    func toData() -> Data {
        var data = Data()
        data.append(messageType)
        data.append(payload)
        return data
    }
}

class ArkavoService {
    public static var kasPublicKey: P256.KeyAgreement.PublicKey?
    let webSocketManager: WebSocketManager
    private var cancellables = Set<AnyCancellable>()
    private var isReconnecting = false
    private var hasInitialConnection = false
    let nanoTDFManager = NanoTDFManager()
    let authenticationManager = AuthenticationManager()
    var thoughtService: ThoughtService?
    var streamService: StreamService?
    #if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
        var videoStreamViewModel: VideoStreamViewModel?
    #endif
    var token: String?

    init() {
        webSocketManager = WebSocketManager.shared
    }

    func setupCallbacks() {
        thoughtService = ThoughtService(self)
        streamService = StreamService(self)
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
                await self.handleIncomingNATS(data: data)
            }
        }
    }

    func sendMessage(_ nano: Data) throws {
        let natsMessage = NATSMessage(payload: nano)
        let messageData = natsMessage.toData()
        print("Sending NATS message: \(messageData)")
        WebSocketManager.shared.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending stream: \(error)")
            }
        }
    }

    func sendEvent(_ payload: Data) throws {
        let natsMessage = NATSEvent(payload: payload)
        let messageData = natsMessage.toData()
        print("Sending NATS event: \(messageData)")
        WebSocketManager.shared.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending stream: \(error)")
            }
        }
    }

    private func handleIncomingNATS(data: Data) async {
        guard data.count > 4 else {
            print("Invalid NATS message: \(data.base64EncodedString())")
            return
        }
        let messageType = data.prefix(1)
        switch messageType[0] {
        case 0x05, 0x06:
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
        default:
            print("Unknown message type: \(messageType.base64EncodedString())")
        }
    }

    // FIXME: add to handle rewrap - handleNATSEvent(payload: payload)

    private func handleNATSEvent(payload: Data) {
        print("Received NATS event: \(payload.base64EncodedString())")
        var bb = ByteBuffer(data: payload)
        do {
            var verifier = try Verifier(buffer: &bb)
            try Arkavo_Event.verify(&verifier, at: 0, of: Arkavo_Event.self)
            print("The bytes represent a valid Arkavo_Event")
        } catch {
            print("Verification failed: \(error)")
            return
        }

        let event = Arkavo_Event(bb, o: 0)

        print("  Action: \(event.action)")

        switch event.dataType {
        case .userevent:
            if let userEvent = event.data(type: Arkavo_UserEvent.self) {
                handleUserEvent(userEvent)
            }
        case .cacheevent:
            if let cacheEvent = event.data(type: Arkavo_CacheEvent.self) {
                handleCacheEvent(cacheEvent)
            }
        case .routeevent:
            if let routeEvent = event.data(type: Arkavo_RouteEvent.self) {
                handleRouteEvent(routeEvent)
            }
        case .none_:
            print("  No event data")
        }
    }

    private func handleRouteEvent(_ routeEvent: Arkavo_RouteEvent) {
        print("Route Event:")
        print("  Source Type: \(routeEvent.sourceType)")
        print("  Target Type: \(routeEvent.targetType)")
        print("  Source ID: \(Data(routeEvent.sourceId).base64EncodedString())")
    }

    private func handleUserEvent(_ userEvent: Arkavo_UserEvent) {
        print("User Event:")
        print("  Source Type: \(userEvent.sourceType)")
        print("  Target Type: \(userEvent.targetType)")
        print("  Source ID: \(Data(userEvent.sourceId).base64EncodedString())")
        print("  Target ID: \(Data(userEvent.targetId).base64EncodedString())")
        // Add any additional processing for user events here
    }

    private func handleCacheEvent(_ cacheEvent: Arkavo_CacheEvent) {
        print("Cache Event:")
        print("  Target ID: \(Data(cacheEvent.targetId).base64EncodedString())")
        print("  TTL: \(cacheEvent.ttl)")
        print("  One-Time Access: \(cacheEvent.oneTimeAccess)")
        // Add any additional processing for cache events here
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
            print("missing nanoTDF \(id.base64EncodedString())")
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
                    await handleStreamProfile(payload: payload, policy: policy, nano: nano)
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

    private func handleStreamProfile(payload: Data, policy: ArkavoPolicy, nano: NanoTDF) async {
        guard let streamService else {
            print("Stream service is not initialized")
            return
        }
        do {
            // Handle the stream profile using the stream service
            try await streamService.handle(payload, policy: policy, nano: nano)
        } catch {
            print("Error handling stream profile: \(error)")
        }
    }

    private func handleThought(payload: Data, policy: ArkavoPolicy, nano: NanoTDF) async {
        guard let thoughtService else { return }
        do {
            try await thoughtService.handle(payload, policy: policy, nano: nano)
        } catch {
            print("Error handling thought: \(error)")
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
