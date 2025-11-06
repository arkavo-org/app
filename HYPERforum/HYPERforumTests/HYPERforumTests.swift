import XCTest
@testable import HYPERforum

final class HYPERforumTests: XCTestCase {
    func testExample() throws {
        // This is an example of a functional test case.
        XCTAssertTrue(true)
    }

    func testAppStateInitialization() throws {
        let appState = AppState()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(appState.currentUser)
    }

    func testSignIn() throws {
        let appState = AppState()
        appState.signIn(user: "test@example.com")
        XCTAssertTrue(appState.isAuthenticated)
        XCTAssertEqual(appState.currentUser, "test@example.com")
    }

    func testSignOut() throws {
        let appState = AppState()
        appState.signIn(user: "test@example.com")
        appState.signOut()
        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(appState.currentUser)
    }
}
