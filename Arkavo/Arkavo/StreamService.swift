import CryptoKit
import FlatBuffers
import Foundation
import OpenTDFKit
import SwiftData

struct StreamServiceModel: Codable {
    var publicID: Data
    var streamProfile: Profile
    var admissionPolicy: AdmissionPolicy
    var interactionPolicy: InteractionPolicy

    init(stream: Stream) {
        publicID = stream.publicID
        streamProfile = stream.profile
        admissionPolicy = .open
        interactionPolicy = .open
    }
}

extension StreamServiceModel {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    var publicIDString: String {
        publicID.base58EncodedString
    }

    func serialize() throws -> Data {
        try StreamServiceModel.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> StreamServiceModel {
        try decoder.decode(StreamServiceModel.self, from: data)
    }
}

class StreamService {
    private let service: ArkavoService
    public var streamViewModel: StreamViewModel?

    init(_ service: ArkavoService) {
        self.service = service
    }

    @MainActor func createStream(_ viewModel: StreamViewModel) throws -> Data {
        guard let kasPublicKey = ArkavoService.kasPublicKey else {
            print("KAS public key not available")
            return Data()
        }

        let payload = try createPayload(viewModel: viewModel)

        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: payload)
        return nanoTDF.toData()
    }

    @MainActor func createPayload(viewModel: StreamViewModel) throws -> Data {
        guard let stream = viewModel.thoughtStreamViewModel.stream else {
            throw StreamServiceError.missingAccountOrProfile
        }
        let streamServiceModel = StreamServiceModel(stream: stream)
        let payload = try streamServiceModel.serialize()
        return payload
    }

    func sendStream(_ nano: Data) throws {
        let natsMessage = NATSMessage(payload: nano)
        let messageData = natsMessage.toData()

        WebSocketManager.shared.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending stream: \(error)")
            }
        }
    }

    func sendEvent(_ payload: Data) throws {
        let natsMessage = NATSEvent(payload: payload)
        let messageData = natsMessage.toData()
        print("Sending event: \(messageData)")
        WebSocketManager.shared.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending stream: \(error)")
            }
        }
    }

    @MainActor
    public func fetchStream(withPublicID publicID: Data) async throws -> Stream? {
        let streams = try await PersistenceController.shared.fetchStream(withPublicID: publicID)
        let stream = streams?.first
        if stream == nil {
            print("No stream found with publicID: \(publicID)")
            // get stream
            var builder = FlatBufferBuilder(initialSize: 1024)
            // Create string offsets
            let targetIdVector = builder.createVector(bytes: publicID)
            let sourcePublicID: [UInt8] = [1, 2, 3, 4, 5] // Example byte array for sourcePublicID
            let sourcePublicIDOffset = builder.createVector(sourcePublicID)
            // Create the Event object in the FlatBuffer
            let action = Arkavo_UserEvent.createUserEvent(
                &builder,
                sourceType: .accountProfile,
                targetType: .streamProfile,
                sourceIdVectorOffset: sourcePublicIDOffset,
                targetIdVectorOffset: targetIdVector
            )
            // Create the Event object
            let eventOffset = Arkavo_Event.createEvent(
                &builder,
                action: .invite,
                timestamp: UInt64(Date().timeIntervalSince1970),
                status: .preparing,
                dataType: .userevent,
                dataOffset: action
            )
            builder.finish(offset: eventOffset)
            let serializedEvent = builder.data
            print("streamInvite: \(builder.data.base64EncodedString())")
            try sendEvent(serializedEvent)
        }
        return stream
    }

    @MainActor func handle(_ decryptedData: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async throws {
        _ = try StreamServiceModel.deserialize(from: decryptedData)
        // TODO: implement
//        // Check if the stream already exists
//        if let existingStream = try await fetchExistingStream(publicID: streamServiceModel.publicID) {
//            // Update existing stream
        ////            try await updateExistingStream(existingStream, with: streamServiceModel, policy: policy, nano: nano)
//        } else {
//            // Create new stream
        ////            try await createNewStream(from: streamServiceModel, policy: policy, nano: nano)
//        }
    }

    enum StreamServiceError: Error {
        case missingAccountOrProfile
    }
}
