import Foundation

// MARK: - Fence Parser for Small Models (Gemma-3 270M)

/// Parses fence-based tool calls from LLM output
/// Format: ```tool_name\nkey: value\nkey2: value2\n```
public struct FenceParser: Sendable {

    // MARK: - Regex Patterns

    /// Primary pattern: ```tool_name\nkey: value\n```
    /// Tool names are lowercase with underscores
    private nonisolated static let primaryPattern = #"```([a-z][a-z0-9_]*)\s*\n([\s\S]*?)```"#

    /// Fallback pattern: ```\ntool_name\nkey: value\n```
    /// Handles when model puts tool name on separate line after opening fence
    private nonisolated static let fallbackPattern = #"```\s*\n([a-z][a-z0-9_]*)\s*\n([\s\S]*?)```"#

    /// Pattern 3: Space after opening fence (```  tool_name)
    private nonisolated static let spaceAfterOpeningPattern = #"```\s+([a-z][a-z0-9_]*)\s*\n([\s\S]*?)```"#

    /// Pattern 4: Missing closing fence (truncation) - matches to end of string
    private nonisolated static let unclosedFencePattern = #"```([a-z][a-z0-9_]*)\s*\n([\s\S]*?)(?:```|$)"#

    /// Pattern 5: Case-insensitive tool names (handles PLAY_ANIMATION, Play_Animation, etc.)
    private nonisolated static let caseInsensitivePattern = #"```([A-Za-z][A-Za-z0-9_]*)\s*\n([\s\S]*?)```"#

    /// Known tool names for fuzzy matching
    private nonisolated static let knownTools = ["play_animation", "set_expression", "get_time", "get_date"]

    /// Code block languages to skip (not tool calls)
    private nonisolated static let skipLanguages = Set([
        "swift", "python", "javascript", "typescript", "json", "xml",
        "html", "css", "bash", "shell", "sh", "rust", "go", "java",
        "kotlin", "c", "cpp", "objc", "ruby", "php", "sql", "yaml",
        "markdown", "md", "text", "plaintext"
    ])

    // MARK: - Public API

    /// Parse all tool calls from text
    /// - Parameter text: The LLM response text
    /// - Returns: Array of parsed tool calls
    public static nonisolated func parse(_ text: String) -> [ParsedToolCall] {
        var calls: [ParsedToolCall] = []

        // Try patterns in order of strictness
        let patterns = [
            primaryPattern,
            fallbackPattern,
            spaceAfterOpeningPattern,
            caseInsensitivePattern,
            unclosedFencePattern
        ]

        for pattern in patterns {
            calls = extractWithPattern(pattern, from: text)
            if !calls.isEmpty {
                break
            }
        }

        return calls
    }

    // MARK: - Fuzzy Tool Name Matching

    /// Fuzzy match a tool name against known tools using Levenshtein distance
    /// - Parameters:
    ///   - name: The tool name from LLM output
    ///   - threshold: Maximum edit distance to consider a match (default 3)
    /// - Returns: The matched tool name, or nil if no close match found
    public static nonisolated func fuzzyMatchTool(_ name: String, threshold: Int = 3) -> String? {
        let lowered = name.lowercased()

        // Exact match
        if knownTools.contains(lowered) {
            return lowered
        }

        // Find closest match within threshold
        var bestMatch: String?
        var bestDistance = Int.max

        for tool in knownTools {
            let distance = levenshteinDistance(lowered, tool)
            if distance < bestDistance && distance <= threshold {
                bestDistance = distance
                bestMatch = tool
            }
        }

        return bestMatch
    }

    /// Calculate Levenshtein edit distance between two strings
    private static nonisolated func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,      // deletion
                    dp[i][j - 1] + 1,      // insertion
                    dp[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return dp[m][n]
    }

    /// Extract text remaining after removing tool calls (for TTS)
    /// - Parameter text: The original LLM response
    /// - Returns: Text with tool call blocks removed
    public static nonisolated func extractRemainingText(_ text: String) -> String {
        var result = text

        // Remove primary pattern matches
        if let regex = try? NSRegularExpression(pattern: primaryPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Remove fallback pattern matches
        if let regex = try? NSRegularExpression(pattern: fallbackPattern) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Clean up extra whitespace
        return result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    private static nonisolated func extractWithPattern(_ pattern: String, from text: String) -> [ParsedToolCall] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: pattern == caseInsensitivePattern ? .caseInsensitive : []) else {
            return []
        }

        var results: [ParsedToolCall] = []
        let nsRange = NSRange(text.startIndex..., in: text)

        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges >= 3,
                  let nameRange = Range(match.range(at: 1), in: text),
                  let bodyRange = Range(match.range(at: 2), in: text),
                  let fullRange = Range(match.range, in: text) else {
                return
            }

            var toolName = String(text[nameRange])

            // Skip if it's a known code block language
            if skipLanguages.contains(toolName.lowercased()) {
                return
            }

            // Normalize tool name to lowercase
            toolName = toolName.lowercased()

            // Try fuzzy matching if not an exact known tool
            if !knownTools.contains(toolName) {
                if let matched = fuzzyMatchTool(toolName) {
                    toolName = matched
                }
            }

            let body = String(text[bodyRange])
            let arguments = parseKeyValuePairs(body)
            let rawText = String(text[fullRange])

            // Calculate confidence score
            let confidence = ParsedToolCall.calculateConfidence(
                toolName: toolName,
                arguments: arguments
            )

            results.append(ParsedToolCall(
                name: toolName,
                arguments: arguments,
                rawText: rawText,
                confidence: confidence
            ))
        }

        return results
    }

    /// Parse key: value pairs from fence body
    public static nonisolated func parseKeyValuePairs(_ body: String) -> [String: ToolValue] {
        var arguments: [String: ToolValue] = [:]

        for line in body.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Find first colon to split key: value
            if let colonIndex = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStr = String(trimmed[trimmed.index(after: colonIndex)...])
                    .trimmingCharacters(in: .whitespaces)

                // Skip empty keys
                guard !key.isEmpty else { continue }

                arguments[key] = inferType(valueStr)
            }
        }

        return arguments
    }

    /// Infer the type of a string value
    public static nonisolated func inferType(_ value: String) -> ToolValue {
        let lowered = value.lowercased()

        // Empty string
        if value.isEmpty {
            return .string("")
        }

        // Boolean
        if lowered == "true" || lowered == "yes" {
            return .bool(true)
        }
        if lowered == "false" || lowered == "no" {
            return .bool(false)
        }

        // Null
        if lowered == "null" || lowered == "none" || lowered == "nil" {
            return .null
        }

        // Integer
        if let intVal = Int(value) {
            return .int(intVal)
        }

        // Float/Double
        if let doubleVal = Double(value) {
            return .float(doubleVal)
        }

        // JSON array
        if value.hasPrefix("[") && value.hasSuffix("]") {
            if let data = value.data(using: .utf8),
               let array = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return .array(array.map { convertJSONValue($0) })
            }
        }

        // Default: string
        return .string(value)
    }

    private static nonisolated func convertJSONValue(_ value: Any) -> ToolValue {
        switch value {
        case let str as String:
            return .string(str)
        case let num as Int:
            return .int(num)
        case let num as Double:
            return .float(num)
        case let bool as Bool:
            return .bool(bool)
        case let arr as [Any]:
            return .array(arr.map { convertJSONValue($0) })
        default:
            return .string(String(describing: value))
        }
    }
}

// MARK: - Parsed Tool Call

/// A parsed tool call from fence format
public struct ParsedToolCall: Equatable, Sendable {
    public nonisolated let name: String
    public nonisolated let arguments: [String: ToolValue]
    public nonisolated let rawText: String
    /// Confidence score from 0.0 (low) to 1.0 (high)
    public nonisolated let confidence: Float

    public nonisolated init(name: String, arguments: [String: ToolValue], rawText: String, confidence: Float = 1.0) {
        self.name = name
        self.arguments = arguments
        self.rawText = rawText
        self.confidence = confidence
    }

    /// Calculate confidence score based on tool definition match
    public static nonisolated func calculateConfidence(
        toolName: String,
        arguments: [String: ToolValue],
        knownTools: [FenceToolDefinition] = FenceToolDefinition.all
    ) -> Float {
        var score: Float = 0.0

        // Check if tool name is exact match (0.5 points)
        guard let tool = knownTools.first(where: { $0.name == toolName.lowercased() }) else {
            // Fuzzy match - lower confidence
            if FenceParser.fuzzyMatchTool(toolName) != nil {
                score += 0.3
            }
            return score
        }
        score += 0.5

        // Check required parameters present (0.3 points)
        let requiredParams = tool.parameters.filter { $0.required }
        if !requiredParams.isEmpty {
            let presentRequired = requiredParams.filter { arguments[$0.name] != nil }
            score += 0.3 * Float(presentRequired.count) / Float(requiredParams.count)
        } else {
            score += 0.3 // No required params = full score
        }

        // Check for unexpected/invalid parameters (0.2 points)
        let knownParamNames = Set(tool.parameters.map { $0.name })
        let providedParamNames = Set(arguments.keys)
        let unknownParams = providedParamNames.subtracting(knownParamNames)
        if unknownParams.isEmpty {
            score += 0.2
        } else {
            // Deduct based on unknown params ratio
            let unknownRatio = Float(unknownParams.count) / Float(max(providedParamNames.count, 1))
            score += 0.2 * (1.0 - unknownRatio)
        }

        return min(score, 1.0)
    }

    /// Get a string argument
    public nonisolated func getString(_ key: String) -> String? {
        if case .string(let value) = arguments[key] {
            return value
        }
        return nil
    }

    /// Get an int argument
    public nonisolated func getInt(_ key: String) -> Int? {
        if case .int(let value) = arguments[key] {
            return value
        }
        return nil
    }

    /// Get a float argument
    public nonisolated func getFloat(_ key: String) -> Double? {
        if case .float(let value) = arguments[key] {
            return value
        }
        // Also accept int as float
        if case .int(let value) = arguments[key] {
            return Double(value)
        }
        return nil
    }

    /// Get a bool argument
    public nonisolated func getBool(_ key: String) -> Bool? {
        if case .bool(let value) = arguments[key] {
            return value
        }
        return nil
    }
}

// MARK: - Tool Value

/// Type-safe tool argument value
public enum ToolValue: Sendable {
    case string(String)
    case int(Int)
    case float(Double)
    case bool(Bool)
    case array([ToolValue])
    case null
}

extension ToolValue: Equatable {
    public static nonisolated func == (lhs: ToolValue, rhs: ToolValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)):
            return a == b
        case (.int(let a), .int(let b)):
            return a == b
        case (.float(let a), .float(let b)):
            return a == b
        case (.bool(let a), .bool(let b)):
            return a == b
        case (.array(let a), .array(let b)):
            return a == b
        case (.null, .null):
            return true
        default:
            return false
        }
    }
}

// MARK: - Fence Prompt Generator

/// Generates prompts with tool documentation in fence format for small models
public struct FencePromptGenerator: Sendable {

    /// Generate a basic prompt section describing available tools
    public static nonisolated func generate(tools: [FenceToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        var prompt = "\n\nYou have tools. Call them using code fences.\n\n"
        prompt += "Tools:\n"

        for tool in tools {
            prompt += "- \(tool.name): \(tool.description)\n"
        }

        prompt += "\nFormat:\n```<tool>\n<param>: <value>\n```\n\n"

        // Add examples
        prompt += "Examples:\n"
        for tool in tools.prefix(2) {
            prompt += "```\(tool.name)\n"
            for param in tool.parameters.filter({ $0.required }) {
                prompt += "\(param.name): \(param.example)\n"
            }
            prompt += "```\n"
        }

        prompt += "\nRespond with ONLY the code fence when using a tool.\n"

        return prompt
    }

    /// Generate an enhanced prompt optimized for small models (270M-1B)
    /// Includes explicit examples, when NOT to use tools, and trigger keywords
    public static nonisolated func generateEnhanced(tools: [FenceToolDefinition]) -> String {
        guard !tools.isEmpty else { return "" }

        var prompt = """

        # TOOLS
        You can use these tools when the user asks. Always include your spoken response too.

        ## Available Tools

        """

        for tool in tools {
            prompt += "### \(tool.name)\n"
            prompt += "\(tool.description)\n"
            prompt += "Parameters:\n"
            for param in tool.parameters {
                let req = param.required ? "(required)" : "(optional)"
                prompt += "  - \(param.name): \(param.type) \(req) - \(param.description)\n"
            }
            prompt += "\n"
        }

        prompt += """
        ## How to Call Tools

        When the user asks for animation, expression, time, or date, use this format:

        [Your spoken response here]

        ```tool_name
        parameter: value
        ```

        ## Examples

        User: "Wave at me!"
        Response: Sure, I'll wave at you!
        ```play_animation
        animation: happy_gesture
        ```

        User: "What time is it?"
        Response: Let me check the time for you.
        ```get_time
        ```

        User: "Look sad"
        Response: Okay, here's my sad face.
        ```set_expression
        expression: sad
        intensity: 0.8
        ```

        ## When NOT to Use Tools

        Don't use tools for regular conversation:
        - "How are you?" → Just respond normally, no tool
        - "What's your favorite color?" → Just respond normally, no tool
        - "Tell me about yourself" → Just respond normally, no tool
        - "What's the weather?" → Just respond normally (no weather tool exists)

        Only use tools when the user EXPLICITLY asks for:
        - Animations: wave, dance, gesture, bounce, move
        - Expressions: look happy/sad/angry, show face, expression
        - Time: what time is it, current time
        - Date: what's today's date, what day is it

        """

        return prompt
    }

    /// Detect if user message likely needs a tool based on keywords
    /// - Parameter message: The user's message
    /// - Returns: Suggested tool name, or nil if no tool needed
    public static nonisolated func suggestTool(for message: String) -> String? {
        let lowered = message.lowercased()

        // Animation triggers
        let animationTriggers = ["wave", "dance", "gesture", "move", "animate", "bounce", "sway", "excited"]
        if animationTriggers.contains(where: { lowered.contains($0) }) {
            return "play_animation"
        }

        // Expression triggers
        let expressionTriggers = ["look ", "face", "expression", "show me", "make a face"]
        let emotionWords = ["happy", "sad", "angry", "surprised", "relaxed", "neutral"]
        if expressionTriggers.contains(where: { lowered.contains($0) }) ||
           emotionWords.contains(where: { lowered.contains("look \($0)") || lowered.contains("be \($0)") }) {
            return "set_expression"
        }

        // Time triggers
        let timeTriggers = ["what time", "current time", "tell me the time", "clock"]
        if timeTriggers.contains(where: { lowered.contains($0) }) {
            return "get_time"
        }

        // Date triggers
        let dateTriggers = ["what's today", "today's date", "what day", "what date", "current date"]
        if dateTriggers.contains(where: { lowered.contains($0) }) {
            return "get_date"
        }

        return nil
    }
}

/// Definition of a tool for fence format prompts
public struct FenceToolDefinition: Sendable {
    public nonisolated let name: String
    public nonisolated let description: String
    public nonisolated let parameters: [FenceToolParameter]

    public nonisolated init(name: String, description: String, parameters: [FenceToolParameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

/// Parameter definition for fence format
public struct FenceToolParameter: Sendable {
    public nonisolated let name: String
    public nonisolated let type: String
    public nonisolated let description: String
    public nonisolated let required: Bool
    public nonisolated let example: String

    public nonisolated init(name: String, type: String, description: String, required: Bool, example: String) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.example = example
    }
}

// MARK: - Built-in Tool Definitions for Fence Format

extension FenceToolDefinition {
    public nonisolated static let playAnimation = FenceToolDefinition(
        name: "play_animation",
        description: "Play an animation on the avatar",
        parameters: [
            FenceToolParameter(name: "animation", type: "string", description: "Animation name", required: true, example: "happy_gesture"),
            FenceToolParameter(name: "loop", type: "bool", description: "Loop animation", required: false, example: "false")
        ]
    )

    public nonisolated static let setExpression = FenceToolDefinition(
        name: "set_expression",
        description: "Set the avatar's facial expression",
        parameters: [
            FenceToolParameter(name: "expression", type: "string", description: "Expression preset", required: true, example: "happy"),
            FenceToolParameter(name: "intensity", type: "float", description: "Intensity 0.0-1.0", required: false, example: "0.8")
        ]
    )

    public nonisolated static let getTime = FenceToolDefinition(
        name: "get_time",
        description: "Get the current time",
        parameters: [
            FenceToolParameter(name: "timezone", type: "string", description: "Timezone identifier", required: false, example: "America/New_York")
        ]
    )

    public nonisolated static let getDate = FenceToolDefinition(
        name: "get_date",
        description: "Get the current date",
        parameters: [
            FenceToolParameter(name: "format", type: "string", description: "short or long", required: false, example: "long")
        ]
    )

    public nonisolated static let all: [FenceToolDefinition] = [
        .playAnimation,
        .setExpression,
        .getTime,
        .getDate
    ]
}
