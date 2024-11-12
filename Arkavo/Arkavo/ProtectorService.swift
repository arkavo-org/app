import FlatBuffers
import Foundation
import OpenTDFKit

class ProtectorService {
    let service: ArkavoService

    init(_ service: ArkavoService) {
        self.service = service
    }

    func sendContentSignatureEvent(_ signature: Data, creatorPublicID: Data) throws {
        guard let kasPublicKey = ArkavoService.kasPublicKey else {
            throw ServiceError.missingKASkey
        }
        // Create Nano
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.streamProfile.rawValue)!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: signature)
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
}

enum ServiceError: Error {
    case missingAccountOrProfile
    case missingKASkey
    case flatBufferCreationFailed
    case missingRequiredFields
    case serviceNotInitialized
}
