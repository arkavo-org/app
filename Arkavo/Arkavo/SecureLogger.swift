import Foundation
import OSLog

/// Secure logging utility that redacts sensitive information in production builds
/// and provides detailed logging in debug builds only
enum SecureLogger {
    private static let logger = Logger(subsystem: "com.arkavo.Arkavo", category: "Security")

    /// Log levels matching OSLog
    enum Level {
        case debug
        case info
        case notice
        case error
        case fault
    }

    // MARK: - Public Logging Methods

    /// Log a message at the specified level
    /// - Parameters:
    ///   - level: The log level
    ///   - message: The message to log
    ///   - file: Source file (automatically captured)
    ///   - function: Function name (automatically captured)
    ///   - line: Line number (automatically captured)
    static func log(
        _ level: Level = .info,
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        let fileName = (file as NSString).lastPathComponent
        let context = "[\(fileName):\(line) \(function)]"

        switch level {
        case .debug:
            #if DEBUG
            logger.debug("\(context) \(message)")
            #endif
        case .info:
            logger.info("\(context) \(message)")
        case .notice:
            logger.notice("\(context) \(message)")
        case .error:
            logger.error("\(context) \(message)")
        case .fault:
            logger.fault("\(context) \(message)")
        }
    }

    // MARK: - Sensitive Data Redaction

    /// Logs data with automatic redaction in production
    /// - Parameters:
    ///   - level: The log level
    ///   - label: A label describing the data
    ///   - data: The sensitive data to log
    static func logSensitiveData(
        _ level: Level = .debug,
        label: String,
        data: Data,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // In debug builds, show first/last few bytes
        let preview = data.prefix(4).map { String(format: "%02x", $0) }.joined()
        let suffix = data.suffix(4).map { String(format: "%02x", $0) }.joined()
        log(level, "\(label): \(data.count) bytes [\(preview)...\(suffix)]", file: file, function: function, line: line)
        #else
        // In production, only show length
        log(level, "\(label): \(data.count) bytes [REDACTED]", file: file, function: function, line: line)
        #endif
    }

    /// Logs a base64-encoded string with automatic redaction
    static func logBase64(
        _ level: Level = .debug,
        label: String,
        base64String: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // In debug builds, show first/last characters
        let preview = base64String.prefix(8)
        let suffix = base64String.suffix(8)
        log(level, "\(label): \(base64String.count) chars [\(preview)...\(suffix)]", file: file, function: function, line: line)
        #else
        // In production, only show length
        log(level, "\(label): \(base64String.count) chars [REDACTED]", file: file, function: function, line: line)
        #endif
    }

    /// Logs a token/credential with automatic redaction
    static func logToken(
        _ level: Level = .debug,
        label: String,
        token: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // In debug builds, show first few characters only
        let preview = token.prefix(10)
        log(level, "\(label): \(preview)... (\(token.count) chars)", file: file, function: function, line: line)
        #else
        // In production, completely redact
        log(level, "\(label): [REDACTED] (\(token.count) chars)", file: file, function: function, line: line)
        #endif
    }

    /// Logs cryptographic keys with automatic redaction
    static func logCryptoKey(
        _ level: Level = .debug,
        label: String,
        keyData: Data,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        // In debug, show key size only (never the actual key)
        log(level, "\(label): Key size \(keyData.count * 8) bits", file: file, function: function, line: line)
        #else
        // In production, completely redact
        log(level, "\(label): [CRYPTO_KEY_REDACTED]", file: file, function: function, line: line)
        #endif
    }

    // MARK: - Specialized Logging

    /// Logs authentication events
    static func logAuth(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, "🔐 AUTH: \(message)", file: file, function: function, line: line)
    }

    /// Logs security-related events
    static func logSecurity(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.notice, "🛡️ SECURITY: \(message)", file: file, function: function, line: line)
    }

    /// Logs security violations or potential attacks
    static func logSecurityViolation(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.fault, "⚠️ SECURITY_VIOLATION: \(message)", file: file, function: function, line: line)
    }

    /// Logs key exchange events
    static func logKeyExchange(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        log(.debug, "🔑 KEY_EXCHANGE: \(message)", file: file, function: function, line: line)
        #else
        log(.info, "🔑 KEY_EXCHANGE: \(message)", file: file, function: function, line: line)
        #endif
    }
}

// MARK: - Data Extension for Secure Logging

extension Data {
    /// Returns a secure string representation suitable for logging
    var secureDescription: String {
        #if DEBUG
        let preview = prefix(4).map { String(format: "%02x", $0) }.joined()
        let suffix = suffix(4).map { String(format: "%02x", $0) }.joined()
        return "\(count) bytes [\(preview)...\(suffix)]"
        #else
        return "\(count) bytes [REDACTED]"
        #endif
    }
}
