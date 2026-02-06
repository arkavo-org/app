import ArkavoSocial
import SwiftData
import SwiftUI

// MARK: - SwiftData Model

/// Tracks read state for Patreon memberships
@Model
final class MembershipReadState {
    @Attribute(.unique) var membershipId: String
    var lastViewedAt: Date
    var lastPostSeenAt: Date?
    var createdAt: Date

    init(membershipId: String) {
        self.membershipId = membershipId
        self.lastViewedAt = Date.distantPast
        self.lastPostSeenAt = nil
        self.createdAt = Date()
    }
}

// MARK: - Store

/// Manages unread badge counts for Patreon memberships
@MainActor
final class PatreonMembershipStore: ObservableObject {
    @Published private(set) var unreadCounts: [String: Int] = [:]
    @Published private(set) var totalUnreadCount: Int = 0
    @Published private(set) var isLoading = false

    private let modelContext: ModelContext
    private let client: PatreonClient

    init(modelContext: ModelContext? = nil) {
        if let context = modelContext {
            self.modelContext = context
        } else {
            // Use the main container from PersistenceController
            self.modelContext = PersistenceController.shared.container.mainContext
        }
        self.client = PatreonClient(
            clientId: Secrets.patreonClientId,
            clientSecret: Secrets.patreonClientSecret
        )
    }

    // MARK: - Public Methods

    /// Loads memberships and calculates unread counts
    func loadMembershipsWithUnread() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let memberships = try await client.getMyMemberships()
            await calculateUnreadCounts(for: memberships)
        } catch {
            print("[PatreonMembershipStore] Failed to load memberships: \(error)")
        }
    }

    /// Refreshes unread counts for given memberships (used when we already have the list)
    func refreshUnreadCounts(for memberships: [PatreonMembership], postsByMembership: [String: [PatreonPost]]? = nil) async {
        await calculateUnreadCounts(for: memberships, postsByMembership: postsByMembership)
    }

    /// Marks all posts for a membership as viewed
    func markAsViewed(membershipId: String) {
        let state = getOrCreateReadState(for: membershipId)
        state.lastViewedAt = Date()

        do {
            try modelContext.save()
            unreadCounts[membershipId] = 0
            recalculateTotal()
        } catch {
            print("[PatreonMembershipStore] Failed to save read state: \(error)")
        }
    }
    
    /// Marks all memberships as viewed (e.g., when user opens the memberships tab)
    func markAllAsViewed() {
        let descriptor = FetchDescriptor<MembershipReadState>()
        guard let states = try? modelContext.fetch(descriptor) else { return }
        
        let now = Date()
        for state in states {
            state.lastViewedAt = now
            unreadCounts[state.membershipId] = 0
        }
        
        do {
            try modelContext.save()
            recalculateTotal()
        } catch {
            print("[PatreonMembershipStore] Failed to mark all as viewed: \(error)")
        }
    }

    /// Gets unread count for a specific membership
    func unreadCount(for membershipId: String) -> Int {
        unreadCounts[membershipId] ?? 0
    }

    /// Checks if there are any unread posts across all memberships
    var hasUnreadContent: Bool {
        totalUnreadCount > 0
    }

    // MARK: - Private Methods

    private func calculateUnreadCounts(
        for memberships: [PatreonMembership],
        postsByMembership: [String: [PatreonPost]]? = nil
    ) async {
        var newCounts: [String: Int] = [:]

        for membership in memberships {
            let readState = getOrCreateReadState(for: membership.id)

            // Get posts for this membership
            let posts: [PatreonPost]
            if let cached = postsByMembership?[membership.id] {
                posts = cached
            } else {
                // Fetch posts if not provided
                do {
                    posts = try await client.getPosts(campaignId: membership.campaignId)
                } catch {
                    print("[PatreonMembershipStore] Failed to fetch posts for \(membership.creatorName): \(error)")
                    posts = []
                }
            }

            // Count unread posts
            let unread = posts.filter { $0.publishedAt > readState.lastViewedAt }.count
            newCounts[membership.id] = unread

            // Update lastPostSeenAt if we have posts
            if let newestPost = posts.max(by: { $0.publishedAt < $1.publishedAt }) {
                if readState.lastPostSeenAt == nil || newestPost.publishedAt > readState.lastPostSeenAt! {
                    readState.lastPostSeenAt = newestPost.publishedAt
                }
            }
        }

        do {
            try modelContext.save()
        } catch {
            print("[PatreonMembershipStore] Failed to save read states: \(error)")
        }

        await MainActor.run {
            self.unreadCounts = newCounts
            self.recalculateTotal()
        }
    }

    private func getOrCreateReadState(for membershipId: String) -> MembershipReadState {
        let descriptor = FetchDescriptor<MembershipReadState>(
            predicate: #Predicate { $0.membershipId == membershipId }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        let newState = MembershipReadState(membershipId: membershipId)
        modelContext.insert(newState)
        return newState
    }

    private func recalculateTotal() {
        let newTotal = unreadCounts.values.reduce(0, +)
        totalUnreadCount = newTotal
        
        // Update app icon badge
        UIApplication.shared.applicationIconBadgeNumber = newTotal
    }
}

// MARK: - Badge View

/// Reusable badge view for showing unread counts
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(min(count, 99))")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(minWidth: 18, minHeight: 18)
                .background(Color.red)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white, lineWidth: 2)
                )
        }
    }
}

/// Small dot indicator for unread content
struct UnreadDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 1)
            )
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 16) {
        UnreadBadge(count: 5)
        UnreadBadge(count: 99)
        UnreadBadge(count: 150)
        UnreadDot()
    }
    .padding()
}
