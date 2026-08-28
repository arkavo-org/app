import ArkavoSocial
import CryptoKit
import DeviceCheck
import Foundation
import UIKit

/// Seam over `DCAppAttestService` so tests can drive a `MockAppAttest` instead
/// of the real, simulator-unavailable API. Signatures mirror the three
/// `DCAppAttestService` operations this service needs.
protocol AppAttestProviding: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// Thin wrapper around `DCAppAttestService.shared`. `DCAppAttestService` is a
/// plain (non-Sendable-annotated) class, so this struct is `@unchecked
/// Sendable`: Apple's completion-handler/async APIs are documented safe to
/// call from any thread, and `.shared` is itself a singleton with no mutable
/// state this type touches directly.
///
/// `isSupported` is `false` on the simulator (no Secure Enclave attestation
/// key) and on any device without one -- every method below is only ever
/// called after `DeviceAttestationService` has checked `isSupported`, so a
/// simulator run never reaches into `DCAppAttestService` at all.
struct DCAppAttestProvider: AppAttestProviding, @unchecked Sendable {
    private let service: DCAppAttestService

    init(service: DCAppAttestService = .shared) {
        self.service = service
    }

    var isSupported: Bool { service.isSupported }

    func generateKey() async throws -> String {
        try await service.generateKey()
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

/// Seam so the cloud calls to `ArkavoIdentityClient` can be swapped for a
/// mock in tests. Signatures mirror `ArkavoIdentityClient`'s `/device-check/*`
/// methods exactly -- see `device-check-contract.md` for the wire shapes.
protocol DeviceCheckIdentity: Sendable {
    func deviceCheckChallenge(username: String) async throws -> String
    func deviceCheckAttest(keyId: String, attestationObject: Data, clientDataHash: Data) async throws
    func deviceCheckAssertChallenge(username: String) async throws -> String
    func deviceCheckAssert(keyId: String, assertion: Data, clientDataHash: Data) async throws -> String
}

extension ArkavoIdentityClient: DeviceCheckIdentity {}

/// Persists the App Attest key id (`DCAppAttestService.generateKey()`'s
/// result) in keychain account `app_attest_key_id` -- separate from both
/// `authentication_token` and `device_attestation_token`. A struct of
/// closures, not a protocol, so tests can substitute in-memory storage
/// without touching the real keychain.
struct DeviceKeyIdStore: Sendable {
    var get: @Sendable () -> String?
    var save: @Sendable (String) -> Void
    var delete: @Sendable () -> Void

    static let keychain = DeviceKeyIdStore(
        get: { KeychainManager.getAppAttestKeyId() },
        save: { keyId in try? KeychainManager.saveAppAttestKeyId(keyId) },
        delete: { KeychainManager.deleteAppAttestKeyId() }
    )
}

/// Errors raised by `DeviceAttestationService` itself, as opposed to errors
/// surfaced by `DCAppAttestService` or the identity server.
enum DeviceAttestationError: LocalizedError, Equatable {
    /// No signed-in account name was available to build a `/device-check/*`
    /// challenge path from.
    case noUsername
    /// A key id was expected to be in the keychain (e.g. right after a
    /// successful re-attestation) but was not.
    case noKeyId

    var errorDescription: String? {
        switch self {
        case .noUsername: return "No signed-in account name available for device attestation."
        case .noKeyId: return "No App Attest key id available after attestation."
        }
    }
}

/// Obtains and refreshes the device CWT (`aud` includes `arkavo:devicecheck`)
/// via Apple App Attest: a one-time key generation + attestation, followed by
/// periodic assertion refreshes that mint a fresh device CWT. The device CWT
/// is stored in `KeychainManager`'s `device_attestation_token` slot -- never
/// in `authentication_token` -- where `PlatformTokenProvider` picks it up.
///
/// No-ops everywhere when `attest.isSupported` is `false` (the simulator, or
/// any device without a Secure Enclave attestation key): `ensureAttested()`
/// and `refreshAssertion()` return immediately without throwing, and
/// `start()` never spins up its refresh loop.
@MainActor
final class DeviceAttestationService: ObservableObject {
    /// Device CWT lifetime per `device-check-contract.md`: `mint_assertion_token`
    /// uses `AUTH_TOKEN_HOURS` = 1.
    private static let deviceTokenLifetime: TimeInterval = 60 * 60
    /// Refresh cadence while foregrounded, well inside the 1-hour token lifetime.
    private static let refreshInterval: Duration = .seconds(10 * 60)

    private let attest: any AppAttestProviding
    private let identity: any DeviceCheckIdentity
    private let username: @Sendable () -> String?
    private let keychain: DeviceKeyIdStore

    @Published var lastError: Error?

    private var isForeground = true
    private var loopTask: Task<Void, Never>?
    private var foregroundObservationTask: Task<Void, Never>?
    private var backgroundObservationTask: Task<Void, Never>?

    init(
        attest: any AppAttestProviding = DCAppAttestProvider(),
        identity: any DeviceCheckIdentity = ArkavoIdentityClient(),
        username: @escaping @Sendable () -> String? = { KeychainManager.getArkavoHandle() },
        keychain: DeviceKeyIdStore = .keychain
    ) {
        self.attest = attest
        self.identity = identity
        self.username = username
        self.keychain = keychain
    }

    deinit {
        loopTask?.cancel()
        foregroundObservationTask?.cancel()
        backgroundObservationTask?.cancel()
    }

    // MARK: - One-time attestation

    /// Generates a key and attests it with the server exactly once. A second
    /// call is a no-op as long as a key id is already persisted -- App Attest
    /// key generation is meant to happen once per device/app install.
    func ensureAttested() async throws {
        guard attest.isSupported else { return }
        guard keychain.get() == nil else { return }
        try await performAttestation()
    }

    private func performAttestation() async throws {
        guard let name = username() else { throw DeviceAttestationError.noUsername }
        let challenge = try await identity.deviceCheckChallenge(username: name)
        let clientDataHash = Self.hash(challenge)
        let keyId = try await attest.generateKey()
        let attestationObject = try await attest.attestKey(keyId, clientDataHash: clientDataHash)
        try await identity.deviceCheckAttest(keyId: keyId, attestationObject: attestationObject, clientDataHash: clientDataHash)
        keychain.save(keyId)
    }

    // MARK: - Assertion refresh

    /// Mints a fresh device CWT via `generateAssertion` and stores it. If the
    /// server reports the persisted key id as unknown (attest state cleared
    /// server-side, or a stale/corrupt local key id), clears it and
    /// re-attests exactly once before retrying -- it does not loop.
    func refreshAssertion() async throws {
        guard attest.isSupported else { return }

        let keyId: String
        if let existing = keychain.get() {
            keyId = existing
        } else {
            try await performAttestation()
            guard let generated = keychain.get() else { throw DeviceAttestationError.noKeyId }
            keyId = generated
        }

        do {
            try await performAssertion(keyId: keyId)
        } catch let error where Self.isUnknownKeyId(error) {
            keychain.delete()
            try await performAttestation()
            guard let newKeyId = keychain.get() else { throw error }
            try await performAssertion(keyId: newKeyId)
        }
    }

    private func performAssertion(keyId: String) async throws {
        guard let name = username() else { throw DeviceAttestationError.noUsername }
        let challenge = try await identity.deviceCheckAssertChallenge(username: name)
        let clientDataHash = Self.hash(challenge)
        let assertion = try await attest.generateAssertion(keyId, clientDataHash: clientDataHash)
        let token = try await identity.deviceCheckAssert(keyId: keyId, assertion: assertion, clientDataHash: clientDataHash)
        try KeychainManager.saveDeviceAttestationToken(token, expiresAt: Date().addingTimeInterval(Self.deviceTokenLifetime))
    }

    /// A `.notFound` (404) or `.server(400, _)` from the assert call means
    /// the server doesn't recognize this key id -- distinct from every other
    /// failure mode, which should propagate rather than trigger a re-attest.
    private static func isUnknownKeyId(_ error: Error) -> Bool {
        guard let identityError = error as? ArkavoIdentityError else { return false }
        switch identityError {
        case .notFound: return true
        case .server(400, _): return true
        default: return false
        }
    }

    private static func hash(_ challenge: String) -> Data {
        Data(SHA256.hash(data: Data(challenge.utf8)))
    }

    // MARK: - Lifecycle

    /// Idempotent: attest once, refresh immediately (so the device CWT slot
    /// is populated right away rather than sitting empty for the first
    /// refresh interval), then keep refreshing every `refreshInterval` while
    /// the app is foregrounded. On an unsupported device this never starts
    /// the loop at all.
    func start() {
        guard attest.isSupported else { return }
        guard loopTask == nil else { return }

        observeForegroundState()
        loopTask = Task { [weak self] in
            guard let self else { return }
            await self.runLoop()
        }
    }

    private func runLoop() async {
        do {
            try await ensureAttested()
            try await refreshAssertion()
        } catch {
            lastError = error
        }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.refreshInterval)
            } catch {
                break // cancelled during sleep
            }
            guard !Task.isCancelled, isForeground else { continue }
            do {
                try await refreshAssertion()
            } catch {
                lastError = error
            }
        }
    }

    private func observeForegroundState() {
        foregroundObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                self?.isForeground = true
            }
        }
        backgroundObservationTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.willResignActiveNotification) {
                self?.isForeground = false
            }
        }
    }
}
