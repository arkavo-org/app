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
        guard let streamAccountProfile = stream.account.profile else {
            throw StreamServiceError.missingAccountOrProfile
        }
        // Create Stream
        // Create Stream using FlatBuffers
        var fbb = FlatBufferBuilder(initialSize: 1024)
        // Create PublicId
        let publicIdVector = fbb.createVector(bytes: stream.publicID)
        let publicId = Arkavo_PublicId.createPublicId(&fbb, idVectorOffset: publicIdVector)
        // Create Entity
        let entity = Arkavo_Entity.createEntity(&fbb, publicIdOffset: publicId)
        // Create Profile
        let name = fbb.create(string: stream.profile.name)
        let blurb = fbb.create(string: stream.profile.blurb ?? "")
        let interests = fbb.create(string: stream.profile.interests)
        let location = fbb.create(string: stream.profile.location)
        let profile = Arkavo_Profile.createProfile(
            &fbb,
            nameOffset: name,
            blurbOffset: blurb,
            interestsOffset: interests,
            locationOffset: location,
            locationLevel: .unused, // Set appropriate value
            identityAssuranceLevel: .unused, // Set appropriate value
            encryptionLevel: .unused // Set appropriate value
        )
        // Create creator's PublicId
        let creatorPublicIdVector = fbb.createVector(bytes: streamAccountProfile.publicID)
        let creatorPublicId = Arkavo_PublicId.createPublicId(&fbb, idVectorOffset: creatorPublicIdVector)
        // Create membersPublicId vector
//        let membersPublicIds = stream.thoughts.compactMap { $0.account.publicID }
//        let membersPublicIdVectors = membersPublicIds.map { fbb.createVector($0) }
//        let membersPublicIdOffsets = membersPublicIdVectors.map { Arkavo_PublicId.createPublicId(&fbb, idVectorOffset: $0) }
//        let membersPublicIdVector = fbb.createVector(ofOffsets: membersPublicIdOffsets)
        // Create Stream
        let streamObj = Arkavo_Stream.createStream(
            &fbb,
            entityOffset: entity,
            profileOffset: profile,
            creatorPublicIdOffset: creatorPublicId,
            membersPublicIdVectorOffset: Offset(), // Empty offset for no members,
            streamLevel: .sl1 // Set appropriate StreamLevel
        )
        fbb.finish(offset: streamObj)
        let payload = fbb.data
        print("Arkavo_Stream payload: \(payload.base64URLEncodedString())")
        // Create Nano
        let kasRL = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: "kas.arkavo.net")!
        let kasMetadata = KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.streamProfile.rawValue)!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
        let nanoTDF = try createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: payload)
        let targetPayload = nanoTDF.toData()
        // Create CacheEvent
        var builder = FlatBufferBuilder(initialSize: 1024)
        let targetIdVector = builder.createVector(bytes: stream.publicID)
        let targetPayloadVector = builder.createVector(bytes: targetPayload)
        let cacheEventOffset = Arkavo_CacheEvent.createCacheEvent(
            &builder,
            targetIdVectorOffset: targetIdVector,
            targetPayloadVectorOffset: targetPayloadVector,
            ttl: 3600, // 1 hour TTL, TODO adjust as needed
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
        print("cache event: \(data.base64EncodedString())")
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
        print("invite event: \(data.base64EncodedString())")
        try service.sendEvent(data)
        return nil
    }

    @MainActor
    func handle(_ data: Data, policy _: ArkavoPolicy, nano _: NanoTDF) async throws {
        print("handle stream data \(data.base64EncodedString())")

        // 2. Parse the decrypted data using FlatBuffers
        let byteBuffer = ByteBuffer(data: data)
        let arkStream = Arkavo_Stream(byteBuffer, o: 0)

        // 3. Extract information from the Arkavo_Stream object
        guard let entity = arkStream.entity,
              let profile = arkStream.profile
        else {
            throw StreamServiceError.missingRequiredFields
        }

        let name = profile.name ?? ""
        let blurb = profile.blurb
        let interests = profile.interests ?? ""
        let location = profile.location ?? ""

        // 4. Create or fetch the Account
//        let creatorPublicIDData = Data(creatorPublicId.id)
        // FIXME: load creatorPublicIDData
        let account = Account()

        // 5. Create the Profile
        let streamProfile = Profile(name: name, blurb: blurb, interests: interests, location: location)

        // 6. Create the Stream object
        let stream = Stream(
            id: UUID(), // Generate a new UUID for local storage
            account: account,
            profile: streamProfile,
            admissionPolicy: .open, // Set appropriate admission policy
            interactionPolicy: .open, // Set appropriate interaction policy
            thoughts: [] // Start with empty thoughts
        )

        // Set the publicID separately to ensure it matches the one from the incoming data
        if entity.publicId != nil {
            stream.publicID = Data(entity.publicId!.id)
        }

        do {
            // 7. Store the Stream in the database
            try PersistenceController.shared.saveStream(stream)
            print("Stream saved successfully")
        } catch {
            print("Failed to save stream: \(error)")
            throw error
        }
    }

    enum StreamServiceError: Error {
        case missingAccountOrProfile
        case missingKASkey
        case flatBufferCreationFailed
        case missingRequiredFields
    }
}
