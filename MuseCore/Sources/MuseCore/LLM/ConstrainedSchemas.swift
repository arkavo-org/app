import Foundation

// MARK: - JSON Schema Definitions for Constrained Decoding
//
// These schemas mirror the @Generable structs in ToolDefinitions.swift
// Used with mlx-swift-structured for grammar-based constrained generation
//
// NOTE: Requires mlx-swift-structured package (>=0.0.3)
// Add via Xcode: https://github.com/petrukha-ivan/mlx-swift-structured
// Pin to commit: baee5511aefa4ce25022cc2e68cc7ae901f193a0

#if canImport(MLXStructured)
import MLXStructured

/// JSON Schemas for constrained decoding with Gemma-3
public enum ConstrainedSchemas {

    // MARK: - Main Response Schema

    /// Schema for AssistantResponse matching @Generable struct
    public static var assistantResponseSchema: JSONSchema {
        .object(
            description: "Assistant response with optional tool call",
            properties: [
                "message": .string(description: "Friendly spoken response"),
                "toolCall": toolCallSchema
            ],
            required: ["message"]
        )
    }

    // MARK: - Tool Call Schema (Union Type)

    /// Combined tool call schema with type discriminator
    private static var toolCallSchema: JSONSchema {
        .oneOf([
            .null,
            playAnimationSchema,
            setExpressionSchema,
            getTimeSchema,
            getDateSchema
        ])
    }

    // MARK: - Individual Tool Schemas

    /// Schema for play_animation tool
    public static var playAnimationSchema: JSONSchema {
        .object(
            description: "Play animation tool call",
            properties: [
                "type": .const("playAnimation"),
                "animation": .string(
                    description: "Animation name",
                    enum: AvailableAnimations.all
                ),
                "loop": .boolean(description: "Loop continuously")
            ],
            required: ["type", "animation"]
        )
    }

    /// Schema for set_expression tool
    public static var setExpressionSchema: JSONSchema {
        .object(
            description: "Set expression tool call",
            properties: [
                "type": .const("setExpression"),
                "expression": .string(
                    description: "Expression preset",
                    enum: AvailableExpressions.all
                ),
                "intensity": .number(
                    description: "Intensity 0.0-1.0",
                    minimum: 0.0,
                    maximum: 1.0
                )
            ],
            required: ["type", "expression"]
        )
    }

    /// Schema for get_time tool
    public static var getTimeSchema: JSONSchema {
        .object(
            description: "Get current time",
            properties: [
                "type": .const("getTime"),
                "timezone": .string(description: "IANA timezone identifier")
            ],
            required: ["type"]
        )
    }

    /// Schema for get_date tool
    public static var getDateSchema: JSONSchema {
        .object(
            description: "Get current date",
            properties: [
                "type": .const("getDate"),
                "format": .string(
                    description: "Date format",
                    enum: ["short", "long"]
                )
            ],
            required: ["type"]
        )
    }
}

// MARK: - Grammar Factory

/// Factory for creating and caching grammar instances
public enum GrammarFactory {

    /// Cached grammar instance (compiled once, expensive operation)
    private static var cachedGrammar: Grammar?

    /// Create or return cached grammar for AssistantResponse
    /// - Returns: Compiled grammar for constrained generation
    /// - Throws: Grammar compilation error
    public static func assistantResponseGrammar() throws -> Grammar {
        if let cached = cachedGrammar {
            return cached
        }
        let grammar = try Grammar.schema(ConstrainedSchemas.assistantResponseSchema)
        cachedGrammar = grammar
        return grammar
    }

    /// Reset the grammar cache (useful for testing)
    public static func resetCache() {
        cachedGrammar = nil
    }
}

#else

// MARK: - Stub Implementation (when MLXStructured not available)

/// Placeholder schemas when mlx-swift-structured is not available
public enum ConstrainedSchemas {
    public static var assistantResponseSchema: String {
        """
        {
          "type": "object",
          "properties": {
            "message": { "type": "string" },
            "toolCall": {
              "oneOf": [
                { "type": "null" },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "playAnimation" },
                    "animation": { "enum": ["wave", "nod", "jump", "hop", "thinking", "bow", "surprised", "laugh", "shrug", "clap", "sad", "angry", "pout", "excited", "scared", "flex", "heart", "point", "bashful", "victory", "exhausted", "dance", "yawn", "curious", "nervous", "proud", "relieved", "disgust", "goodbye", "love", "confused", "grateful", "danceGangnam", "danceDab", "idle"] },
                    "loop": { "type": "boolean" }
                  },
                  "required": ["type", "animation"]
                },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "setExpression" },
                    "expression": { "enum": ["happy", "sad", "angry", "surprised", "relaxed", "neutral"] },
                    "intensity": { "type": "number", "minimum": 0, "maximum": 1 }
                  },
                  "required": ["type", "expression"]
                },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "getTime" },
                    "timezone": { "type": "string" }
                  },
                  "required": ["type"]
                },
                {
                  "type": "object",
                  "properties": {
                    "type": { "const": "getDate" },
                    "format": { "enum": ["short", "long"] }
                  },
                  "required": ["type"]
                }
              ]
            }
          },
          "required": ["message"]
        }
        """
    }
}

/// Placeholder factory when mlx-swift-structured is not available
public enum GrammarFactory {
    public static func assistantResponseGrammar() throws -> Any {
        throw ConstrainedDecodingError.libraryNotAvailable
    }

    public static func resetCache() {}
}

public enum ConstrainedDecodingError: LocalizedError {
    case libraryNotAvailable

    public var errorDescription: String? {
        switch self {
        case .libraryNotAvailable:
            return "mlx-swift-structured library is not available. Add package: https://github.com/petrukha-ivan/mlx-swift-structured"
        }
    }
}

#endif
