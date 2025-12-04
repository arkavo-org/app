import ArkavoKit
import ArkavoSocial
import XCTest

/// Integration tests that verify connectivity to the Arkavo backend server
/// These tests require network access and a running server at wss://100.arkavo.net
class ServerConnectivityIntegrationTests: XCTestCase {
    // MARK: - Properties

    var client: ArkavoClient!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Initialize the ArkavoClient with configuration
        let config = ArkavoConfiguration.shared
        client = ArkavoClient(
            authURL: config.identityURL,
            websocketURL: config.websocketURL,
            relyingPartyID: config.relyingPartyID,
            curve: .p256
        )
    }

    override func tearDown() async throws {
        // Ensure we disconnect after each test
        if client.connectionState == .connected {
            client.disconnect()
        }
        client = nil
        try await super.tearDown()
    }

    // MARK: - Integration Tests

    /// Test basic WebSocket connectivity to the server
    /// This test verifies that we can establish a WebSocket connection
    func testWebSocketConnectivity() async throws {
        // Skip this test in CI or when running unit tests only
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true",
                          "Integration tests are disabled. Set RUN_INTEGRATION_TESTS=true to run.")

        let expectation = XCTestExpectation(description: "WebSocket connection established")

        do {
            // Attempt to connect without authentication
            // This should fail with authentication error, but proves network connectivity
            try await client.connect(accountName: "test-user")

            // If we get here, connection succeeded (unlikely without auth)
            XCTAssertEqual(client.connectionState, .connected, "Client should be connected")
            expectation.fulfill()

        } catch let error as ArkavoError {
            // Expected errors that still prove connectivity
            switch error {
            case let .authenticationFailed(message):
                print("✅ Server reachable - Authentication failed as expected: \(message)")
                expectation.fulfill()
            case let .connectionFailed(message):
                if message.contains("401") || message.contains("Unauthorized") {
                    print("✅ Server reachable - Got 401 Unauthorized as expected")
                    expectation.fulfill()
                } else {
                    XCTFail("❌ Connection failed: \(message)")
                }
            default:
                XCTFail("❌ Unexpected error type: \(error)")
            }
        } catch {
            XCTFail("❌ Network connectivity issue: \(error.localizedDescription)")
        }

        await fulfillment(of: [expectation], timeout: 10.0)
    }

    /// Test that we can reach the authentication endpoint
    func testAuthEndpointReachability() async throws {
        // Skip this test in CI or when running unit tests only
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true",
                          "Integration tests are disabled. Set RUN_INTEGRATION_TESTS=true to run.")

        let authURL = ArkavoConfiguration.shared.identityURL
        var request = URLRequest(url: authURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                print("✅ Auth endpoint reachable - Status code: \(httpResponse.statusCode)")

                // We expect some response, even if it's an error
                // 404, 405, or 401 all indicate the server is reachable
                XCTAssertTrue(httpResponse.statusCode > 0, "Should get a valid HTTP response")
            }
        } catch {
            XCTFail("❌ Cannot reach auth endpoint: \(error.localizedDescription)")
        }
    }

    /// Test DNS resolution for the server domain
    func testDNSResolution() async throws {
        // Skip this test in CI or when running unit tests only
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true",
                          "Integration tests are disabled. Set RUN_INTEGRATION_TESTS=true to run.")

        let host = "100.arkavo.net"
        let hostRef = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()

        var resolved = false
        let context = CFHostClientContext()

        CFHostSetClient(hostRef, { _, _, _, _ in
            // Callback when resolution completes
        }, &context)

        CFHostScheduleWithRunLoop(hostRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        var error = CFStreamError()
        resolved = CFHostStartInfoResolution(hostRef, .addresses, &error)

        if resolved {
            if let addresses = CFHostGetAddressing(hostRef, nil)?.takeUnretainedValue() as? [Data] {
                XCTAssertFalse(addresses.isEmpty, "Should resolve to at least one IP address")

                for addressData in addresses {
                    // Convert to readable IP address
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    addressData.withUnsafeBytes { ptr in
                        guard let baseAddress = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                        getnameinfo(baseAddress, socklen_t(addressData.count),
                                    &hostname, socklen_t(hostname.count),
                                    nil, 0, NI_NUMERICHOST)
                    }
                    let ipAddress = String(cString: hostname)
                    print("✅ DNS resolved to: \(ipAddress)")
                }
            }
        } else {
            XCTFail("❌ DNS resolution failed for \(host)")
        }

        CFHostUnscheduleFromRunLoop(hostRef, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    /// Test network reachability from simulator
    func testNetworkReachability() async throws {
        // Skip this test in CI or when running unit tests only
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_INTEGRATION_TESTS"] == "true",
                          "Integration tests are disabled. Set RUN_INTEGRATION_TESTS=true to run.")

        // Test general internet connectivity first
        let googleURL = URL(string: "https://www.google.com")!
        var request = URLRequest(url: googleURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("✅ General internet connectivity OK - Google returned: \(httpResponse.statusCode)")
                XCTAssertEqual(httpResponse.statusCode, 200, "Google should be reachable")
            }
        } catch {
            XCTFail("❌ No internet connectivity: \(error.localizedDescription)")
        }
    }
}

// MARK: - Test Runner Helper

extension ServerConnectivityIntegrationTests {
    /// Helper to run all integration tests
    /// Usage: Set environment variable RUN_INTEGRATION_TESTS=true before running
    static func runIntegrationTests() {
        print("""

        ========================================
        Running Server Connectivity Integration Tests
        ========================================

        To run these tests:
        1. In Xcode: Edit Scheme > Test > Arguments > Environment Variables
        2. Add: RUN_INTEGRATION_TESTS = true
        3. Or run from command line:
           RUN_INTEGRATION_TESTS=true xcodebuild test -workspace Arkavo.xcworkspace -scheme Arkavo -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:ArkavoTests/ServerConnectivityIntegrationTests

        """)
    }
}
