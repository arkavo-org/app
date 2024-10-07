import CryptoKit
import Foundation
import OpenTDFKit

// for transmission, serializes to payload
struct ThoughtServiceModel: Codable {
    var publicID: Data
    var creatorID: UUID
    var mediaType: MediaType
    var content: Data

    init(creatorID: UUID, mediaType: MediaType, content: Data) {
        self.creatorID = creatorID
        self.mediaType = mediaType
        self.content = content
        let hashData = creatorID.uuidString.data(using: .utf8)! + mediaType.rawValue.data(using: .utf8)! + content
        publicID = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }
}

extension ThoughtServiceModel {
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
        try ThoughtServiceModel.encoder.encode(self)
    }

    static func deserialize(from data: Data) throws -> ThoughtServiceModel {
        try decoder.decode(ThoughtServiceModel.self, from: data)
    }
}

class ThoughtService {
    private let service: ArkavoService
    public var streamViewModel: StreamViewModel?
    weak var thoughtStreamViewModel: ThoughtStreamViewModel?

    init(_ service: ArkavoService) {
        self.service = service
    }

    func createNano(_ viewModel: ThoughtViewModel, stream _: Stream) throws -> Data {
        guard let kasPublicKey = ArkavoService.kasPublicKey else {
            print("KAS public key not available")
            return Data()
        }
        // TODO: Create policy based on stream

        // TODO: Create thought payload
        let payload = try createPayload(viewModel: viewModel)

        // Create a NanoTDF
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        // smart contract
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "5GnJAVumy3NBdo2u9ZEK1MQAXdiVnZWzzso4diP2JszVgSJQ")!
        // FIXME: use stream to determine metadata and abac
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)

        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: payload)
        return nanoTDF.toData()
    }

    func createPayload(viewModel: ThoughtViewModel) throws -> Data {
        // TODO: replace with Flatbuffers
        let thoughtServiceModel = ThoughtServiceModel(creatorID: viewModel.creator.id, mediaType: viewModel.mediaType, content: viewModel.content)
        let payload = try thoughtServiceModel.serialize()
        return payload
    }

    func send(viewModel: ThoughtViewModel, stream: Stream) async {
        do {
            let nano = try createNano(viewModel, stream: stream)
            // persist
            // FIXME: always fails on unique constraint
//            let thought = Thought(id: UUID(), nano: nano)
//            thought.stream = stream
//            stream.thoughts.append(thought)
//            try await PersistenceController.shared.saveChanges()
            // send
            try sendThought(nano)
        } catch {
            print("error sending thought: \(error.localizedDescription)")
        }
    }

    func loadAndDecrypt(for stream: Stream) {
        for thought in stream.thoughts {
            do {
                try sendThought(thought.nano)
            } catch {
                print("sendThought error: \(error)")
            }
        }
    }

    func sendThought(_ nano: Data) throws {
        // Create and send the NATSMessage
        let natsMessage = NATSMessage(payload: nano)
        let messageData = natsMessage.toData()
//            print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

        WebSocketManager.shared.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending thought: \(error)")
            }
        }
    }

    @MainActor func handle(_ decryptedData: Data, policy: ArkavoPolicy, nano: NanoTDF) async throws {
        guard let thoughtStreamViewModel else {
            throw ThoughtServiceError.missingThoughtStreamViewModel
        }
        try await thoughtStreamViewModel.handle(decryptedData, policy: policy, nano: nano)
    }

    enum ThoughtServiceError: Error {
        case missingThoughtStreamViewModel
    }
}
