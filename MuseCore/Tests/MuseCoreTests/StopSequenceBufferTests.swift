import XCTest
@testable import MuseCore

final class StopSequenceBufferTests: XCTestCase {
    // MARK: - Basic emission

    func testSingleChunkBelowHoldbackHoldsEverything() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"])
        let outcome = buffer.append("Hi")
        XCTAssertEqual(outcome, .emit(""), "Short chunks should hold back until safe")
    }

    func testEmitsOnceChunksExceedHoldback() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"]) // holdback = 13
        // Feed 20 chars of plain text; anything over 13 should spill out.
        let outcome = buffer.append("Hello there, friend!") // 20 chars
        guard case .emit(let text) = outcome else {
            return XCTFail("Expected emit, got \(outcome)")
        }
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue("Hello there, friend!".hasPrefix(text))
        XCTAssertEqual(text.count, 20 - "<end_of_turn>".count)
    }

    func testFlushReturnsRemainingText() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"])
        _ = buffer.append("Hi there")
        let flushed = buffer.flush()
        XCTAssertEqual(flushed, "Hi there")
    }

    // MARK: - Stop sequence detection

    func testTerminatesOnCompleteStopSequence() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"])
        _ = buffer.append("Hello world")
        let outcome = buffer.append("<end_of_turn>")
        guard case .terminate(let text) = outcome else {
            return XCTFail("Expected terminate, got \(outcome)")
        }
        // Terminate emits everything buffered that came *before* the stop sequence
        XCTAssertEqual(text, "Hello world")
    }

    func testPartialStopSequenceIsHeldBackAndCompletes() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"])

        var seen = ""
        for chunk in ["Goodbye", "<end_", "of_turn>"] {
            switch buffer.append(chunk) {
            case .emit(let t):
                seen += t
            case .terminate(let t):
                seen += t
                XCTAssertEqual(seen, "Goodbye", "Stop sequence prefix must never leak to consumer")
                return
            }
        }
        XCTFail("Expected termination once '<end_of_turn>' completes")
    }

    func testPartialStopSequenceThatTurnsOutToBeLiteralText() {
        // "<end_of_turns" (trailing 's') is NOT the stop sequence — it must emit.
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>"])
        var seen = ""

        for chunk in ["Text before ", "<end_of_turn", "s later"] {
            switch buffer.append(chunk) {
            case .emit(let t): seen += t
            case .terminate: return XCTFail("Should not terminate on near-miss")
            }
        }
        seen += buffer.flush()
        XCTAssertEqual(seen, "Text before <end_of_turns later")
    }

    // MARK: - Multiple stop sequences

    func testMultipleStopSequencesUsesLongestHoldback() {
        // "<end_of_turn>" is 13 chars, "<eos>" is 5 chars → holdback must be 13.
        // The invariant we care about is: no character of the completing stop
        // sequence ever leaks to the consumer.
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>", "<eos>"])
        var seen = ""

        for chunk in ["Partial", "<end_of", "_turn", ">"] {
            switch buffer.append(chunk) {
            case .emit(let t): seen += t
            case .terminate(let t):
                seen += t
                XCTAssertEqual(seen, "Partial", "Stop sequence must not leak")
                return
            }
        }
        XCTFail("Should have terminated once stop sequence completed")
    }

    func testTerminatesOnShortSecondaryStopSequence() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>", "<eos>"])
        _ = buffer.append("Done here")
        guard case .terminate(let text) = buffer.append("<eos>") else {
            return XCTFail("Should terminate on <eos>")
        }
        XCTAssertEqual(text, "Done here")
    }

    // MARK: - Flush defensiveness

    func testFlushStripsTrailingStopMarkers() {
        var buffer = StopSequenceBuffer(stopSequences: ["<end_of_turn>", "<eos>"])
        _ = buffer.append("Answer")
        // Simulate a case where chunks arrive but the buffer holds them,
        // then generation ends with a partial marker that the loop didn't
        // see as a complete stop — flush should clean it defensively.
        _ = buffer.append("<eos>x") // emits as it turns out to be literal text
        let flushed = buffer.flush()
        XCTAssertFalse(flushed.contains("<eos>"))
    }

    // MARK: - Invariants

    func testStopSequenceNeverLeaksAcrossSplits() {
        // Property-like: for any split of a terminating output, the consumer
        // should never see any character of the stop marker.
        let stop = "<end_of_turn>"
        let generated = "Hello!" + stop
        let splits: [[String]] = [
            [generated],
            Array(generated.map { String($0) }),
            [String(generated.prefix(3)), String(generated.dropFirst(3).prefix(4)), String(generated.dropFirst(7))],
        ]

        for split in splits {
            var buffer = StopSequenceBuffer(stopSequences: [stop])
            var seen = ""
            var terminated = false
            for chunk in split {
                switch buffer.append(chunk) {
                case .emit(let t): seen += t
                case .terminate(let t):
                    seen += t
                    terminated = true
                }
                if terminated { break }
            }
            XCTAssertTrue(terminated, "Split \(split) should terminate")
            XCTAssertEqual(seen, "Hello!", "Stop marker leaked for split \(split): got '\(seen)'")
        }
    }
}
