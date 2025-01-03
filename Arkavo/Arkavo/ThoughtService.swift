// import CryptoKit
// import FlatBuffers
// import Foundation
// import OpenTDFKit
//

//

//
// class ThoughtService {
//    private let service: ArkavoService
//    public var streamViewModel: StreamViewModel?
//    weak var thoughtStreamViewModel: ThoughtStreamViewModel?
//
//    init(_ service: ArkavoService) {
//        self.service = service
//    }
//
//    func createNano(_ viewModel: ThoughtViewModel, stream: Stream) async throws -> Data {
//        guard let kasPublicKey = ArkavoService.kasPublicKey else {
//            print("KAS public key not available")
//            return Data()
//        }
//        // TODO: Create policy based on stream
//        // FIXME: use stream to determine metadata and abac
//        var builder = FlatBufferBuilder()
//        // Create format info strings
//        let formatVersionString = builder.create(string: "1.0")
//        let formatProfileString = builder.create(string: "standard")
//        // Create format info
//        let formatInfo = Arkavo_FormatInfo.createFormatInfo(
//            &builder,
//            type: .plain,
//            versionOffset: formatVersionString,
//            profileOffset: formatProfileString
//        )
//        // Create content format
//        let contentFormat = Arkavo_ContentFormat.createContentFormat(
//            &builder,
//            mediaType: .text,
//            dataEncoding: .utf8,
//            formatOffset: formatInfo
//        )
//        // Create rating
//        let rating: Offset = switch stream.policies.age {
//        case .onlyAdults:
//            Arkavo_Rating.createRating(
//                &builder,
//                violent: .severe,
//                sexual: .severe,
//                profane: .severe,
//                substance: .severe,
//                hate: .severe,
//                harm: .severe,
//                mature: .severe,
//                bully: .severe
//            )
//        case .onlyKids:
//            Arkavo_Rating.createRating(
//                &builder,
//                violent: .mild,
//                sexual: .none_,
//                profane: .none_,
//                substance: .none_,
//                hate: .none_,
//                harm: .none_,
//                mature: .none_,
//                bully: .none_
//            )
//        case .forAll:
//            Arkavo_Rating.createRating(
//                &builder,
//                violent: .mild,
//                sexual: .mild,
//                profane: .mild,
//                substance: .none_,
//                hate: .none_,
//                harm: .none_,
//                mature: .mild,
//                bully: .none_
//            )
//        case .onlyTeens:
//            Arkavo_Rating.createRating(
//                &builder,
//                violent: .mild,
//                sexual: .none_,
//                profane: .none_,
//                substance: .none_,
//                hate: .none_,
//                harm: .none_,
//                mature: .none_,
//                bully: .none_
//            )
//        }
//        // Create purpose
//        let purpose = Arkavo_Purpose.createPurpose(
//            &builder,
//            educational: 0.8,
//            entertainment: 0.2,
//            news: 0.0,
//            promotional: 0.0,
//            personal: 0.0,
//            opinion: 0.1,
//            transactional: 0.0,
//            harmful: 0.0,
//            confidence: 0.9
//        )
//        // Create ID and related arrays (256-bit)
//        let idVector = builder.createVector(bytes: stream.publicID) // FIXME: thought.publicID
//        let relatedVector = builder.createVector(bytes: stream.publicID)
//        // Create topics array
//        let topics: [UInt32] = [1, 2, 3]
//        let topicsVector = builder.createVector(topics)
//        // Create the root metadata table
//        let metadata = Arkavo_Metadata.createMetadata(
//            &builder,
//            created: Int64(Date().timeIntervalSince1970),
//            idVectorOffset: idVector,
//            relatedVectorOffset: relatedVector,
//            ratingOffset: rating,
//            purposeOffset: purpose,
//            topicsVectorOffset: topicsVector,
//            contentOffset: contentFormat
//        )
//        builder.finish(offset: metadata)
//        var buffer = builder.sizedBuffer
//        do {
//            print("Debug: Starting FlatBuffer verification")
//            let rootOffset = buffer.read(def: Int32.self, position: 0)
//            var verifier = try Verifier(buffer: &buffer)
//            try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)
//            print("Arkavo_Metadata FlatBuffer verification passed")
//        } catch {
//            print("Arkavo_Metadata FlatBuffer verification failed: \(error)")
//            throw error // or handle the error as appropriate for your application
//        }
//        let policyBody = Data(bytes: buffer.memory.advanced(by: buffer.reader), count: Int(buffer.size))
//        print("policyBody: \(policyBody.base64EncodedString())")
//        let policyEmbedded = EmbeddedPolicyBody(body: policyBody)
//        var policy = Policy(type: .embeddedPlaintext, body: policyEmbedded, remote: nil, binding: nil)
//        // Create thought payload
//        let payload = try createPayload(viewModel: viewModel)
//        // Create a NanoTDF
//        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
//        let kasMetadata = try KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
//        let nanoTDF = try await createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: payload)
//        print("nanoTDF: \(nanoTDF.toData().base64EncodedString())")
//        return nanoTDF.toData()
//    }
//
//    func createPayload(viewModel: ThoughtViewModel) throws -> Data {
//        // TODO: replace with Flatbuffers
//        let streamPublicID = Base58.decode(viewModel.streamPublicIDString)
//        let thoughtServiceModel = ThoughtServiceModel(creatorPublicID: viewModel.creator.publicID, streamPublicID: Data(streamPublicID!), mediaType: viewModel.mediaType, content: viewModel.content)
//        let payload = try thoughtServiceModel.serialize()
//        return payload
//    }
//
//    func send(viewModel: ThoughtViewModel, stream: Stream) async {
//        do {
//            let nano = try await createNano(viewModel, stream: stream)
//            // persist
//            // FIXME: always fails on unique constraint
////            let thought = Thought(id: UUID(), nano: nano)
////            thought.stream = stream
////            stream.thoughts.append(thought)
////            try await PersistenceController.shared.saveChanges()
//            // send
//            try sendThought(nano)
//        } catch {
//            print("error sending thought: \(error.localizedDescription)")
//        }
//    }
//
//    func loadAndDecrypt(for stream: Stream) {
//        for thought in stream.thoughts {
//            do {
//                try sendThought(thought.nano)
//            } catch {
//                print("sendThought error: \(error)")
//            }
//        }
//    }
//
//    func sendThought(_ nano: Data) throws {
//        // Create and send the NATSMessage
//        let natsMessage = NATSMessage(payload: nano)
//        let messageData = natsMessage.toData()
////            print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")
//
//        WebSocketManager.shared.sendCustomMessage(messageData) { error in
//            if let error {
//                print("Error sending thought: \(error)")
//            }
//        }
//    }
//
//    @MainActor func handle(_ decryptedData: Data, policy: ArkavoPolicy, nano: NanoTDF) async throws {
//        guard let thoughtStreamViewModel else {
//            throw ThoughtServiceError.missingThoughtStreamViewModel
//        }
//        try await thoughtStreamViewModel.handle(decryptedData, policy: policy, nano: nano)
//    }
//
//    enum ThoughtServiceError: Error {
//        case missingThoughtStreamViewModel
//    }
// }
