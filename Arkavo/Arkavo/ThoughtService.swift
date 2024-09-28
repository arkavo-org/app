import CryptoKit
import Foundation
import OpenTDFKit

// for transmission, serializes to payload
struct ThoughtServiceModel: Codable {
    var publicId: Data
    var creatorId: UUID
    var mediaType: MediaType
    var content: Data

    init(creatorId: UUID, mediaType: MediaType, content: Data) {
        self.creatorId = creatorId
        self.mediaType = mediaType
        self.content = content
        let hashData = creatorId.uuidString.data(using: .utf8)! + mediaType.rawValue.data(using: .utf8)! + content
        publicId = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }
}

extension ThoughtServiceModel {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    var publicIdString: String {
        publicId.map { String(format: "%02x", $0) }.joined()
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
        let thoughtServiceModel = ThoughtServiceModel(creatorId: viewModel.creator.id, mediaType: viewModel.mediaType, content: viewModel.content)
        let payload = try thoughtServiceModel.serialize()
        return payload
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

    /// Reconstructs a Thought object from unencrypted Data.
    /// - Parameter thought: The Thought object containing encrypted data.
    /// - Returns: A reconstructed Thought object, or nil if decryption fails.
    @MainActor func handle(_ decryptedData: Data, policy _: ArkavoPolicy, nano: NanoTDF) async throws {
        guard let thoughtStreamViewModel = streamViewModel?.thoughtStreamViewModel else {
            throw ThoughtServiceError.missingThoughtStreamViewModel
        }
        // FIXME: dedupe
        let thoughtServiceModel = try ThoughtServiceModel.deserialize(from: decryptedData)
        // don't process if creator
        if streamViewModel?.accountProfile?.id == thoughtServiceModel.creatorId {
//            print("Ignoring thought from self")
            return
        }
        // persist
        let thought = Thought(nano: nano.toData())
        thought.publicId = thoughtServiceModel.publicId
        thought.nano = nano.toData()
        thought.stream = streamViewModel?.thoughtStreamViewModel.stream
        PersistenceController.shared.container.mainContext.insert(thought)
        streamViewModel?.thoughtStreamViewModel.stream?.thoughts.append(thought)
        try await PersistenceController.shared.saveChanges()
        // show
        thoughtStreamViewModel.receive(thoughtServiceModel)
    }

    enum ThoughtServiceError: Error {
        case missingThoughtStreamViewModel
    }
}
