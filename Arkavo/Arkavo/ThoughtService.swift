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
    private let webSocketManager: WebSocketManager
    private let nanoTDFManager: NanoTDFManager
    var thoughtStreamViewModel: ThoughtStreamViewModel?
    // FIXME: get from provider or singleton
    var kasPublicKey: P256.KeyAgreement.PublicKey?

    init(nanoTDFManager: NanoTDFManager, webSocketManager: WebSocketManager) {
        self.nanoTDFManager = nanoTDFManager
        self.webSocketManager = webSocketManager
    }

    func handleIncomingThought(data: Data) async {
        // Assuming the incoming data is a NATSMessage
//        print("NATS message received: \(data.base64EncodedString())")
//        print("NATS payload size: \(data.count)")
        do {
            // FIXME: copy of data after first byte
            let subData = data.subdata(in: 1 ..< data.count)
            // Create a NanoTDF from the payload
            let parser = BinaryParser(data: subData)
            let header = try parser.parseHeader()
            let payload = try parser.parsePayload(config: header.payloadSignatureConfig)
            let nanoTDF = NanoTDF(header: header, payload: payload, signature: nil)
            // Use the nanoTDFManager to handle the incoming NanoTDF
            let id = nanoTDF.header.ephemeralPublicKey
//            print("ephemeralPublicKey: \(id.base64EncodedString())")
            nanoTDFManager.addNanoTDF(nanoTDF, withIdentifier: id)
            webSocketManager.sendRewrapMessage(header: nanoTDF.header)
        } catch let error as ParsingError {
            handleParsingError(error)
        } catch {
            print("Unexpected error: \(error.localizedDescription)")
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

    func createNano(_ viewModel: ThoughtViewModel, stream _: Stream) throws -> Data {
        guard let kasPublicKey else {
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
        let contentData = viewModel.content.data(using: .utf8) ?? Data()
        let thoughtServiceModel = ThoughtServiceModel(creatorId: viewModel.creator.id, mediaType: viewModel.mediaType, content: contentData)
        let payload = try thoughtServiceModel.serialize()
        return payload
    }

    func sendThought(_ nano: Data) throws {
        // Create and send the NATSMessage
        let natsMessage = NATSMessage(payload: nano)
        let messageData = natsMessage.toData()
//            print("NATS message payload sent: \(natsMessage.payload.base64EncodedString())")

        webSocketManager.sendCustomMessage(messageData) { error in
            if let error {
                print("Error sending thought: \(error)")
            }
        }
    }

    /// Reconstructs a Thought object from unencrypted Data.
    /// - Parameter thought: The Thought object containing encrypted data.
    /// - Returns: A reconstructed Thought object, or nil if decryption fails.
    func handle(_ decryptedData: Data, policy _: ArkavoPolicy, nano: Data) throws {
        let thought = try Thought.deserialize(from: decryptedData)
        thought.nano = nano
        DispatchQueue.main.async {
            // FIXME: Update the ThoughtStreamView
            self.thoughtStreamViewModel!.receiveThought(thought)
        }
    }

//
//    // MARK: - Properties
//    private var allThoughts: [Thought] = []
//    private var displayedThoughts: [Thought] = []
//
//    // Simulated server or data source containing all thoughts
//    private var thoughtDataSource: [Thought] = []
//
//    // Number of thoughts to load per page
//    private let pageSize = 20
//
//    // MARK: - Initialization
//    init(thoughts: [Thought]) {
//        // FIXME Initialize with an array of thoughts (e.g., from a server or database)
    ////        self.allThoughts = thoughts.sorted { $0.creationDate > $1.creationDate }
//        self.thoughtDataSource = self.allThoughts
//    }
//
//    // MARK: - Public Methods
//
//    /// Fetches the next page of thoughts based on the current scroll position.
//    func fetchNextPageOfThoughts(completion: @escaping ([Thought]) -> Void) {
//        guard !thoughtDataSource.isEmpty else {
//            completion([])
//            return
//        }
//
//        // Determine the range of thoughts to fetch
//        let startIndex = max(0, displayedThoughts.count)
//        let endIndex = min(startIndex + pageSize, thoughtDataSource.count)
//
//        // Extract the next page of thoughts
//        let nextPage = Array(thoughtDataSource[startIndex..<endIndex])
//
//        // Append to the displayed thoughts and remove from the data source
//        displayedThoughts.append(contentsOf: nextPage)
//
//        // Simulate the decryption and reconstruction process
//        var decryptedThoughts: [Thought] = []
//
//        for thought in nextPage {
//            if let decryptedThought = decryptAndReconstructThought(thought) {
//                decryptedThoughts.append(decryptedThought)
//            }
//        }
//
//        completion(decryptedThoughts)
//    }
//
//
//    // MARK: - Private Methods
//
//    /// Decrypts NanoTDF encrypted data.
//    /// - Parameter data: The encrypted data.
//    /// - Returns: The decrypted data, or nil if decryption fails.
//    private func decryptNanoTDF(_ data: Data) -> Data? {
//        // Implement NanoTDF decryption logic here
//        // Replace this with the actual decryption code
//        // For now, return the original data as a placeholder
//        return data
//    }
//
//    /// Extracts metadata from the decrypted thought data.
//    /// - Parameter data: The decrypted data.
//    /// - Returns: The extracted metadata.
//    private func extractMetadata(from data: Data) -> ThoughtMetadata? {
//        // Implement metadata extraction logic here
//        // This could involve parsing JSON or another format
//        // Return a ThoughtMetadata object
//        return ThoughtMetadata() // Placeholder for the extracted metadata
//    }
//
//    // MARK: - DataSource Management
//
//    /// Updates the thought data source. Useful when new thoughts are added to the Stream.
//    func updateThoughts(thoughts: [Thought]) {
//        self.allThoughts = thoughts.sorted { $0.creationDate > $1.creationDate }
//        self.thoughtDataSource = self.allThoughts
//    }
}
