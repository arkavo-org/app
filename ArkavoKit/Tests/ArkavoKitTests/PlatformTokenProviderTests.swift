import XCTest
@testable import ArkavoSocial

final class PlatformTokenProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_devicePresentAndFresh_returnsDeviceToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(60)) },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "device-token")
    }

    func test_devicePresentButExpired_returnsHumanToken() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { (token: "device-token", expiresAt: self.now.addingTimeInterval(-60)) },
            human: { "human-token" }
        )
        XCTAssertEqual(result, "human-token")
    }

    func test_neitherPresent_returnsNil() {
        let result = PlatformTokenProvider.bearerForPlatform(
            now: now,
            device: { nil },
            human: { nil }
        )
        XCTAssertNil(result)
    }

    func test_deviceExpiryExactlyNow_treatedAsExpired_returnsHumanToken() {
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
}
