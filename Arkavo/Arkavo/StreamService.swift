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
        // Create Stream using FlatBuffers
        var fbb = FlatBufferBuilder(initialSize: 1024)
        // Create PublicId
        let publicIdVector = fbb.createVector(bytes: stream.publicID)
        let publicId = Arkavo_PublicId.createPublicId(&fbb, idVectorOffset: publicIdVector)
        // Create Profile
        let profileOffset = createProfile(&fbb, from: stream.profile)
        // Create Activity (using default values as it's not in the Stream model)
        let activityOffset = createDefaultActivity(&fbb)
        // Create creator's PublicId
        let creatorPublicIdVector = fbb.createVector(bytes: stream.account.profile!.publicID)
        let creatorPublicId = Arkavo_PublicId.createPublicId(&fbb, idVectorOffset: creatorPublicIdVector)
        // Create members' PublicIds (assuming Stream has a members property)
        let membersPublicIdOffsets: [Offset] = [] // Implement this if Stream has members
        let membersPublicIdVector = fbb.createVector(ofOffsets: membersPublicIdOffsets)
        // Create Stream
        let streamOffset = Arkavo_Stream.createStream(
            &fbb,
            publicIdOffset: publicId,
            profileOffset: profileOffset,
            activityOffset: activityOffset,
            creatorPublicIdOffset: creatorPublicId,
            membersPublicIdVectorOffset: membersPublicIdVector,
            streamLevel: .sl1 // You might want to map AdmissionPolicy to StreamLevel
        )
        fbb.finish(offset: streamOffset)
        let payload = fbb.data
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
        // Parse the decrypted data using FlatBuffers
        let byteBuffer = ByteBuffer(data: data)
        let arkStream = Arkavo_Stream(byteBuffer, o: 0)
        // Extract information from the Arkavo_Stream object
        let publicID = Data(arkStream.publicId?.id ?? [])
        let profile = extractProfile(from: arkStream.profile)
        let creatorPublicID = Data(arkStream.creatorPublicId?.id ?? [])
        // Create the Stream object
        let stream = Stream(
            id: UUID(),
            account: Account(),
            profile: profile,
            admissionPolicy: .open, // You might want to map StreamLevel to AdmissionPolicy
            interactionPolicy: .open // Default value, adjust as needed
        )
        do {
            // Store the Stream in the database
            try PersistenceController.shared.saveStream(stream)
            print("Stream saved successfully")
        } catch {
            print("Failed to save stream: \(error)")
            throw error
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
        Arkavo_Activity.createActivity(
            &fbb,
            dateCreated: Int64(Date().timeIntervalSince1970),
            expertLevel: .novice,
            activityLevel: .low,
            trustLevel: .low
        )
    }

    private func extractProfile(from arkProfile: Arkavo_Profile?) -> Profile {
        Profile(
            id: UUID(),
            name: arkProfile?.name ?? "",
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
}
