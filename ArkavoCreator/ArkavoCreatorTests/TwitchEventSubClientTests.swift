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

    /// Reconnect path must NOT finish the events stream — consumers should
    /// keep iterating across transport teardowns. We simulate the underlying
    /// transport teardown that reconnect() performs (via the internal helper)
    /// and then race the iterator's next() against a short timer. A finished
    /// AsyncStream returns nil from next() immediately; a live one suspends
    /// until cancelled. The timer must win.
    func testEventStreamSurvivesTransportTeardown() async {
        let client = makeClient()
        let stream = client.events

        client.tearDownConnection()

        let winner = await withTaskGroup(of: String.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                _ = await iterator.next()
                return "stream-finished"
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(150))
                return "still-suspended"
            }
            let first = await group.next() ?? "no-result"
            group.cancelAll()
            // Drain remaining children to avoid leaking the iterator pull task.
            for await _ in group { }
            return first
        }

        XCTAssertEqual(winner, "still-suspended",
                       "tearDownConnection() must not finish the events stream — \(winner)")
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
