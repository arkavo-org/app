import XCTest
@testable import ArkavoSocial

final class PlatformTokenProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Human token wins whenever it exists

    func test_humanPresentAndDeviceFresh_returnsHumanToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(60)) },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "human-token")
    }

    func test_humanPresentAndDeviceExpired_returnsHumanToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(-60)) },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "human-token")
    }

    func test_humanPresentAndDeviceExpiryExactlyNow_returnsHumanToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now) },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "human-token")
    }

    func test_deviceAbsent_returnsHumanToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { nil },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "human-token")
    }

    // MARK: - Device token is the signed-out fallback only

    func test_humanAbsentAndDeviceFresh_returnsDeviceToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(60)) },
            human: { nil }
        )
        XCTAssertEqual(result, "device-token")
    }

    func test_humanAbsentAndDeviceExpired_returnsNil() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(-60)) },
            human: { nil }
        )
        XCTAssertNil(result)
    }

    /// The strict-`>` expiry boundary is only observable when there is no human
    /// token to fall back from, so it is asserted here: an expiry exactly equal
    /// to `now` counts as expired.
    func test_humanAbsentAndDeviceExpiryExactlyNow_treatedAsExpired_returnsNil() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now) },
            human: { nil }
        )
        XCTAssertNil(result)
    }

    func test_neitherPresent_returnsNil() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { nil },
            human: { nil }
        )
        XCTAssertNil(result)
    }
}
