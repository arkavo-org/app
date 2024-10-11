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

    func sendStreamEvent(_ stream: Stream) throws {
        guard let kasPublicKey = ArkavoService.kasPublicKey else {
            throw StreamServiceError.missingKASkey
        }
        // Create Stream using FlatBuffers
        var builder = FlatBufferBuilder(initialSize: 1024)
        // Create nested structures first
        let nameOffset = builder.create(string: stream.profile.name)
        let blurbOffset = builder.create(string: stream.profile.blurb ?? "")
        let interestsOffset = builder.create(string: stream.profile.interests)
        let locationOffset = builder.create(string: stream.profile.location)
        // Create Profile
        let profileOffset = Arkavo_Profile.createProfile(
            &builder,
            nameOffset: nameOffset,
            blurbOffset: blurbOffset,
            interestsOffset: interestsOffset,
            locationOffset: locationOffset,
            locationLevel: .approximate,
            identityAssuranceLevel: stream.profile.hasHighIdentityAssurance ? .ial2 : .ial1,
            encryptionLevel: stream.profile.hasHighEncryption ? .el2 : .el1
        )
        // Create Activity
        let activityOffset = createDefaultActivity(&builder)
        // Create PublicIds
        let publicIdVector = builder.createVector(bytes: stream.publicID)
        let publicIdOffset = Arkavo_PublicId.createPublicId(&builder, idVectorOffset: publicIdVector)
        let creatorPublicIdVector = builder.createVector(bytes: stream.creatorPublicID)
        let creatorPublicIdOffset = Arkavo_PublicId.createPublicId(&builder, idVectorOffset: creatorPublicIdVector)
        // Create Stream
        let streamOffset = Arkavo_Stream.createStream(
            &builder,
            publicIdOffset: publicIdOffset,
            profileOffset: profileOffset,
            activityOffset: activityOffset,
            creatorPublicIdOffset: creatorPublicIdOffset,
            membersPublicIdVectorOffset: Offset(),
            streamLevel: .sl1
        )
        // Create EntityRoot with Stream as the entity
        let entityRootOffset = Arkavo_EntityRoot.createEntityRoot(
            &builder,
            entityType: .stream,
            entityOffset: streamOffset
        )
        builder.finish(offset: entityRootOffset)
        // BEGIN ***** debug
//        let payload = builder.sizedByteArray
//        print("Payload size: \(payload.count) bytes")
//        do {
//            var buffer = ByteBuffer(bytes: payload)
//            print("Buffer size: \(buffer.size)")
//            print("Buffer capacity: \(buffer.capacity)")
//            // Read and print the root table offset
//            let rootOffset = buffer.read(def: Int32.self, position: 0)
//            print("Root table offset: \(rootOffset)")
//            var verifier = try Verifier(buffer: &buffer)
//            try Arkavo_EntityRoot.verify(&verifier, at: Int(rootOffset), of: Arkavo_EntityRoot.self)
//            print("Verification successful")
//            // Access the EntityRoot
//            let entityRoot = Arkavo_EntityRoot(buffer, o: Int32(rootOffset))
//            print("entityRoot type: \(entityRoot.entityType)")
//            // Access the Stream through EntityRoot
//            if let arkStream = entityRoot.entity(type: Arkavo_Stream.self) {
//                print("Successfully accessed Stream through EntityRoot")
//                // Debug PublicId
//                if let publicId = arkStream.publicId {
//                    print("Stream public ID: \(publicId.id.map { String(format: "%02x", $0) }.joined())")
//                } else {
//                    print("Stream public ID is nil")
//                }
//            } else {
//                print("Failed to access Stream through EntityRoot")
//            }
//        } catch {
//            print("Verification or access failed: \(error)")
//        }
        // END ***** debug
        let nanoPayload = builder.data
        // Create Nano
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.streamProfile.rawValue)!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: nanoPayload)
        let targetPayload = nanoTDF.toData()
        // Create CacheEvent
        builder = FlatBufferBuilder(initialSize: 1024)
        let targetIdVector = builder.createVector(bytes: stream.publicID)
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
        let data = builder.data
//        print("cache event: \(data.base64EncodedString())")
        try service.sendEvent(data)
    }

    @MainActor
    public func requestStream(withPublicID publicID: Data) async throws -> Stream? {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let accountProfile = account.profile
        let streams = try await PersistenceController.shared.fetchStream(withPublicID: publicID)
        guard let accountProfilePublicID = accountProfile?.publicID
        else {
            throw StreamServiceError.missingAccountOrProfile
        }
        let stream = streams?.first
        if let stream {
            print("Found stream: \(stream.publicID.base58EncodedString)")
            return stream
        }
        print("No stream found with publicID: \(publicID.base58EncodedString)")
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
//        print("invite event: \(data.base64EncodedString())")
        try service.sendEvent(data)
        return nil
    }

    @MainActor
    func handle(_ data: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async throws {
//        print("Handling stream data: \(data.base64EncodedString())")
        // Parse the decrypted data using FlatBuffers
        var buffer = ByteBuffer(data: data)
        let rootOffset = buffer.read(def: Int32.self, position: 0)
        var verifier = try Verifier(buffer: &buffer)
        try Arkavo_EntityRoot.verify(&verifier, at: Int(rootOffset), of: Arkavo_EntityRoot.self)
        // Access the EntityRoot
        let entityRoot = Arkavo_EntityRoot(buffer, o: Int32(rootOffset))
        // Access the Stream through EntityRoot
        if let arkStream = entityRoot.entity(type: Arkavo_Stream.self) {
            // Extract PublicId
            guard let publicId = arkStream.publicId?.id else {
                throw StreamError.missingPublicId
            }
            // Extract CreatorPublicId
            guard let creatorPublicId = arkStream.creatorPublicId?.id else {
                throw StreamError.missingCreatorPublicId
            }
            // Extract Profile
            guard let profile = arkStream.profile,
                  let name = profile.name
            else {
                throw StreamError.missingProfile
            }
            // Create the Stream object
            let stream = Stream(
                id: UUID(),
                creatorPublicID: Data(creatorPublicId),
                profile: Profile(name: name),
                admissionPolicy: .open, // map
                interactionPolicy: .open, // map
                publicID: Data(publicId)
            )
            try PersistenceController.shared.saveStream(stream)
        } else {
            throw StreamError.invalidEntityType
        }
    }

    // Helper functions
    private func createProfile(_ fbb: inout FlatBufferBuilder, from profile: Profile) -> Offset {
        let nameOffset = fbb.create(string: profile.name)
        let blurbOffset = fbb.create(string: profile.blurb ?? "")
        let interestsOffset = fbb.create(string: profile.interests)
        let locationOffset = fbb.create(string: profile.location)

        return Arkavo_Profile.createProfile(
            &fbb,
            nameOffset: nameOffset,
            blurbOffset: blurbOffset,
            interestsOffset: interestsOffset,
            locationOffset: locationOffset,
            locationLevel: .approximate, // You might want to map this
            identityAssuranceLevel: profile.hasHighIdentityAssurance ? .ial2 : .ial1,
            encryptionLevel: profile.hasHighEncryption ? .el2 : .el1
        )
    }

    private func createDefaultActivity(_ fbb: inout FlatBufferBuilder) -> Offset {
        let activityOffset = Arkavo_Activity.createActivity(
            &fbb,
            dateCreated: Int64(Date().timeIntervalSince1970),
            expertLevel: .novice,
            activityLevel: .low,
            trustLevel: .low
        )
        print("Inside createDefaultActivity - activityOffset: \(activityOffset.o)")
        return activityOffset
    }

    private func extractProfile(from arkProfile: Arkavo_Profile?) -> Profile {
        Profile(
            id: UUID(),
            name: arkProfile?.name ?? "Empty",
            blurb: arkProfile?.blurb,
            interests: arkProfile?.interests ?? "",
            location: arkProfile?.location ?? "",
            hasHighEncryption: arkProfile?.encryptionLevel == .el2,
            hasHighIdentityAssurance: arkProfile?.identityAssuranceLevel == .ial2 || arkProfile?.identityAssuranceLevel == .ial3
        )
    }

    enum StreamServiceError: Error {
        case missingAccountOrProfile
        case missingKASkey
        case flatBufferCreationFailed
        case missingRequiredFields
    }

    enum StreamError: Error {
        case missingPublicId
        case missingCreatorPublicId
        case missingProfile
        case invalidEntityType
    }
}
