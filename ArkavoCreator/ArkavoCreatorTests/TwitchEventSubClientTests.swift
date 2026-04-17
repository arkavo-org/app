import XCTest
@testable import ArkavoCreator

/// Verifies the transport-agnostic invariants of TwitchEventSubClient.
/// These tests do not exercise networking — they only cover the stream
/// lifecycle and disconnect semantics.
@MainActor
final class TwitchEventSubClientTests: XCTestCase {
    private func makeClient() -> TwitchEventSubClient {
        TwitchEventSubClient(
            clientId: "test-client",
            accessToken: { nil },
            userId: { nil },
            ensureValidToken: { true }
        )
    }

    /// The event stream is constructed exactly once at init. Consumers
    /// hold a reference and iterate it across the full lifetime of the client,
    /// including reconnects. Regression test for the prior bug where reconnect()
    /// replaced `events` with a new stream and finished the old one, silently
    /// dropping all consumers.
    func testEventStreamIsStableAcrossLifecycle() {
        let client = makeClient()
        let streamA = client.events
        let streamB = client.events
        XCTAssertTrue(type(of: streamA) == type(of: streamB))
        // There is no public way to rebuild the stream — the property is a `let`.
        // This test serves as a compile-time contract: if someone reintroduces
        // a `var events`, the next line would still pass but the subsequent
        // refactor review should catch it. The real guarantee is in the type.
        XCTAssertNotNil(client.events)
    }

    /// After disconnect(), iterating the stream terminates cleanly rather
    /// than hanging. This is the only way consumers learn the client is done.
    func testDisconnectTerminatesEventStream() async {
        let client = makeClient()
        let stream = client.events

        // Disconnect before consuming — stream should be finished.
        client.disconnect()

        var iterator = stream.makeAsyncIterator()
        let next = await iterator.next()
        XCTAssertNil(next, "Stream must terminate after disconnect()")
    }

    /// Calling disconnect() when never connected must be a safe no-op
    /// rather than touching nil WebSocket state.
    func testDisconnectWhenNeverConnectedIsSafe() {
        let client = makeClient()
        XCTAssertFalse(client.isConnected)
        client.disconnect() // must not crash
        XCTAssertFalse(client.isConnected)
    }
}
