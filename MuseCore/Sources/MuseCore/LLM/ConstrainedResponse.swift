import Foundation

// MARK: - Constrained Response

/// Response from constrained LLM generation
nonisolated public struct ConstrainedResponse: Decodable, Sendable, Equatable {
    public let message: String
    public let toolCall: ConstrainedToolCall?

    nonisolated public init(message: String, toolCall: ConstrainedToolCall? = nil) {
        self.message = message
        self.toolCall = toolCall
    }
}

/// Tool call decoded from constrained JSON output
nonisolated public enum ConstrainedToolCall: Sendable, Equatable {
    case playAnimation(animation: String, loop: Bool)
    case setExpression(expression: String, intensity: Double)
    case getTime(timezone: String?)
    case getDate(format: String?)
}

extension ConstrainedToolCall: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, animation, loop, expression, intensity, timezone, format
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "playAnimation":
            let animation = try container.decode(String.self, forKey: .animation)
            let loop = try container.decodeIfPresent(Bool.self, forKey: .loop) ?? false
            self = .playAnimation(animation: animation, loop: loop)

        case "setExpression":
            let expression = try container.decode(String.self, forKey: .expression)
            let intensity = try container.decodeIfPresent(Double.self, forKey: .intensity) ?? 0.8
            self = .setExpression(expression: expression, intensity: intensity)

        case "getTime":
            let timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
            self = .getTime(timezone: timezone)

        case "getDate":
            let format = try container.decodeIfPresent(String.self, forKey: .format)
            self = .getDate(format: format)

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool type: \(type)"
            )
        }
    }
}

// MARK: - Bridge to ParsedToolCall

extension ConstrainedToolCall {
    /// Convert to ParsedToolCall for unified tool execution
    public func toParsedToolCall() -> ParsedToolCall {
        switch self {
        case .playAnimation(let animation, let loop):
            return ParsedToolCall(
                name: "play_animation",
                arguments: ["animation": .string(animation), "loop": .bool(loop)],
                rawText: ""
            )
        case .setExpression(let expression, let intensity):
            return ParsedToolCall(
                name: "set_expression",
                arguments: ["expression": .string(expression), "intensity": .float(intensity)],
                rawText: ""
            )
        case .getTime(let timezone):
            return ParsedToolCall(
                name: "get_time",
                arguments: timezone.map { ["timezone": .string($0)] } ?? [:],
                rawText: ""
            )
        case .getDate(let format):
            return ParsedToolCall(
                name: "get_date",
                arguments: format.map { ["format": .string($0)] } ?? [:],
                rawText: ""
            )
        }
    }
}
