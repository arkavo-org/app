import os

private let logger = Logger(subsystem: "com.arkavo.ArkavoCreator", category: "app")

/// Debug-only logging. Compiles to a no-op in release builds.
@inline(__always)
func debugLog(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
        let message = items.map { "\($0)" }.joined(separator: separator)
        logger.debug("\(message, privacy: .public)")
    #endif
}
