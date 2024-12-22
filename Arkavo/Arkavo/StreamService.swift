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
    private var locationContinuation: CheckedContinuation<(LocationData, Data), Error>?

    init(_ service: ArkavoService) {
        self.service = service
    }

    func sendStreamEvent(_ stream: Stream) async throws {
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
        let kasMetadata = try KasMetadata(resourceLocator: kasRL, publicKey: kasPublicKey, curve: .secp256r1)
        let remotePolicy = ResourceLocator(protocolEnum: .sharedResourceDirectory, body: ArkavoPolicy.PolicyType.streamProfile.rawValue)!
        var policy = Policy(type: .remote, body: nil, remote: remotePolicy, binding: nil)
        let nanoTDF = try await createNanoTDF(kas: kasMetadata, policy: &policy, plaintext: nanoPayload)
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

    func requestLocationAndWait(for publicID: Data) async throws -> LocationData {
        let (coordinate, _) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(LocationData, Data), Error>?) in
            locationContinuation = continuation
            Task {
                do {
                    try await requestLocation(withPublicID: publicID)
                } catch {
                    if let cont = self.locationContinuation {
                        cont.resume(throwing: error)
                        self.locationContinuation = nil
                    }
                }
            }
        }
        return coordinate
    }

    @MainActor
    public func requestLocation(withPublicID publicID: Data) async throws {
        let account = try await PersistenceController.shared.getOrCreateAccount()
        let accountProfile = account.profile
        guard let accountProfilePublicID = accountProfile?.publicID
        else {
            throw StreamServiceError.missingAccountOrProfile
        }
        // Create RouteEvent
        var builder = FlatBufferBuilder(initialSize: 1024)
        let targetIdVector = builder.createVector(bytes: publicID)
        let sourceIdVector = builder.createVector(bytes: accountProfilePublicID)
        let routeEventOffset = Arkavo_RouteEvent.createRouteEvent(
            &builder,
            targetType: .accountProfile,
            targetIdVectorOffset: targetIdVector,
            sourceType: .accountProfile,
            sourceIdVectorOffset: sourceIdVector,
            attributeType: .location,
            entityType: .streamProfile
        )
//        print("Debug: Created RouteEvent, offset: \(routeEventOffset)")
        // Create Event
        let eventOffset = Arkavo_Event.createEvent(
            &builder,
            action: .share,
            timestamp: UInt64(Date().timeIntervalSince1970),
            status: .preparing,
            dataType: .routeevent,
            dataOffset: routeEventOffset
        )
//        print("Debug: Created Event, offset: \(eventOffset)")
        builder.finish(offset: eventOffset)
//        print("Debug: Finished builder")
        var buffer = builder.sizedBuffer
//        print("Debug: Got sized buffer, size: \(buffer.size), capacity: \(buffer.capacity)")
        // Convert ByteBuffer to Data for base64 encoding and sending
        let data = Data(bytes: buffer.memory.advanced(by: buffer.reader), count: Int(buffer.size))
//        print("Debug: Converted buffer to Data, size: \(data.count)")
//        print("Debug: route event (base64): \(data.base64EncodedString())")
        // Print hex representation for more detailed view
//        print("Debug: route event (hex): \(data.map { String(format: "%02hhx", $0) }.joined())")
        // FlatBuffers verification
        do {
//            print("Debug: Starting FlatBuffer verification")
            let rootOffset = buffer.read(def: Int32.self, position: 0)
            var verifier = try Verifier(buffer: &buffer)
            try Arkavo_Event.verify(&verifier, at: Int(rootOffset), of: Arkavo_Event.self)
            print("FlatBuffer verification passed")
        } catch {
            print("FlatBuffer verification failed: \(error)")
            throw error // or handle the error as appropriate for your application
        }
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
            guard (arkStream.publicId?.id) != nil else {
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
                policies: Policies(admission: .open, interaction: .open, age: .forAll)
            )
            try PersistenceController.shared.saveStream(stream)
        } else {
            throw StreamError.invalidEntityType
        }
    }

    func handleRouteEventFulfilled(_ routeEvent: Arkavo_RouteEvent) {
        print("Route Event Fulfilled:")
        print("  Source Type: \(routeEvent.sourceType)")
        print("  Target Type: \(routeEvent.targetType)")
        print("  Source ID: \(Data(routeEvent.sourceId).base58EncodedString)")
        print("  Attribute Type: \(routeEvent.attributeType)")

        if !routeEvent.hasPayload {
            print("No payload in fulfilled route event")
            return
        }
        let payloadData = Data(routeEvent.payload)
        do {
            if let jsonString = String(data: payloadData, encoding: .utf8),
               let jsonData = jsonString.data(using: .utf8)
            {
                let locationData = try JSONDecoder().decode(LocationData.self, from: jsonData)
                if let continuation = locationContinuation {
                    continuation.resume(returning: (locationData, Data(routeEvent.targetId)))
                    locationContinuation = nil
                }
            } else {
                print("Failed to convert payload to JSON string")
                return
            }
        } catch {
            print("Failed to decode location data: \(error)")
            return
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
        case serviceNotInitialized
    }

    enum StreamError: Error {
        case missingPublicId
        case missingCreatorPublicId
        case missingProfile
        case invalidEntityType
    }
}
