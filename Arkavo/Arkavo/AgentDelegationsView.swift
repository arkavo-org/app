import ArkavoSocial
import SwiftUI

/// Seam so the cloud calls to `ArkavoIdentityClient` can be swapped for a
/// mock in tests. Signatures mirror `ArkavoIdentityClient.listDelegations()`
/// and `.revokeDelegation(did:)` exactly.
protocol DelegationListing: Sendable {
    func listDelegations() async throws -> [DelegationInfo]
    func revokeDelegation(did: String) async throws
}

extension ArkavoIdentityClient: DelegationListing {}

/// Seam so `AgentDelegationsViewModel` can be tested without a SwiftData
/// `ModelContainer`. A true subset of what `UnifiedContactService` already
/// provides -- no new behavior. Marked `@MainActor` because
/// `UnifiedContactService` is `@MainActor`-isolated: a nonisolated protocol
/// requirement cannot be satisfied by an actor-isolated stored property
/// under Swift 6 strict concurrency, so the protocol must share the same
/// isolation as the type it abstracts.
@MainActor
protocol DelegatedAgentStore: AnyObject {
    var allContacts: [Profile] { get }
    func deleteContact(_ profile: Profile) async throws
}

extension UnifiedContactService: DelegatedAgentStore {}

/// One row in the delegated-agents list: a server-known delegation, a
/// locally-persisted contact, or both joined by DID.
struct DelegationRow: Identifiable {
    /// The agent DID. Sourced from `info.agentDid` when a server delegation
    /// exists, otherwise from the local profile's DID.
    let id: String
    /// The server's view of this delegation. `nil` for `.localOnly` rows --
    /// there is no server record to show, and fabricating one (fake
    /// `createdAt`/`expiresAt`) would be worse than omitting it.
    let info: DelegationInfo?
    /// The locally-persisted contact for this agent, if one exists.
    let localProfile: Profile?
    var status: Status

    enum Status: Equatable {
        case active
        case expired
        case revoked
        case localOnly
    }
}

extension DelegationRow: Equatable {
    static func == (lhs: DelegationRow, rhs: DelegationRow) -> Bool {
        lhs.id == rhs.id
            && lhs.info == rhs.info
            && lhs.status == rhs.status
            && lhs.localProfile?.id == rhs.localProfile?.id
    }
}

/// Lists an account's delegated agents by reconciling the identity server's
/// `/agents/delegations` with locally-persisted `.delegatedAgent` contacts,
/// and revokes them.
@MainActor
final class AgentDelegationsViewModel: ObservableObject {
    @Published private(set) var rows: [DelegationRow] = []
    @Published var errorMessage: String?
    @Published private(set) var isLoading = false

    private let identity: any DelegationListing
    private let contacts: any DelegatedAgentStore

    init(identity: any DelegationListing, contacts: any DelegatedAgentStore) {
        self.identity = identity
        self.contacts = contacts
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let delegations = try await identity.listDelegations()
            rows = Self.reconcile(serverDelegations: delegations, localContacts: contacts.allContacts)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Revokes `row`. A `.localOnly` row has no server-side record to
    /// revoke, so only the local contact is removed. Otherwise the server
    /// delegation is revoked first; `.notFound` there means it is already
    /// gone (revoked elsewhere, or never persisted server-side after a
    /// partial failure) and is treated the same as success so the local
    /// contact doesn't get stranded -- mirroring how `authorizeAgent`
    /// treats 409 as already-authorized rather than an error. Any other
    /// server error aborts before the local contact is touched.
    func revoke(_ row: DelegationRow) async {
        errorMessage = nil
        do {
            if row.status != .localOnly {
                do {
                    try await identity.revokeDelegation(did: row.id)
                } catch ArkavoIdentityError.notFound {
                    // Already gone server-side; proceed to local cleanup.
                }
            }
            if let profile = row.localProfile {
                try await contacts.deleteContact(profile)
            }
            rows.removeAll { $0.id == row.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pure join: server delegations (`info`) to locally-persisted
    /// `.delegatedAgent` contacts, keyed by DID.
    ///
    /// - A server row with a matching local profile: `.revoked` if the
    ///   server marked it revoked, else `.expired` if `expiresAt` has
    ///   passed, else `.active`.
    /// - A local `.delegatedAgent` profile with a DID the server doesn't
    ///   know about: `.localOnly`.
    /// - Profiles with no DID, or whose `contactType` isn't
    ///   `.delegatedAgent`, are never joined or surfaced as `.localOnly` --
    ///   there is nothing safe to revoke or remove.
    static func reconcile(serverDelegations: [DelegationInfo], localContacts: [Profile], now: Date = Date()) -> [DelegationRow] {
        let delegatedContacts = localContacts.filter { $0.contactTypeEnum == .delegatedAgent }
        // `.unique` guards persisted SwiftData attributes, not this
        // in-memory join input -- fall back to the first match rather than
        // trapping on a duplicate DID.
        let localByDID = Dictionary(delegatedContacts.compactMap { profile -> (String, Profile)? in
            guard let did = profile.did else { return nil }
            return (did, profile)
        }, uniquingKeysWith: { first, _ in first })

        let serverRows = serverDelegations.map { info -> DelegationRow in
            let localProfile = localByDID[info.agentDid]
            let status: DelegationRow.Status
            if info.revoked {
                status = .revoked
            } else if let expiresAt = info.expiresAt, Double(expiresAt) < now.timeIntervalSince1970 {
                status = .expired
            } else {
                status = .active
            }
            return DelegationRow(id: info.agentDid, info: info, localProfile: localProfile, status: status)
        }

        let serverDIDs = Set(serverDelegations.map(\.agentDid))
        let localOnlyRows = delegatedContacts.compactMap { profile -> DelegationRow? in
            guard let did = profile.did, !serverDIDs.contains(did) else { return nil }
            return DelegationRow(id: did, info: nil, localProfile: profile, status: .localOnly)
        }

        return serverRows + localOnlyRows
    }
}

/// Displays and revokes the account's delegated agents.
struct AgentDelegationsView: View {
    @StateObject private var contactService: UnifiedContactService
    @StateObject private var viewModel: AgentDelegationsViewModel

    @State private var pendingRevoke: DelegationRow?
    @State private var showingRevokeConfirmation = false

    init(identity: any DelegationListing = ArkavoIdentityClient()) {
        let contacts = UnifiedContactService()
        _contactService = StateObject(wrappedValue: contacts)
        _viewModel = StateObject(wrappedValue: AgentDelegationsViewModel(identity: identity, contacts: contacts))
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if viewModel.rows.isEmpty && !viewModel.isLoading {
                Section {
                    Text("No delegated agents.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(viewModel.rows) { row in
                        DelegationRowView(row: row)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingRevoke = row
                                    showingRevokeConfirmation = true
                                } label: {
                                    Label(row.status == .localOnly ? "Remove" : "Revoke", systemImage: "xmark.circle.fill")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Delegated Agents")
        .overlay {
            if viewModel.isLoading && viewModel.rows.isEmpty {
                ProgressView()
            }
        }
        .task {
            await contactService.loadContacts()
            await viewModel.load()
        }
        .refreshable {
            await contactService.loadContacts()
            await viewModel.load()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showingRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button(pendingRevoke?.status == .localOnly ? "Remove" : "Revoke", role: .destructive) {
                if let pendingRevoke {
                    Task { await viewModel.revoke(pendingRevoke) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var confirmationTitle: String {
        guard let pendingRevoke else { return "" }
        let name = pendingRevoke.localProfile?.name ?? pendingRevoke.info?.name ?? "this agent"
        return pendingRevoke.status == .localOnly
            ? "Remove \(name)?"
            : "Revoke access for \(name)? This cannot be undone."
    }
}

private struct DelegationRowView: View {
    let row: DelegationRow

    private var entitlements: AgentEntitlements {
        if let info = row.info {
            return AgentEntitlements(from: info.entitlements)
        }
        return row.localProfile?.entitlements ?? AgentEntitlements()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.localProfile?.name ?? row.info?.name ?? row.id)
                    .fontWeight(.medium)
                Spacer()
                statusBadge
            }

            Text(row.id)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !entitlements.displayList.isEmpty {
                HStack(spacing: 8) {
                    ForEach(entitlements.displayList, id: \.1) { icon, label in
                        Label(label, systemImage: icon)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch row.status {
        case .active:
            Text("Active").font(.caption).foregroundStyle(.green)
        case .expired:
            Text("Expired").font(.caption).foregroundStyle(.orange)
        case .revoked:
            Text("Revoked").font(.caption).foregroundStyle(.red)
        case .localOnly:
            Text("Local only").font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        AgentDelegationsView()
    }
}
