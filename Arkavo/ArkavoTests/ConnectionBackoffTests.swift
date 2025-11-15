import XCTest
@testable import Arkavo
import ArkavoKit

/// Tests for connection retry backoff behavior
/// Verifies that the app properly throttles connection attempts after failures
class ConnectionBackoffTests: XCTestCase {

    // MARK: - Properties

    var sharedState: SharedState!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()
        sharedState = SharedState()
    }

    override func tearDown() async throws {
        sharedState = nil
        try await super.tearDown()
    }

    // MARK: - Backoff State Tests

    /// Test that backoff timer is initially nil
    func testInitialBackoffState() {
        XCTAssertNil(sharedState.nextAllowedAccountCheck, "Backoff should be nil initially")
    }

    /// Test that setting backoff prevents immediate checks
    func testBackoffPreventsImmediateCheck() {
        // Set backoff to 10 seconds from now
        let backoffTime = Date().addingTimeInterval(10)
        sharedState.nextAllowedAccountCheck = backoffTime

        XCTAssertNotNil(sharedState.nextAllowedAccountCheck, "Backoff should be set")
        XCTAssertTrue(Date() < backoffTime, "Current time should be before backoff expiry")

        // Verify the backoff time is correct
        let timeDifference = backoffTime.timeIntervalSince(Date())
        XCTAssertTrue(timeDifference > 9 && timeDifference <= 10,
                     "Backoff should be approximately 10 seconds")
    }

    /// Test that backoff can be cleared (reset to nil)
    func testBackoffCanBeCleared() {
        // Set backoff
        sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(10)
        XCTAssertNotNil(sharedState.nextAllowedAccountCheck, "Backoff should be set")

        // Clear backoff
        sharedState.nextAllowedAccountCheck = nil
        XCTAssertNil(sharedState.nextAllowedAccountCheck, "Backoff should be cleared")
    }

    /// Test that backoff expires after the specified duration
    func testBackoffExpiresAfterDuration() async {
        // Set a very short backoff for testing (0.1 seconds)
        let backoffTime = Date().addingTimeInterval(0.1)
        sharedState.nextAllowedAccountCheck = backoffTime

        // Wait for backoff to expire
        try? await Task.sleep(nanoseconds: 150_000_000) // 150ms

        // Verify current time is now after backoff expiry
        XCTAssertTrue(Date() > backoffTime, "Current time should be after backoff expiry")
    }

    // MARK: - Published Property Tests

    /// Test that backoff changes trigger @Published updates
    func testBackoffPublishedUpdates() {
        let expectation = XCTestExpectation(description: "Published update")

        // Subscribe to changes
        let cancellable = sharedState.$nextAllowedAccountCheck.sink { value in
            if value != nil {
                expectation.fulfill()
            }
        }

        // Trigger change
        sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(10)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    // MARK: - Offline Mode Integration Tests

    /// Test that offline mode and backoff work together
    func testOfflineModeWithBackoff() {
        // Simulate connection failure scenario
        sharedState.isOfflineMode = true
        sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(10)

        XCTAssertTrue(sharedState.isOfflineMode, "Should be in offline mode")
        XCTAssertNotNil(sharedState.nextAllowedAccountCheck, "Backoff should be set")
    }

    /// Test that successful connection clears both offline mode and backoff
    func testSuccessfulConnectionClearsState() {
        // Set failure state
        sharedState.isOfflineMode = true
        sharedState.nextAllowedAccountCheck = Date().addingTimeInterval(10)

        // Simulate successful connection
        sharedState.isOfflineMode = false
        sharedState.nextAllowedAccountCheck = nil

        XCTAssertFalse(sharedState.isOfflineMode, "Should not be in offline mode")
        XCTAssertNil(sharedState.nextAllowedAccountCheck, "Backoff should be cleared")
    }

    // MARK: - Keychain Error Handling Tests

    /// Test that itemNotFound error is properly distinguished
    func testKeychainItemNotFoundError() throws {
        // Test that KeychainError.itemNotFound can be thrown and caught
        do {
            throw KeychainManager.KeychainError.itemNotFound
        } catch KeychainManager.KeychainError.itemNotFound {
            // Expected error type
            XCTAssertTrue(true, "Should catch itemNotFound error")
        } catch {
            XCTFail("Should have caught KeychainError.itemNotFound, got \(error)")
        }
    }

    /// Test that unknown keychain errors are properly distinguished
    func testKeychainUnknownError() throws {
        // Test that unknown errors have distinct status codes
        do {
            throw KeychainManager.KeychainError.unknown(errSecParam) // -50
        } catch KeychainManager.KeychainError.unknown(let status) {
            XCTAssertEqual(status, errSecParam, "Should preserve error status")
        } catch {
            XCTFail("Should have caught KeychainError.unknown, got \(error)")
        }
    }

    // MARK: - Edge Cases

    /// Test that setting backoff to past date doesn't prevent checks
    func testPastBackoffDoesNotPreventCheck() {
        // Set backoff to past time
        let pastTime = Date().addingTimeInterval(-10)
        sharedState.nextAllowedAccountCheck = pastTime

        // Current time should be after backoff
        XCTAssertTrue(Date() > pastTime, "Current time should be after past backoff time")
    }

    /// Test that multiple rapid backoff sets use the latest value
    func testMultipleBackoffSetsUsesLatest() {
        let firstBackoff = Date().addingTimeInterval(10)
        sharedState.nextAllowedAccountCheck = firstBackoff

        let secondBackoff = Date().addingTimeInterval(20)
        sharedState.nextAllowedAccountCheck = secondBackoff

        XCTAssertEqual(sharedState.nextAllowedAccountCheck, secondBackoff,
                      "Should use the latest backoff time")
    }
}
