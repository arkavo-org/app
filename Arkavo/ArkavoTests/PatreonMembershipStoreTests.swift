@testable import Arkavo
import SwiftData
import XCTest

@MainActor
final class PatreonMembershipStoreTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var store: PatreonMembershipStore!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        let modelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: MembershipReadState.self,
            configurations: modelConfiguration
        )
        modelContext = modelContainer.mainContext

        // Initialize store with test context
        store = PatreonMembershipStore(modelContext: modelContext)
    }

    override func tearDown() async throws {
        store = nil
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Happy Path Tests

    func testMarkAsViewed_UpdatesLastViewedAt() {
        // Arrange
        let membershipId = "test-membership-1"
        let beforeDate = Date()

        // Act
        store.markAsViewed(membershipId: membershipId)

        // Assert
        let count = store.unreadCount(for: membershipId)
        XCTAssertEqual(count, 0, "Unread count should be 0 after marking as viewed")
    }

    func testUnreadCount_WithNoPosts_ReturnsZero() {
        // Arrange
        let membershipId = "test-membership-2"

        // Act
        let count = store.unreadCount(for: membershipId)

        // Assert
        XCTAssertEqual(count, 0, "Unread count should be 0 when no posts exist")
    }

    func testHasUnreadContent_WithNoUnread_ReturnsFalse() {
        // Assert
        XCTAssertFalse(store.hasUnreadContent, "Should have no unread content initially")
        XCTAssertEqual(store.totalUnreadCount, 0, "Total unread should be 0")
    }

    // MARK: - Edge Case Tests

    func testMarkAsViewed_WithEmptyString_StoresCorrectly() {
        // Arrange
        let emptyMembershipId = ""

        // Act
        store.markAsViewed(membershipId: emptyMembershipId)

        // Assert
        let count = store.unreadCount(for: emptyMembershipId)
        XCTAssertEqual(count, 0)
    }

    func testMarkAsViewed_MultipleTimes_DoesNotDuplicate() {
        // Arrange
        let membershipId = "test-membership-3"

        // Act
        store.markAsViewed(membershipId: membershipId)
        store.markAsViewed(membershipId: membershipId)
        store.markAsViewed(membershipId: membershipId)

        // Assert
        let descriptor = FetchDescriptor<MembershipReadState>(
            predicate: #Predicate { $0.membershipId == membershipId }
        )
        let states = try? modelContext.fetch(descriptor)
        XCTAssertEqual(states?.count, 1, "Should only create one read state per membership")
    }

    func testMarkAsViewed_DifferentMemberships_CreatesSeparateStates() {
        // Arrange
        let membershipId1 = "membership-a"
        let membershipId2 = "membership-b"

        // Act
        store.markAsViewed(membershipId: membershipId1)
        store.markAsViewed(membershipId: membershipId2)

        // Assert
        let descriptor = FetchDescriptor<MembershipReadState>()
        let states = try? modelContext.fetch(descriptor)
        XCTAssertEqual(states?.count, 2, "Should create separate states for each membership")
    }

    func testUnreadCount_NonExistentMembership_ReturnsZero() {
        // Arrange
        let nonExistentId = "does-not-exist"

        // Act
        let count = store.unreadCount(for: nonExistentId)

        // Assert
        XCTAssertEqual(count, 0, "Should return 0 for non-existent membership")
    }

    // MARK: - Read State Persistence Tests

    func testReadState_PersistsToSwiftData() {
        // Arrange
        let membershipId = "persist-test"

        // Act
        store.markAsViewed(membershipId: membershipId)

        // Create new store instance with same context to verify persistence
        let newStore = PatreonMembershipStore(modelContext: modelContext)

        // Assert - lastViewedAt should be updated
        let descriptor = FetchDescriptor<MembershipReadState>(
            predicate: #Predicate { $0.membershipId == membershipId }
        )
        let state = try? modelContext.fetch(descriptor).first
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.membershipId, membershipId)
        XCTAssertGreaterThan(state?.lastViewedAt ?? .distantPast, .distantPast)
    }

    // MARK: - Total Unread Count Tests

    func testTotalUnreadCount_SumsAllUnread() {
        // Arrange - manually set unread counts
        store.unreadCounts["m1"] = 5
        store.unreadCounts["m2"] = 3
        store.unreadCounts["m3"] = 2

        // Act
        store.recalculateTotal()

        // Assert
        XCTAssertEqual(store.totalUnreadCount, 10, "Should sum all unread counts")
    }

    func testTotalUnreadCount_WithZeroCounts() {
        // Arrange
        store.unreadCounts["m1"] = 0
        store.unreadCounts["m2"] = 0

        // Act
        store.recalculateTotal()

        // Assert
        XCTAssertEqual(store.totalUnreadCount, 0)
        XCTAssertFalse(store.hasUnreadContent)
    }

    // MARK: - Integration Tests

    func testCalculateUnreadCounts_WithPosts() async {
        // Arrange
        let membership = PatreonMembership(
            id: "test-mem",
            creatorName: "Test Creator",
            creatorAvatarURL: nil,
            campaignId: "campaign-1",
            tierName: "Test Tier",
            tierAmount: 5.0,
            status: "Active Patron",
            pledgeCadence: 1,
            campaignURL: nil,
            isActive: true
        )

        let oldPost = PatreonPost(
            id: "old",
            title: "Old Post",
            content: nil,
            publishedAt: Date().addingTimeInterval(-86400), // 1 day ago
            isPublic: false,
            minTierAmount: 5.0,
            imageURL: nil,
            url: nil,
            likeCount: 10,
            commentCount: 2
        )

        let newPost = PatreonPost(
            id: "new",
            title: "New Post",
            content: nil,
            publishedAt: Date(), // Now
            isPublic: false,
            minTierAmount: 5.0,
            imageURL: nil,
            url: nil,
            likeCount: 5,
            commentCount: 1
        )

        // First mark as viewed at a time between old and new post
        store.markAsViewed(membershipId: membership.id)
        // Manually set lastViewedAt to 12 hours ago (between the two posts)
        let descriptor = FetchDescriptor<MembershipReadState>(
            predicate: #Predicate { $0.membershipId == membership.id }
        )
        if let state = try? modelContext.fetch(descriptor).first {
            state.lastViewedAt = Date().addingTimeInterval(-43200) // 12 hours ago
            try? modelContext.save()
        }

        // Act
        await store.refreshUnreadCounts(
            for: [membership],
            postsByMembership: [membership.id: [oldPost, newPost]]
        )

        // Assert - only new post should be unread
        XCTAssertEqual(store.unreadCount(for: membership.id), 1)
        XCTAssertEqual(store.totalUnreadCount, 1)
        XCTAssertTrue(store.hasUnreadContent)
    }

    func testCalculateUnreadCounts_AllPostsRead() async {
        // Arrange
        let membership = PatreonMembership(
            id: "test-mem-2",
            creatorName: "Test Creator",
            creatorAvatarURL: nil,
            campaignId: "campaign-2",
            tierName: "Test Tier",
            tierAmount: 5.0,
            status: "Active Patron",
            pledgeCadence: 1,
            campaignURL: nil,
            isActive: true
        )

        let oldPost = PatreonPost(
            id: "old",
            title: "Old Post",
            content: nil,
            publishedAt: Date().addingTimeInterval(-86400),
            isPublic: false,
            minTierAmount: 5.0,
            imageURL: nil,
            url: nil,
            likeCount: 10,
            commentCount: 2
        )

        // Mark as viewed now (after the old post)
        store.markAsViewed(membershipId: membership.id)

        // Act
        await store.refreshUnreadCounts(
            for: [membership],
            postsByMembership: [membership.id: [oldPost]]
        )

        // Assert - all posts should be read
        XCTAssertEqual(store.unreadCount(for: membership.id), 0)
        XCTAssertEqual(store.totalUnreadCount, 0)
        XCTAssertFalse(store.hasUnreadContent)
    }
}
