import Combine
import CryptoKit
import FlatBuffers
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
    let redditAuthManager = RedditAuthManager()
    var thoughtService: ThoughtService?
    var streamService: StreamService?
    var protectorService: ProtectorService?
    private let locationManager = LocationManager()
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
        protectorService = ProtectorService()
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
        // FIXME: copy of data after first byte
        let subData = data.subdata(in: 1 ..< data.count)
        switch messageType[0] {
        case 0x05:
            do {
                let parser = BinaryParser(data: subData)
                let header = try parser.parseHeader()
                let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
                let nanoTDF = NanoTDF(header: header, payload: payload, signature: nil)
                sendRewrapNanoTDF(nano: nanoTDF)
            } catch let error as ParsingError {
                handleParsingError(error)
            } catch {
                print("Unexpected 0x05 error: \(error.localizedDescription)")
            }
        case 0x06:
            do {
                let parser = BinaryParser(data: subData)
                let header = try parser.parseHeader()
                let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
                let nanoTDF = NanoTDF(header: header, payload: payload, signature: nil)
                sendRewrapNanoTDF(nano: nanoTDF)
            } catch let error as ParsingError {
                if error == .invalidFormat || error == .invalidMagicNumber {
                    handleNATSEvent(payload: subData)
                } else {
                    handleParsingError(error)
                }
            } catch {
                print("Unexpected 0x06 error: \(error.localizedDescription)")
            }
        default:
            print("Unknown message type: \(messageType.base64EncodedString())")
        }
    }

    // FIXME: add to handle rewrap - handleNATSEvent(payload: payload)

    private func handleNATSEvent(payload: Data) {
        print("Received NATS event: \(payload.base64EncodedString())")
        var bb = ByteBuffer(data: payload)
        let rootOffset = bb.read(def: Int32.self, position: 0)
        do {
            var verifier = try Verifier(buffer: &bb)
            try Arkavo_Event.verify(&verifier, at: Int(rootOffset), of: Arkavo_Event.self)
            print("The bytes represent a valid Arkavo_Event")
        } catch {
            print("Verification failed: \(error)")
            return
        }
        let event = Arkavo_Event(bb, o: Int32(Int(rootOffset)))
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
            if event.status == .fulfilled,
               let routeEvent = event.data(type: Arkavo_RouteEvent.self)
            {
                print("Route Event: fulfilled")
                if let streamService {
                    streamService.handleRouteEventFulfilled(routeEvent)
                }
                return
            }
            if event.status == .preparing,
               let routeEvent = event.data(type: Arkavo_RouteEvent.self)
            {
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
        print("  Source ID: \(Data(routeEvent.sourceId).base58EncodedString)")
        print("  Attribute Type: \(routeEvent.attributeType)")
        switch routeEvent.attributeType {
        case .unused:
            print("handleRouteEvent unused")
        case .location:
            print("handleRouteEvent location")
            // Check if we have permission to access location
            if let status = locationManager.locationStatus {
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    // We have permission
                    print("Location access is allowed")
                    Task {
                        do {
                            let locationData = try await locationManager.requestLocationAsync()
                            // TODO: use flatbuffers
                            let jsonEncoder = JSONEncoder()
                            let jsonData = try jsonEncoder.encode(locationData)
                            print("Location: \(String(decoding: jsonData, as: UTF8.self))")
                            // FIXME: add to encrypted metadata of nanotdf
                            // Create new RouteEvent, switch source and target, add jsonData as payload
                            // Create a new RouteEvent
                            var builder = FlatBufferBuilder()
                            // Create the payload (location data)
                            let payloadVector = builder.createVector(bytes: jsonData)
                            // Switch source and target
                            let sourceIdVector = builder.createVector(routeEvent.targetId)
                            let targetIdVector = builder.createVector(routeEvent.sourceId)
                            let routeEventOffset = Arkavo_RouteEvent.createRouteEvent(
                                &builder,
                                targetType: .accountProfile,
                                targetIdVectorOffset: targetIdVector,
                                sourceType: .accountProfile,
                                sourceIdVectorOffset: sourceIdVector,
                                attributeType: .location,
                                entityType: .unused,
                                payloadVectorOffset: payloadVector
                            )
//                            print("Debug: Created RouteEvent, offset: \(routeEventOffset)")
                            // Create Event
                            let eventOffset = Arkavo_Event.createEvent(
                                &builder,
                                action: .share,
                                timestamp: UInt64(Date().timeIntervalSince1970),
                                status: .fulfilled,
                                dataType: .routeevent,
                                dataOffset: routeEventOffset
                            )
//                            print("Debug: Created Event, offset: \(eventOffset)")
                            builder.finish(offset: eventOffset)
                            // Get the bytes of the FlatBuffer
//                            print("Debug: Finished builder")
                            let buffer = builder.sizedBuffer
//                            print("Debug: Got sized buffer, size: \(buffer.size), capacity: \(buffer.capacity)")
                            // Convert ByteBuffer to Data for base64 encoding and sending
                            let data = Data(bytes: buffer.memory.advanced(by: buffer.reader), count: Int(buffer.size))
                            // Send the event
                            try self.sendEvent(data)
                            print("Sent location RouteEvent")
                        } catch {
                            print("Error getting location: \(error)")
                        }
                    }
                case .denied, .restricted:
                    print("Location access is denied or restricted")
                // Handle lack of permission
                case .notDetermined:
                    print("Location permission not determined")
                    locationManager.requestLocation()
                @unknown default:
                    print("Unknown location authorization status")
                }
            } else {
                print("Location status is not available")
                locationManager.requestLocation()
            }
        case .time:
            print("  Attribute Value: \(routeEvent.attributeType)")
        }
    }

    private func handleUserEvent(_ userEvent: Arkavo_UserEvent) {
        print("User Event:")
        print("  Source Type: \(userEvent.sourceType)")
        print("  Target Type: \(userEvent.targetType)")
        print("  Source ID: \(Data(userEvent.sourceId).base58EncodedString)")
        print("  Target ID: \(Data(userEvent.targetId).base58EncodedString)")
        // Add any additional processing for user events here
    }

    private func handleCacheEvent(_ cacheEvent: Arkavo_CacheEvent) {
        print("Cache Event:")
        print("  Target ID: \(Data(cacheEvent.targetId).base58EncodedString)")
        print("  TTL: \(cacheEvent.ttl)")
        print("  One-Time Access: \(cacheEvent.oneTimeAccess)")
        // Add any additional processing for cache events here
    }

    func sendRewrapNanoTDF(nano: NanoTDF) {
        let id = nano.header.ephemeralPublicKey

        // First quickly send the rewrap message
        webSocketManager.sendRewrapMessage(header: nano.header)

        // Then start async processing
        Task {
            do {
                // Wait for symmetric key without blocking other operations
                if let symmetricKey = try await nanoTDFManager.processNanoTDF(nano, withIdentifier: id) {
                    // Process in background
                    Task.detached(priority: .background) {
                        do {
                            let payload = try await nano.getPayloadPlaintext(symmetricKey: symmetricKey)
                            let policy = ArkavoPolicy(nano.header.policy)

                            // Handle different policy types
                            switch policy.type {
                            case .accountProfile:
                                await self.handleAccountProfile(payload: payload, policy: policy, nano: nano)
                            case .streamProfile:
                                await self.handleStreamProfile(payload: payload, policy: policy, nano: nano)
                            case .thought:
                                await self.handleThought(payload: payload, policy: policy, nano: nano)
                            case .videoFrame:
                                await self.handleVideoFrame(payload: payload)
                            }
                        } catch {
                            print("Error processing payload: \(error)")
                        }
                    }
                }
            } catch {
                print("Error processing NanoTDF: \(error)")
            }
        }
    }

    func handleRewrapCallback(id: Data?, symmetricKey: SymmetricKey?) {
        guard let id else {
            print("missing id")
            return
        }
        nanoTDFManager.completeProcessing(forIdentifier: id, withKey: symmetricKey)
    }

    private func handleAccountProfile(payload: Data, policy: ArkavoPolicy, nano: NanoTDF) async {
        // FIXME: content signature is hacked in to here
        guard let protectorService else {
            print("Protector service is not initialized")
            return
        }
        do {
            try await protectorService.handle(payload, policy: policy, nano: nano)
        } catch {
            print("Error handling account profile: \(error)")
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

class NanoTDFManager {
    private var nanoTDFs: [Data: (NanoTDF, CheckedContinuation<SymmetricKey?, Error>)] = [:]
    private let queue = DispatchQueue(label: "com.arkavo.nanotdf-manager", attributes: .concurrent)

    func processNanoTDF(_ nanoTDF: NanoTDF, withIdentifier identifier: Data) async throws -> SymmetricKey? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async(flags: .barrier) { [weak self] in
                guard let self else {
                    continuation.resume(throwing: NSError(domain: "NanoTDFManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Manager deallocated"]))
                    return
                }
                nanoTDFs[identifier] = (nanoTDF, continuation)
            }
        }
    }

    func completeProcessing(forIdentifier identifier: Data, withKey symmetricKey: SymmetricKey?) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self,
                  let (_, continuation) = nanoTDFs.removeValue(forKey: identifier)
            else {
                return
            }
            continuation.resume(returning: symmetricKey)
        }
    }

    func getNanoTDF(withIdentifier identifier: Data) -> NanoTDF? {
        queue.sync {
            nanoTDFs[identifier]?.0
        }
    }
}

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
