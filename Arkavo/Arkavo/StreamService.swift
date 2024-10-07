import CryptoKit
import FlatBuffers
import Foundation
import OpenTDFKit
import SwiftData

struct StreamServiceModel {
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
    var publicIDString: String {
        publicID.base58EncodedString
    }
}

class StreamService {
    let service: ArkavoService
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
        guard let stream = viewModel.stream else {
            throw StreamServiceError.missingAccountOrProfile
        }
        let streamServiceModel = StreamServiceModel(stream: stream)
        // FIXME: add flatbuffers
//        let payload = try streamServiceModel.serialize()
//        return payload
        return Data()
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
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let accountProfile = account.profile
        let streams = try await PersistenceController.shared.fetchStream(withPublicID: publicID)
        guard let accountProfilePublicID = accountProfile?.publicID
        else {
            throw StreamServiceError.missingAccountOrProfile
        }
        let stream = streams?.first
        if let stream {
            print("Found stream: \(stream)")
            return stream
        }
        print("No stream found with publicID: \(publicID)")
        // Create FlatBuffer
        var builder = FlatBufferBuilder(initialSize: 384)
        // Create the UserEvent object
        let userEventOffset = Arkavo_UserEvent.createUserEvent(
            &builder,
            sourceType: .accountProfile,
            targetType: .streamProfile,
            sourceIdVectorOffset: builder.createVector(bytes: accountProfilePublicID),
            targetIdVectorOffset: builder.createVector(bytes: publicID)
        )
        // Create the Event object
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .invite,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .userevent,
            dataOffset: userEventOffset
        )
        builder.finish(offset: eventOffset)
        let data = builder.data
        print("inviteEvent: \(data.base64EncodedString())")
        try sendEvent(data)
        return nil
    }

    @MainActor func handle(_: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async throws {
//        _ = try StreamServiceModel.deserialize(from: decryptedData)
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
