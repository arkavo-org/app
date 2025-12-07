@testable import Arkavo
import SwiftData
import XCTest

/// Tests for stream creation functions to ensure SwiftData context management is correct
@MainActor
final class StreamCreationTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create an in-memory SwiftData container for testing
        let schema = Schema([
            Account.self,
            Profile.self,
            Stream.self,
            Thought.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        modelContext = modelContainer.mainContext
    }

    override func tearDownWithError() throws {
        modelContainer = nil
        modelContext = nil
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    /// Creates a test profile with valid data
    private func createTestProfile() -> Profile {
        let profile = Profile(
            name: "Test User",
            blurb: "Test bio",
            interests: "testing",
            location: "Test City"
        )
        profile.publicID = Data("testProfileID12345".utf8)
        return profile
    }

    /// Creates a test account
    private func createTestAccount() -> Account {
        Account()
    }

    // MARK: - Profile Context Insertion Tests

    func testProfileInsertedIntoContextBeforeSave() async throws {
        // Arrange
        let profile = createTestProfile()

        // Act: Insert profile into context before using in relationships
        modelContext.insert(profile)

        // Assert: Profile should be in the context
        XCTAssertFalse(profile.publicID.isEmpty, "Profile should have a valid publicID")
        XCTAssertFalse(profile.name.isEmpty, "Profile should have a valid name")

        // Save should succeed without validation errors
        XCTAssertNoThrow(try modelContext.save())
    }

    func testAccountProfileRelationshipWithProperInsertion() async throws {
        // Arrange
        let account = createTestAccount()
        let profile = createTestProfile()

        // Act: Insert both into context before setting relationship
        modelContext.insert(account)
        modelContext.insert(profile)
        account.profile = profile

        // Assert: Save should succeed
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertNotNil(account.profile, "Account should have a profile")
        XCTAssertEqual(account.profile?.name, "Test User")
    }

    // MARK: - Stream Creation Tests

    func testStreamInsertedIntoContextBeforeThought() async throws {
        // Arrange
        let profile = createTestProfile()
        modelContext.insert(profile)

        // Act: Create stream and insert into context before creating thought
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(
                admission: .closed,
                interaction: .closed,
                age: .onlyKids
            )
        )
        modelContext.insert(stream)

        // Create thought after stream is in context
        let metadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: stream.publicID,
            mediaType: .video,
            createdAt: Date(),
            contributors: []
        )
        let thought = Thought(nano: Data(), metadata: metadata)
        modelContext.insert(thought)

        stream.source = thought

        // Assert: Save should succeed
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertNotNil(stream.source, "Stream should have a source thought")
    }

    func testVideoStreamCreationPattern() async throws {
        // Arrange
        let account = createTestAccount()
        let profile = createTestProfile()
        modelContext.insert(account)
        modelContext.insert(profile)
        account.profile = profile

        // Act: Follow the correct pattern from createVideoStream
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(
                admission: .closed,
                interaction: .closed,
                age: .onlyKids
            )
        )
        modelContext.insert(stream)

        let metadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: stream.publicID,
            mediaType: .video,
            createdAt: Date(),
            contributors: []
        )
        let thought = Thought(nano: Data(), metadata: metadata)
        modelContext.insert(thought)

        stream.source = thought
        account.streams.append(stream)

        // Assert
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertEqual(account.streams.count, 1)
        XCTAssertEqual(account.streams.first?.source?.metadata.mediaType, .video)
    }

    func testPostStreamCreationPattern() async throws {
        // Arrange
        let account = createTestAccount()
        let profile = createTestProfile()
        modelContext.insert(account)
        modelContext.insert(profile)
        account.profile = profile

        // Act: Follow the correct pattern from createPostStream
        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(
                admission: .closed,
                interaction: .closed,
                age: .onlyKids
            )
        )
        modelContext.insert(stream)

        let metadata = Thought.Metadata(
            creatorPublicID: profile.publicID,
            streamPublicID: stream.publicID,
            mediaType: .post,
            createdAt: Date(),
            contributors: []
        )
        let thought = Thought(nano: Data(), metadata: metadata)
        modelContext.insert(thought)

        stream.source = thought
        account.streams.append(stream)

        // Assert
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertEqual(account.streams.count, 1)
        XCTAssertEqual(account.streams.first?.source?.metadata.mediaType, .post)
    }

    func testInnerCircleStreamCreationPattern() async throws {
        // Arrange
        let account = createTestAccount()
        let profile = createTestProfile()
        modelContext.insert(account)
        modelContext.insert(profile)
        account.profile = profile

        // Act: Follow the correct pattern from createInnerCircleStream
        // InnerCircle creates its own profile
        let innerCircleProfile = Profile(
            name: "InnerCircle",
            blurb: "Local peer-to-peer communication",
            interests: "local",
            location: ""
        )
        modelContext.insert(innerCircleProfile)

        let stream = Stream(
            creatorPublicID: profile.publicID,
            profile: innerCircleProfile,
            policies: Policies(
                admission: .openInvitation,
                interaction: .open,
                age: .forAll
            )
        )
        modelContext.insert(stream)

        account.streams.append(stream)

        // Assert
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertEqual(account.streams.count, 1)
        XCTAssertEqual(account.streams.first?.profile.name, "InnerCircle")
    }

    // MARK: - Multiple Streams Creation Test

    func testMultipleStreamsCreation() async throws {
        // Arrange
        let account = createTestAccount()
        let profile = createTestProfile()
        modelContext.insert(account)
        modelContext.insert(profile)
        account.profile = profile

        // Act: Create video stream
        let videoStream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(admission: .closed, interaction: .closed, age: .onlyKids)
        )
        modelContext.insert(videoStream)
        let videoThought = Thought(
            nano: Data(),
            metadata: Thought.Metadata(
                creatorPublicID: profile.publicID,
                streamPublicID: videoStream.publicID,
                mediaType: .video,
                createdAt: Date(),
                contributors: []
            )
        )
        modelContext.insert(videoThought)
        videoStream.source = videoThought
        account.streams.append(videoStream)

        // Create post stream
        let postStream = Stream(
            creatorPublicID: profile.publicID,
            profile: profile,
            policies: Policies(admission: .closed, interaction: .closed, age: .onlyKids)
        )
        modelContext.insert(postStream)
        let postThought = Thought(
            nano: Data(),
            metadata: Thought.Metadata(
                creatorPublicID: profile.publicID,
                streamPublicID: postStream.publicID,
                mediaType: .post,
                createdAt: Date(),
                contributors: []
            )
        )
        modelContext.insert(postThought)
        postStream.source = postThought
        account.streams.append(postStream)

        // Create InnerCircle stream
        let innerCircleProfile = Profile(
            name: "InnerCircle",
            blurb: "Local peer-to-peer communication",
            interests: "local",
            location: ""
        )
        modelContext.insert(innerCircleProfile)
        let innerCircleStream = Stream(
            creatorPublicID: profile.publicID,
            profile: innerCircleProfile,
            policies: Policies(admission: .openInvitation, interaction: .open, age: .forAll)
        )
        modelContext.insert(innerCircleStream)
        account.streams.append(innerCircleStream)

        // Assert: All streams should be saved successfully
        XCTAssertNoThrow(try modelContext.save())
        XCTAssertEqual(account.streams.count, 3, "Account should have 3 streams")

        // Verify each stream type
        let savedVideoStream = account.streams.first { $0.source?.metadata.mediaType == .video }
        let savedPostStream = account.streams.first { $0.source?.metadata.mediaType == .post }
        let savedInnerCircle = account.streams.first { $0.profile.name == "InnerCircle" }

        XCTAssertNotNil(savedVideoStream, "Video stream should exist")
        XCTAssertNotNil(savedPostStream, "Post stream should exist")
        XCTAssertNotNil(savedInnerCircle, "InnerCircle stream should exist")
    }

    // MARK: - Profile Validation Tests

    func testProfileWithValidFieldsSavesSuccessfully() async throws {
        // Arrange
        let profile = Profile(
            name: "Valid Name",
            blurb: "Valid bio",
            interests: "testing",
            location: "City"
        )
        profile.publicID = Data("validID123".utf8)

        // Act
        modelContext.insert(profile)

        // Assert
        XCTAssertNoThrow(try modelContext.save())

        // Verify the saved profile has correct values
        let descriptor = FetchDescriptor<Profile>()
        let profiles = try modelContext.fetch(descriptor)
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Valid Name")
        XCTAssertFalse(profiles.first?.publicID.isEmpty ?? true)
    }

    func testCleanupInvalidProfiles() async throws {
        // Arrange: Create a valid profile
        let validProfile = createTestProfile()
        modelContext.insert(validProfile)

        // Create an "invalid" profile with empty name (simulating corruption)
        let invalidProfile = Profile(name: "", blurb: "", interests: "", location: "")
        invalidProfile.publicID = Data()
        modelContext.insert(invalidProfile)

        try modelContext.save()

        // Act: Simulate cleanup logic
        let descriptor = FetchDescriptor<Profile>()
        let allProfiles = try modelContext.fetch(descriptor)

        for profile in allProfiles {
            if profile.name.isEmpty || profile.publicID.isEmpty {
                modelContext.delete(profile)
            }
        }
        try modelContext.save()

        // Assert: Only valid profile should remain
        let remainingProfiles = try modelContext.fetch(descriptor)
        XCTAssertEqual(remainingProfiles.count, 1)
        XCTAssertEqual(remainingProfiles.first?.name, "Test User")
    }
}
