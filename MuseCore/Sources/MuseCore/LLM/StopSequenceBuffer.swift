import Foundation

/// Pure, testable helper for streaming token output with stop-sequence detection.
///
/// Generates may emit tokens that *partially* match a stop sequence (e.g. the
/// chunk "<end_of" arrives before "<end_of_turn>" completes). If we emit that
/// text immediately, the caller sees garbage before we realize it was actually
/// a stop sequence. This buffer holds back the tail of the accumulated text —
/// up to the length of the stop sequence — until either the full sequence
/// appears (terminates) or enough clean text accumulates that the buffered
/// portion can't possibly be the start of a stop sequence.
struct StopSequenceBuffer {
    /// All stop sequences that should terminate generation.
    /// The first is the "primary" sequence used for holdback sizing.
    let stopSequences: [String]

    private var pending: String = ""
    private let holdBack: Int

    init(stopSequences: [String]) {
        precondition(!stopSequences.isEmpty, "Must provide at least one stop sequence")
        self.stopSequences = stopSequences
        self.holdBack = stopSequences.map(\.count).max() ?? 0
    }

    /// Result of appending a chunk of generated text.
    enum Outcome: Equatable {
        /// Normal emission — the caller should forward `text` to the stream.
        /// `text` may be empty if nothing can be safely emitted yet.
        case emit(String)
        /// A stop sequence was found. Emit `text` (may be empty) and terminate.
        case terminate(String)
    }

    /// Append a new chunk and return what should be emitted (if anything).
    mutating func append(_ chunk: String) -> Outcome {
        pending += chunk

        // Check for any complete stop sequence in the buffer
        for stop in stopSequences {
            if let stopRange = pending.range(of: stop) {
                let clean = String(pending[pending.startIndex..<stopRange.lowerBound])
                pending = ""
                return .terminate(clean)
            }
        }

        // Hold back the tail of the buffer that could be the start of a stop sequence
        if pending.count > holdBack {
            let emitEnd = pending.index(pending.endIndex, offsetBy: -holdBack)
            let emit = String(pending[pending.startIndex..<emitEnd])
            pending = String(pending[emitEnd...])
            return .emit(emit)
        }

        return .emit("")
    }

    /// Flush any remaining text when generation ends naturally (no stop sequence hit).
    /// Strips any trailing partial stop markers defensively — only at the suffix,
    /// never mid-string. A model that legitimately emits a stop token in the
    /// middle of generation should keep that text intact.
    mutating func flush() -> String {
        var result = pending
        // Strip a single trailing stop sequence if present. Loop in case the
        // pending tail is literally just multiple stop sequences concatenated.
        outer: while !result.isEmpty {
            for stop in stopSequences where result.hasSuffix(stop) {
                result.removeLast(stop.count)
                continue outer
            }
            break
        }
        pending = ""
        return result
    }
}
