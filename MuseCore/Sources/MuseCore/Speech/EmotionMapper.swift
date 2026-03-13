import Foundation
import VRMMetalKit

/// Maps sentiment scores to VRM facial expressions
struct EmotionMapper {

    // MARK: - Emoji Sentiment Boosts

    /// Emoji sentiment modifiers for common emotional emojis
    static let emojiSentimentBoosts: [Character: Double] = [
        // Positive
        "😊": 0.5, "😃": 0.6, "😂": 0.8, "🥰": 0.6, "😍": 0.7,
        "🎉": 0.6, "👍": 0.4, "❤️": 0.5, "💕": 0.5, "✨": 0.3,
        // Negative
        "😢": -0.5, "😭": -0.7, "😠": -0.7, "😡": -0.8, "💔": -0.5,
        "😤": -0.6, "😞": -0.4, "😔": -0.4,
        // Neutral/special
        "😮": 0.0, "🤔": 0.0, "😐": 0.0, "🙄": -0.2
    ]

    // MARK: - Filler Words

    /// Common filler words that indicate hesitation/thinking
    static let fillerWords: Set<String> = [
        "um", "uh", "uhh", "umm", "like", "you know", "er", "hmm", "erm",
        "well", "so", "basically", "actually", "literally"
    ]

    // MARK: - Laughter Patterns

    /// Patterns that indicate laughter in transcription
    static let laughterPatterns: [String] = [
        "haha", "ha ha", "hehe", "he he", "lol", "lmao", "rofl",
        "[laughter]", "(laughter)", "😂", "🤣", "hahaha", "lolol"
    ]

    // MARK: - Gratitude Keywords

    /// Keywords indicating gratitude
    static let gratitudeKeywords: [String] = [
        "thank you", "thanks", "appreciate", "grateful", "gratitude",
        "thank u", "thx", "ty", "cheers"
    ]

    // MARK: - Confusion Keywords

    /// Keywords indicating confusion
    static let confusionKeywords: [String] = [
        "huh", "what?", "i don't understand", "don't get it", "confused",
        "makes no sense", "i'm lost", "what do you mean", "pardon"
    ]

    // MARK: - Flirty Keywords

    /// Keywords indicating flirty/playful context (triggers wink)
    static let flirtyKeywords: [String] = [
        "wink", "flirt", "cute", "handsome", "beautiful", "gorgeous",
        "pretty", "attractive", "charming", "lovely", "sweetie", "honey",
        "darling", "babe", "cutie", "hottie", "sexy", "crush"
    ]

    // MARK: - Sentiment Smoothing State

    /// Lock protecting mutable static state (`lastSentiment`, `sentimentBuffer`)
    private static let smoothingLock = NSLock()
    nonisolated(unsafe) private static var lastSentiment: Double = 0
    nonisolated(unsafe) private static var sentimentBuffer: [Double] = []
    private static let bufferSize = 3

    /// Smooth raw sentiment to prevent jarring transitions
    static func smoothedSentiment(_ raw: Double) -> Double {
        smoothingLock.lock()
        defer { smoothingLock.unlock() }
        let alpha = 0.3  // Smoothing factor
        let smoothed = lastSentiment * (1 - alpha) + raw * alpha
        lastSentiment = smoothed
        return smoothed
    }

    /// Check if sentiment is stable (not rapidly changing)
    static func stableSentiment(_ newValue: Double) -> Double? {
        smoothingLock.lock()
        defer { smoothingLock.unlock() }
        sentimentBuffer.append(newValue)
        if sentimentBuffer.count > bufferSize {
            sentimentBuffer.removeFirst()
        }
        // Only return if sentiment direction is stable
        let allPositive = sentimentBuffer.allSatisfy { $0 > 0.1 }
        let allNegative = sentimentBuffer.allSatisfy { $0 < -0.1 }
        if allPositive || allNegative || sentimentBuffer.count < bufferSize {
            return sentimentBuffer.last
        }
        return 0.0  // Mixed/unstable → neutral
    }

    /// Reset smoothing state (call when conversation resets)
    static func resetSmoothingState() {
        smoothingLock.lock()
        defer { smoothingLock.unlock() }
        lastSentiment = 0
        sentimentBuffer.removeAll()
    }

    // MARK: - Emoji Detection

    /// Extract emoji sentiment boost from text
    static func emojiSentimentBoost(for text: String) -> Double {
        var boost: Double = 0
        for char in text {
            if let emojiBoost = emojiSentimentBoosts[char] {
                boost += emojiBoost
            }
        }
        // Clamp to reasonable range
        return max(-1.0, min(1.0, boost))
    }

    // MARK: - Punctuation Weighting

    /// Calculate intensity multiplier based on punctuation
    static func punctuationMultiplier(for text: String) -> Float {
        let exclamationCount = text.filter { $0 == "!" }.count
        // "Wow!" = 1.15x, "Wow!!" = 1.30x, "Wow!!!" = 1.45x (capped)
        return 1.0 + (Float(min(exclamationCount, 3)) * 0.15)
    }

    // MARK: - Intensity Calibration

    /// Intensity tier for expression calibration
    public enum IntensityTier: String {
        case low      // 0.2 - 0.4
        case medium   // 0.5 - 0.7
        case high     // 0.8 - 1.0

        /// Get a random intensity value within this tier's range
        public var randomValue: Float {
            switch self {
            case .low:
                return Float.random(in: AnimationTimingConfig.intensityLowMin...AnimationTimingConfig.intensityLowMax)
            case .medium:
                return Float.random(in: AnimationTimingConfig.intensityMediumMin...AnimationTimingConfig.intensityMediumMax)
            case .high:
                return Float.random(in: AnimationTimingConfig.intensityHighMin...AnimationTimingConfig.intensityHighMax)
            }
        }

        /// Get the center intensity value for this tier
        public var centerValue: Float {
            switch self {
            case .low:
                return (AnimationTimingConfig.intensityLowMin + AnimationTimingConfig.intensityLowMax) / 2
            case .medium:
                return (AnimationTimingConfig.intensityMediumMin + AnimationTimingConfig.intensityMediumMax) / 2
            case .high:
                return (AnimationTimingConfig.intensityHighMin + AnimationTimingConfig.intensityHighMax) / 2
            }
        }
    }

    /// Determine intensity tier based on input energy indicators
    /// - Parameters:
    ///   - text: The input text to analyze
    ///   - amplitude: Optional speech amplitude (0.0 - 1.0)
    /// - Returns: The appropriate intensity tier
    static func determineIntensityTier(for text: String, amplitude: Float? = nil) -> IntensityTier {
        var energyScore: Float = 0

        // Analyze punctuation energy
        let exclamationCount = text.filter { $0 == "!" }.count
        let questionCount = text.filter { $0 == "?" }.count
        let capsRatio = Float(text.filter { $0.isUppercase }.count) / max(Float(text.count), 1.0)

        // Exclamations add significant energy
        energyScore += Float(min(exclamationCount, 3)) * 0.25

        // Questions add mild energy
        energyScore += Float(min(questionCount, 2)) * 0.1

        // ALL CAPS text indicates shouting
        if capsRatio > 0.7 && text.count > 3 {
            energyScore += 0.3
        }

        // Emoji energy boost
        let emojiBoost = abs(emojiSentimentBoost(for: text))
        energyScore += Float(emojiBoost) * 0.2

        // Laughter indicates high energy
        if containsLaughter(text) {
            energyScore += 0.3
        }

        // Strong emotion keywords
        let highEnergyKeywords = ["amazing", "incredible", "fantastic", "terrible", "horrible", "love", "hate", "omg", "wow"]
        let hasHighEnergyWord = highEnergyKeywords.contains { text.lowercased().contains($0) }
        if hasHighEnergyWord {
            energyScore += 0.25
        }

        // Consider amplitude if provided
        if let amplitude = amplitude {
            // Loud speech adds energy
            if amplitude > 0.7 {
                energyScore += 0.3
            } else if amplitude > 0.4 {
                energyScore += 0.15
            }
        }

        // Determine tier based on energy score
        if energyScore >= 0.5 {
            return .high
        } else if energyScore >= 0.2 {
            return .medium
        } else {
            return .low
        }
    }

    /// Calibrate intensity value based on text energy
    /// - Parameters:
    ///   - baseIntensity: The base intensity from sentiment mapping
    ///   - text: The input text for energy analysis
    ///   - amplitude: Optional speech amplitude
    /// - Returns: Calibrated intensity value (0.0 - 1.0)
    static func calibrateIntensity(_ baseIntensity: Float, for text: String, amplitude: Float? = nil) -> Float {
        let tier = determineIntensityTier(for: text, amplitude: amplitude)
        let tierCenter = tier.centerValue

        // Blend base intensity toward tier center
        // This prevents very high expressions for calm text and vice versa
        let blendedIntensity = (baseIntensity * 0.6) + (tierCenter * 0.4)

        // Apply punctuation multiplier
        let multiplier = punctuationMultiplier(for: text)
        let finalIntensity = blendedIntensity * multiplier

        // Clamp to valid range
        return max(0.0, min(1.0, finalIntensity))
    }

    // MARK: - Pattern Detection

    /// Check if text contains laughter patterns
    static func containsLaughter(_ text: String) -> Bool {
        let lower = text.lowercased()
        return laughterPatterns.contains { lower.contains($0) }
    }

    /// Check if text is filler-heavy (>33% filler words)
    static func isFillerHeavy(_ text: String) -> Bool {
        let words = text.lowercased().split(separator: " ").map { String($0) }
        guard !words.isEmpty else { return false }
        let fillerCount = words.filter { fillerWords.contains($0) }.count
        return fillerCount > words.count / 3
    }

    /// Check if text contains gratitude keywords
    static func containsGratitude(_ text: String) -> Bool {
        let lower = text.lowercased()
        return gratitudeKeywords.contains { lower.contains($0) }
    }

    /// Check if text contains confusion keywords
    static func containsConfusion(_ text: String) -> Bool {
        let lower = text.lowercased()
        return confusionKeywords.contains { lower.contains($0) }
    }

    /// Check if text is a question without strong emotion
    static func isCuriousQuestion(_ text: String) -> Bool {
        return text.contains("?") && !text.contains("!")
    }

    /// Check if text contains flirty/playful content (should trigger wink)
    static func isFlirty(_ text: String) -> Bool {
        let lower = text.lowercased()
        return flirtyKeywords.contains(where: { lower.contains($0) })
    }

    /// Maps a sentiment score to a VRM expression preset and intensity
    /// - Parameters:
    ///   - sentiment: Sentiment score from -1.0 (very negative) to 1.0 (very positive)
    ///   - text: Optional context text for nuanced detection
    ///   - isThinking: Whether the system is currently in thinking state
    ///   - amplitude: Optional speech amplitude for intensity calibration
    /// - Returns: Tuple of (expression preset, intensity [0.0-1.0])
    static func mapSentimentToExpression(
        _ sentiment: Double,
        context text: String? = nil,
        isThinking: Bool = false,
        amplitude: Float? = nil
    ) -> (preset: VRMExpressionPreset, intensity: Float) {

        // Thinking state takes priority
        if isThinking {
            return (.relaxed, 0.4)
        }

        // Apply emoji sentiment boost
        var adjustedSentiment = sentiment
        if let text = text {
            let emojiBoost = emojiSentimentBoost(for: text)
            adjustedSentiment = max(-1.0, min(1.0, sentiment + emojiBoost))
        }

        // Smooth sentiment to prevent jarring transitions
        adjustedSentiment = smoothedSentiment(adjustedSentiment)

        // Calculate punctuation-based intensity multiplier
        let punctMultiplier = text != nil ? punctuationMultiplier(for: text!) : 1.0

        // Check for contextual clues first (exclamation, keywords)
        if let text = text?.lowercased() {
            // Filler-heavy text → attentive/thinking expression
            if isFillerHeavy(text) {
                return (.relaxed, 0.4)
            }

            // Laughter detection → high intensity happy
            if containsLaughter(text) {
                return (.happy, min(0.9 * punctMultiplier, 1.0))
            }

            // Gratitude detection → relaxed expression
            if containsGratitude(text) {
                return (.relaxed, min(0.6 * punctMultiplier, 1.0))
            }

            // Confusion detection → surprised at lower intensity
            if containsConfusion(text) {
                return (.surprised, 0.5)
            }

            // Curious question (? without !) → subtle head tilt via reaction
            // Expression stays neutral/relaxed
            if isCuriousQuestion(text) && !text.contains("what") && !text.contains("how") {
                return (.relaxed, 0.3)
            }

            // Angry: specific anger keywords OR very negative sentiment
            let hasAngryKeywords = text.contains("angry") || text.contains("mad") || text.contains("furious") ||
                text.contains("hate") || text.contains("annoyed") || text.contains("frustrated")
            if hasAngryKeywords || adjustedSentiment < -0.6 {
                let intensity = hasAngryKeywords ? 0.8 : Float(min(abs(adjustedSentiment) * 1.2, 1.0))
                return (.angry, min(intensity * punctMultiplier, 1.0))
            }

            // Surprised: keywords, question marks with certain words
            let hasSurprisedKeywords = text.contains("wow") || text.contains("omg") ||
               text.contains("whoa") || text.contains("really") || text.contains("seriously") ||
               text.contains("no way") || text.contains("unbelievable") || text.contains("incredible")
            let hasExclamation = text.contains("!")
            let hasQuestionSurprise = text.contains("?") && (text.contains("what") || text.contains("how"))
            if hasSurprisedKeywords || hasExclamation || hasQuestionSurprise {
                return (.surprised, min(0.8 * punctMultiplier, 1.0))
            }

            // Relaxed: calm/peaceful keywords
            if text.contains("relax") || text.contains("calm") || text.contains("peaceful") ||
               text.contains("chill") || text.contains("easy") || text.contains("comfortable") {
                return (.relaxed, 0.7)
            }
        }

        // Sentiment-based mapping with punctuation weighting
        if adjustedSentiment > 0.5 {
            // Strong positive → happy
            return (.happy, min(Float(adjustedSentiment) * punctMultiplier, 1.0))
        } else if adjustedSentiment > 0.2 {
            // Mild positive → relaxed
            return (.relaxed, min(Float(adjustedSentiment * 1.5) * punctMultiplier, 1.0))
        } else if adjustedSentiment < -0.5 {
            // Strong negative → sad
            return (.sad, min(Float(abs(adjustedSentiment)) * punctMultiplier, 1.0))
        } else if adjustedSentiment < -0.2 {
            // Mild negative → slight sad
            return (.sad, min(Float(abs(adjustedSentiment) * 1.5) * punctMultiplier, 1.0))
        } else {
            // Neutral range (-0.2 to 0.2)
            return (.neutral, 1.0)
        }
    }

    /// Smooth transition helper - blend between current and target expression
    /// - Parameters:
    ///   - from: Current expression
    ///   - to: Target expression
    ///   - progress: Transition progress [0.0-1.0]
    /// - Returns: Blended expression weights
    static func blendExpressions(
        from: (preset: VRMExpressionPreset, intensity: Float),
        to: (preset: VRMExpressionPreset, intensity: Float),
        progress: Float
    ) -> [(preset: VRMExpressionPreset, intensity: Float)] {

        let clampedProgress = max(0, min(1, progress))

        // If same preset, just interpolate intensity
        if from.preset == to.preset {
            let blendedIntensity = from.intensity * (1 - clampedProgress) + to.intensity * clampedProgress
            return [(preset: from.preset, intensity: blendedIntensity)]
        }

        // Different presets: cross-fade
        let fromWeight = from.intensity * (1 - clampedProgress)
        let toWeight = to.intensity * clampedProgress

        var result: [(preset: VRMExpressionPreset, intensity: Float)] = []
        if fromWeight > 0.01 {
            result.append((preset: from.preset, intensity: fromWeight))
        }
        if toWeight > 0.01 {
            result.append((preset: to.preset, intensity: toWeight))
        }

        return result
    }

    // MARK: - Emote Selection (12 Emotes)

    /// Maps sentiment score and context to an EmoteAnimationLayer.Emote
    /// - Parameters:
    ///   - sentiment: Sentiment score from -1.0 (very negative) to 1.0 (very positive)
    ///   - text: Optional context text for keyword-based selection
    ///   - isThinking: Whether the system is currently in thinking state
    /// - Returns: EmoteAnimationLayer.Emote that matches the sentiment/context
    static func mapSentimentToEmote(
        _ sentiment: Double,
        context text: String? = nil,
        isThinking: Bool = false
    ) -> EmoteAnimationLayer.Emote {

        // Thinking state triggers thinking pose
        if isThinking {
            return .thinking
        }

        // Check for contextual keywords first
        if let text = text?.lowercased() {
            // Filler-heavy text → thinking pose
            if isFillerHeavy(text) {
                return .thinking
            }

            // Goodbye detection → goodbye
            if text.contains("bye") || text.contains("goodbye") || text.contains("see you") ||
               text.contains("farewell") || text.contains("take care") || text.contains("later") {
                return .goodbye
            }

            // Greeting detection → wave
            if text.contains("hi") || text.contains("hello") || text.contains("hey") ||
               text.contains("greetings") || text.contains("good morning") ||
               text.contains("good afternoon") || text.contains("good evening") {
                return .wave
            }

            // Agreement detection → nod
            if text.contains("yes") || text.contains("okay") || text.contains("sure") ||
               text.contains("alright") || text.contains("agreed") || text.contains("exactly") {
                return .nod
            }

            // Strong excitement → jump
            if text.contains("amazing") || text.contains("incredible") || text.contains("fantastic") ||
               text.contains("wow") && sentiment > 0.5 {
                return .jump
            }

            // Playful positive → hop
            if (text.contains("fun") || text.contains("playful") || text.contains("cool")) &&
               sentiment > 0.3 {
                return .hop
            }

            // Gratitude detection → bow
            if containsGratitude(text) {
                return .bow
            }

            // Disgust detection → disgust
            if text.contains("gross") || text.contains("disgusting") || text.contains("eww") ||
               text.contains("yuck") || text.contains("nasty") {
                return .disgust
            }

            // Curiosity detection → curious
            if text.contains("curious") || text.contains("wonder") || text.contains("interesting") ||
               text.contains("tell me more") {
                return .curious
            }

            // Nervousness detection → nervous
            if text.contains("nervous") || text.contains("anxious") || text.contains("worried") ||
               text.contains("stressed") {
                return .nervous
            }

            // Pride detection → proud
            if text.contains("proud") || text.contains("accomplished") || text.contains("nailed it") ||
               text.contains("did it") {
                return .proud
            }

            // Relief detection → relieved
            if text.contains("phew") || text.contains("finally") || text.contains("relieved") ||
               text.contains("thank goodness") {
                return .relieved
            }

            // Surprise expressions → surprised
            if text.contains("what?") || text.contains("omg") || text.contains("whoa") ||
               text.contains("really?") || text.contains("no way") {
                return .surprised
            }

            // Laughter detection → laugh
            if containsLaughter(text) {
                return .laugh
            }

            // Uncertainty → shrug
            if text.contains("i don't know") || text.contains("not sure") || text.contains("maybe") ||
               text.contains("dunno") || text.contains("idk") || text.contains("who knows") {
                return .shrug
            }

            // Praise/congratulations → clap
            if text.contains("great job") || text.contains("congrats") || text.contains("well done") ||
               text.contains("congratulations") || text.contains("bravo") || text.contains("awesome work") {
                return .clap
            }

            // Confusion detection → confused
            if containsConfusion(text) {
                return .confused
            }
        }

        // Sentiment-based selection
        if sentiment > 0.6 {
            return .jump
        } else if sentiment > 0.3 {
            return .hop
        } else if sentiment < -0.4 {
            return .sad
        } else if sentiment < -0.2 {
            return .thinking  // Contemplative for mild negative
        } else {
            return .idle
        }
    }
}
