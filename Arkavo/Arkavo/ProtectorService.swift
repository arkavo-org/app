import FlatBuffers
import Foundation
import OpenTDFKit

class ProtectorService {
    let service: ArkavoService
    private var signatureReceivedContinuation: CheckedContinuation<ContentSignature, Error>?
    private var receivedSignature: ContentSignature?

    init(_ service: ArkavoService) {
        self.service = service
    }

    func sendContentSignatureEvent(_ signature: ContentSignature, creatorPublicID: Data) async throws {
        guard let kasPublicKey = ArkavoService.kasPublicKey else {
            throw ProtectorError.missingKASkey
        }
        let compressed = try signature.compressed()
        print("Sending Content signature compressed: \(compressed)")
        print("Creator public ID: \(creatorPublicID.base58EncodedString)")
        // Create Nano
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = try KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        // FIXME: fix this hack - accountProfile is being used for content signature
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.accountProfile.rawValue)!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
        let nanoTDF = try await createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: compressed)
        let targetPayload = nanoTDF.toData()
        // Create CacheEvent
        var builder = FlatBufferBuilder(initialSize: 12000)
        let targetIdVector = builder.createVector(bytes: creatorPublicID)
        let targetPayloadVector = builder.createVector(bytes: targetPayload)
        let cacheEventOffset = Arkavo_CacheEvent.createCacheEvent(
            &builder,
            targetIdVectorOffset: targetIdVector,
            targetPayloadVectorOffset: targetPayloadVector,
            ttl: 3600, // 1 hour TTL
            oneTimeAccess: false
        )
        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .cache,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .cacheevent,
            dataOffset: cacheEventOffset
        )
        builder.finish(offset: eventOffset)
        let buffer = builder.sizedBuffer
        let data = Data(bytes: buffer.memory.advanced(by: buffer.reader), count: Int(buffer.size))
//        print("Content signature cache event: \(data.base64EncodedString())")
        try service.sendEvent(data)
    }

    @MainActor
    public func requestContentSignature(withPublicID publicID: Data) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let accountProfile = account.profile
        guard let accountProfilePublicID = accountProfile?.publicID
        else {
            throw ProtectorError.missingAccountOrProfile
        }
        print("Content creator: \(publicID.base58EncodedString)")
        // Create FlatBuffer
        var builder = FlatBufferBuilder(initialSize: 384)
        // Create the UserEvent object
        let userEventOffset = Arkavo_UserEvent.createUserEvent(
            &builder,
            sourceType: .accountProfile,
            targetType: .streamProfile, // FIXME: add content signature
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
        print("Content invite event: \(data.base64EncodedString())")
        try service.sendEvent(data)
    }

    func waitForSignature() async throws -> ContentSignature {
        // If we already have a signature, return it immediately
        if let signature = receivedSignature {
            return signature
        }

        // Otherwise wait for the signature to be received
        return try await withCheckedThrowingContinuation { continuation in
            signatureReceivedContinuation = continuation
        }
    }

    @MainActor
    func handle(_ data: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async throws {
        print("Receiving Content signature data: \(data)")
        let decompressed = try ContentSignature.decompress(data)
//        print("Decompressed: \(decompressed)")

        // Store the signature
        receivedSignature = decompressed

        // Complete the continuation if someone is waiting
        if let continuation = signatureReceivedContinuation {
            continuation.resume(returning: decompressed)
            signatureReceivedContinuation = nil
        }
    }

    func clearSignature() {
        receivedSignature = nil
        signatureReceivedContinuation = nil
    }
}

enum ProtectorError: Error {
    case missingAccountOrProfile
    case missingKASkey
    case flatBufferCreationFailed
    case missingRequiredFields
    case serviceNotInitialized
    case invalidEntityType
    case missingProfile
    case missingCreatorPublicId
    case missingPublicId
}
