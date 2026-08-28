import ArkavoSocial
import XCTest
@testable import Arkavo

@MainActor
final class AgentDelegationsViewModelTests: XCTestCase {

    // MARK: - Reconciliation

    func test_load_reconcilesServerAndLocal() async throws {
        // Local .delegatedAgent contacts: one matches an active server
        // delegation, one matches a revoked server delegation, one has no
        // server row at all (localOnly).
        let activeProfile = Profile.createAgentProfile(
            agentID: "agent1", name: "Agent One", did: "did:key:agent1",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent,
            entitlements: AgentEntitlements(read: true)
        )
        let revokedProfile = Profile.createAgentProfile(
            agentID: "agent2", name: "Agent Two", did: "did:key:agent2",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent
        )
        let localOnlyProfile = Profile.createAgentProfile(
            agentID: "agent3", name: "Local Only Agent", did: "did:key:local-only",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent
        )
        // A human contact that happens to share a DID with a server
        // delegation must never be joined to it (only .delegatedAgent
        // profiles are eligible).
        let humanWithSameDID = Profile(name: "A Human")
        humanWithSameDID.did = "did:key:agent4"

        let store = MockDelegatedAgentStore()
        store.allContacts = [activeProfile, revokedProfile, localOnlyProfile, humanWithSameDID]

        let now = Int64(Date().timeIntervalSince1970)
        let identity = MockDelegationListing()
        identity.delegations = [
            try makeDelegationInfo(agentDid: "did:key:agent1", name: "Agent One", entitlements: ["read"], createdAt: now - 1000, expiresAt: nil, revoked: false),
            try makeDelegationInfo(agentDid: "did:key:agent2", name: "Agent Two", createdAt: now - 1000, expiresAt: nil, revoked: true),
            try makeDelegationInfo(agentDid: "did:key:agent4", name: "Expired Agent", createdAt: now - 5000, expiresAt: now - 10, revoked: false),
        ]

        let viewModel = AgentDelegationsViewModel(identity: identity, contacts: store)
        await viewModel.load()

        XCTAssertEqual(viewModel.rows.count, 4, "3 server rows + 1 local-only row")

        let byId = Dictionary(uniqueKeysWithValues: viewModel.rows.map { ($0.id, $0) })

        XCTAssertEqual(byId["did:key:agent1"]?.status, .active)
        XCTAssertEqual(byId["did:key:agent1"]?.localProfile?.name, "Agent One")

        XCTAssertEqual(byId["did:key:agent2"]?.status, .revoked)
        XCTAssertEqual(byId["did:key:agent2"]?.localProfile?.name, "Agent Two")

        XCTAssertEqual(byId["did:key:agent4"]?.status, .expired)
        XCTAssertNil(byId["did:key:agent4"]?.localProfile, "server row must not join to a human profile sharing its DID")

        XCTAssertEqual(byId["did:key:local-only"]?.status, .localOnly)
        XCTAssertEqual(byId["did:key:local-only"]?.localProfile?.name, "Local Only Agent")
        XCTAssertNil(byId["did:key:local-only"]?.info)
    }

    func test_load_surfacesServerError() async throws {
        let store = MockDelegatedAgentStore()
        let identity = MockDelegationListing()
        identity.listError = ArkavoIdentityError.unauthorized

        let viewModel = AgentDelegationsViewModel(identity: identity, contacts: store)
        await viewModel.load()

        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    // MARK: - Revoke

    func test_revoke_callsServerThenDeletesLocal() async throws {
        let profile = Profile.createAgentProfile(
            agentID: "agent1", name: "Agent One", did: "did:key:agent1",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent
        )
        let store = MockDelegatedAgentStore()
        store.allContacts = [profile]

        let identity = MockDelegationListing()
        identity.delegations = [try makeDelegationInfo(agentDid: "did:key:agent1", name: "Agent One", revoked: false)]

        let recorder = CallRecorder()
        identity.recorder = recorder
        store.recorder = recorder

        let viewModel = AgentDelegationsViewModel(identity: identity, contacts: store)
        await viewModel.load()

        let row = try XCTUnwrap(viewModel.rows.first { $0.id == "did:key:agent1" })
        await viewModel.revoke(row)

        XCTAssertEqual(recorder.calls, ["revoke:did:key:agent1", "delete:did:key:agent1"], "server revoke must happen before the local contact is deleted")
        XCTAssertEqual(identity.revokedDIDs, ["did:key:agent1"])
        XCTAssertTrue(store.deletedProfiles.contains { $0 === profile })
        XCTAssertFalse(viewModel.rows.contains { $0.id == "did:key:agent1" })
    }

    func test_revoke_serverFailureDoesNotDeleteLocal() async throws {
        let profile = Profile.createAgentProfile(
            agentID: "agent1", name: "Agent One", did: "did:key:agent1",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent
        )
        let store = MockDelegatedAgentStore()
        store.allContacts = [profile]

        let identity = MockDelegationListing()
        identity.delegations = [try makeDelegationInfo(agentDid: "did:key:agent1", name: "Agent One", revoked: false)]
        identity.revokeError = ArkavoIdentityError.forbidden("nope")

        let viewModel = AgentDelegationsViewModel(identity: identity, contacts: store)
        await viewModel.load()
        let row = try XCTUnwrap(viewModel.rows.first { $0.id == "did:key:agent1" })
        await viewModel.revoke(row)

        XCTAssertTrue(store.deletedProfiles.isEmpty, "a server failure must not delete the local contact")
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.rows.contains { $0.id == "did:key:agent1" }, "row should remain after a failed revoke")
    }

    func test_revoke_localOnlySkipsServerCall() async throws {
        let profile = Profile.createAgentProfile(
            agentID: "agent3", name: "Local Only Agent", did: "did:key:local-only",
            purpose: nil, model: nil, endpoint: nil, contactType: .delegatedAgent
        )
        let store = MockDelegatedAgentStore()
        store.allContacts = [profile]
        let identity = MockDelegationListing()

        let viewModel = AgentDelegationsViewModel(identity: identity, contacts: store)
        await viewModel.load()
        let row = try XCTUnwrap(viewModel.rows.first { $0.id == "did:key:local-only" })
        XCTAssertEqual(row.status, .localOnly)

        await viewModel.revoke(row)

        XCTAssertTrue(identity.revokedDIDs.isEmpty, "there is no server record for a local-only row")
        XCTAssertTrue(store.deletedProfiles.contains { $0 === profile })
    }
}

// MARK: - Test helpers

/// Builds a `DelegationInfo` by round-tripping real wire JSON through
/// `JSONDecoder`, since the type's memberwise initializer is internal to
/// ArkavoSocial (public structs don't get a public memberwise init for
/// free) while its `Decodable` synthesis is public.
private func makeDelegationInfo(
    agentDid: String,
    name: String,
    entitlements: [String] = [],
    depth: Int = 1,
    createdAt: Int64 = 0,
    expiresAt: Int64? = nil,
    revoked: Bool
) throws -> DelegationInfo {
    var dict: [String: Any] = [
        "agent_did": agentDid,
        "name": name,
        "entitlements": entitlements,
        "depth": depth,
        "created_at": createdAt,
        "revoked": revoked,
    ]
    if let expiresAt {
        dict["expires_at"] = expiresAt
    }
    let data = try JSONSerialization.data(withJSONObject: dict)
    return try JSONDecoder().decode(DelegationInfo.self, from: data)
}

/// Records cross-mock call order so tests can assert "server before local".
final class CallRecorder: @unchecked Sendable {
    var calls: [String] = []
}

final class MockDelegationListing: DelegationListing, @unchecked Sendable {
    var delegations: [DelegationInfo] = []
    var listError: Error?
    var revokeError: Error?
    var recorder: CallRecorder?
    private(set) var revokedDIDs: [String] = []

    func listDelegations() async throws -> [DelegationInfo] {
        if let listError { throw listError }
        return delegations
    }

    func revokeDelegation(did: String) async throws {
        recorder?.calls.append("revoke:\(did)")
        if let revokeError { throw revokeError }
        revokedDIDs.append(did)
    }
}

@MainActor
final class MockDelegatedAgentStore: DelegatedAgentStore {
    var allContacts: [Profile] = []
    var deleteError: Error?
    var recorder: CallRecorder?
    private(set) var deletedProfiles: [Profile] = []

    func deleteContact(_ profile: Profile) async throws {
        recorder?.calls.append("delete:\(profile.did ?? "nil")")
        if let deleteError { throw deleteError }
        deletedProfiles.append(profile)
        allContacts.removeAll { $0 === profile }
    }
}
