//
// Copyright 2025 Arkavo
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation

/// Centralized timing constants for avatar animation and interaction UX.
/// All values are tuned according to the Avatar Animation & Interaction UX Guide.
public enum AnimationTimingConfig {

    // MARK: - Speech & Listening Transitions

    /// Maximum time for avatar to transition to listening pose after speech starts.
    /// Requirement: < 200ms for responsive feel.
    public static let speechStartToListeningMs: Int = 200

    // MARK: - Processing Beat (Thinking Pause)

    /// Minimum delay before showing sentiment reaction after speech ends.
    /// Creates natural "processing" feel rather than instant robot response.
    public static let processingBeatMinMs: Int = 300

    /// Maximum delay before showing sentiment reaction after speech ends.
    public static let processingBeatMaxMs: Int = 500

    /// Convenience: Random processing beat duration in seconds
    public static var randomProcessingBeatSeconds: Float {
        Float.random(in: Float(processingBeatMinMs) / 1000...Float(processingBeatMaxMs) / 1000)
    }

    // MARK: - Expression Timing

    /// Minimum time to hold expression at peak intensity before starting decay.
    /// Ensures expression is clearly visible before fading.
    public static let expressionPeakHoldMs: Int = 500

    /// Duration for expression to decay from peak to neutral.
    /// Uses ease-out curve for natural fade.
    public static let expressionDecayMs: Int = 1500

    /// Expression decay duration in seconds
    public static var expressionDecaySeconds: Float {
        Float(expressionDecayMs) / 1000
    }

    /// Expression peak hold duration in seconds
    public static var expressionPeakHoldSeconds: Float {
        Float(expressionPeakHoldMs) / 1000
    }

    // MARK: - Mood Lingering (Post-Emote Persistence)

    /// Duration to hold lingering mood at peak after emote ends.
    /// Expression persists at full intensity during this period.
    public static let moodLingerHoldMs: Int = 2000

    /// Duration for lingering mood to decay from peak to neutral.
    /// Uses ease-out curve for natural fade.
    public static let moodLingerDecayMs: Int = 1500

    /// Mood linger hold duration in seconds
    public static var moodLingerHoldSeconds: Float {
        Float(moodLingerHoldMs) / 1000
    }

    /// Mood linger decay duration in seconds
    public static var moodLingerDecaySeconds: Float {
        Float(moodLingerDecayMs) / 1000
    }

    // MARK: - Idle Behavior Intervals

    /// Minimum interval between natural blinks (seconds)
    public static let blinkIntervalMinSeconds: Float = 2.0

    /// Maximum interval between natural blinks (seconds)
    public static let blinkIntervalMaxSeconds: Float = 6.0

    /// Random blink interval
    public static var randomBlinkInterval: Float {
        Float.random(in: blinkIntervalMinSeconds...blinkIntervalMaxSeconds)
    }

    /// Minimum interval between subtle weight shifts (seconds)
    public static let weightShiftIntervalMinSeconds: Float = 10.0

    /// Maximum interval between subtle weight shifts (seconds)
    public static let weightShiftIntervalMaxSeconds: Float = 20.0

    /// Random weight shift interval
    public static var randomWeightShiftInterval: Float {
        Float.random(in: weightShiftIntervalMinSeconds...weightShiftIntervalMaxSeconds)
    }

    // MARK: - Audio Timeout

    /// Minimum time of silence before showing expectant look (seconds)
    public static let noAudioTimeoutMinSeconds: Float = 5.0

    /// Maximum time of silence before showing expectant look (seconds)
    public static let noAudioTimeoutMaxSeconds: Float = 10.0

    /// Default no-audio timeout (middle of range)
    public static let noAudioTimeoutSeconds: Float = 7.0

    // MARK: - Welcome Animation

    /// Delay before playing welcome animation after model loads.
    /// Ensures model is fully initialized and visible.
    public static let welcomeAnimationDelayMs: Int = 500

    /// Welcome animation delay in seconds
    public static var welcomeAnimationDelaySeconds: Float {
        Float(welcomeAnimationDelayMs) / 1000
    }

    // MARK: - Barge-In / Interruption

    /// Delay after barge-in detection before resuming listening.
    /// Allows quick acknowledgment nod to play.
    public static let bargeInAcknowledgmentMs: Int = 150

    /// Audio fade-out duration for anti-pop cut (ms)
    public static let audioFadeOutMs: Int = 50

    /// Audio fade-out duration in seconds
    public static var audioFadeOutSeconds: Float {
        Float(audioFadeOutMs) / 1000
    }

    // MARK: - Micro-Expression (Interruption Jolt)

    /// Micro-expression attack duration (ms) - fast ramp up
    public static let microExpressionAttackMs: Int = 50

    /// Micro-expression sustain duration (ms) - brief hold
    public static let microExpressionSustainMs: Int = 100

    /// Micro-expression decay duration (ms) - return to previous state
    public static let microExpressionDecayMs: Int = 200

    /// Micro-expression attack duration in seconds
    public static var microExpressionAttackSeconds: Float {
        Float(microExpressionAttackMs) / 1000
    }

    /// Micro-expression sustain duration in seconds
    public static var microExpressionSustainSeconds: Float {
        Float(microExpressionSustainMs) / 1000
    }

    /// Micro-expression decay duration in seconds
    public static var microExpressionDecaySeconds: Float {
        Float(microExpressionDecayMs) / 1000
    }

    /// Total micro-expression duration in seconds
    public static var microExpressionTotalSeconds: Float {
        microExpressionAttackSeconds + microExpressionSustainSeconds + microExpressionDecaySeconds
    }

    // MARK: - Physics Damping

    /// Number of frames to apply physics braking during interruption
    public static let physicsBrakingFrames: Int = 8

    /// Drag multiplier during physics braking (higher = more damping)
    public static let physicsBrakingDragMultiplier: Float = 3.0

    // MARK: - Intensity Tiers

    /// Low intensity range for subtle expressions
    public static let intensityLowMin: Float = 0.2
    public static let intensityLowMax: Float = 0.4

    /// Medium intensity range for normal expressions
    public static let intensityMediumMin: Float = 0.5
    public static let intensityMediumMax: Float = 0.7

    /// High intensity range for strong expressions
    public static let intensityHighMin: Float = 0.8
    public static let intensityHighMax: Float = 1.0

    // MARK: - Easing Functions

    /// Ease-out curve for expression decay (quadratic)
    /// - Parameter t: Progress from 0 to 1
    /// - Returns: Eased value from 1 to 0
    public static func easeOutQuadratic(_ t: Float) -> Float {
        1.0 - (1.0 - t) * (1.0 - t)
    }

    /// Ease-in-out curve for smooth transitions
    /// - Parameter t: Progress from 0 to 1
    /// - Returns: Eased value from 0 to 1
    public static func easeInOutQuadratic(_ t: Float) -> Float {
        t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
    }

    /// Inverted ease-out for decay (starts fast, ends slow)
    /// - Parameter t: Progress from 0 to 1
    /// - Returns: Remaining intensity from 1 to 0
    public static func decayCurve(_ t: Float) -> Float {
        let clamped = max(0, min(1, t))
        return 1.0 - easeOutQuadratic(clamped)
    }

    // MARK: - Cognitive Gaze

    /// Minimum fixation duration (ms)
    public static let gazeFixationMinMs: Int = 200

    /// Maximum fixation duration (ms)
    public static let gazeFixationMaxMs: Int = 2000

    /// Minimum fixation duration in seconds
    public static var gazeFixationMinSeconds: Float {
        Float(gazeFixationMinMs) / 1000
    }

    /// Maximum fixation duration in seconds
    public static var gazeFixationMaxSeconds: Float {
        Float(gazeFixationMaxMs) / 1000
    }

    /// Random fixation duration in seconds
    public static var randomFixationDuration: Float {
        Float.random(in: gazeFixationMinSeconds...gazeFixationMaxSeconds)
    }

    /// Saccade speed in degrees per second (~500°/sec for human eyes)
    public static let gazeSaccadeSpeedDegPerSec: Float = 500.0

    /// Saccade speed in radians per second
    public static var gazeSaccadeSpeedRadPerSec: Float {
        gazeSaccadeSpeedDegPerSec * .pi / 180.0
    }

    /// Microsaccade amplitude in degrees (~0.2° during fixation)
    public static let gazeMicrosaccadeAmplitudeDeg: Float = 0.2

    /// Microsaccade amplitude in radians
    public static var gazeMicrosaccadeAmplitudeRad: Float {
        gazeMicrosaccadeAmplitudeDeg * .pi / 180.0
    }

    /// Saccade threshold in degrees - minimum angle change to trigger new saccade
    public static let gazeSaccadeThresholdDeg: Float = 2.0

    /// Saccade threshold in radians
    public static var gazeSaccadeThresholdRad: Float {
        gazeSaccadeThresholdDeg * .pi / 180.0
    }

    /// Blink trigger threshold in degrees - large saccades trigger blinks
    public static let gazeBlinkTriggerDeg: Float = 20.0

    /// Blink trigger threshold in radians
    public static var gazeBlinkTriggerRad: Float {
        gazeBlinkTriggerDeg * .pi / 180.0
    }

    /// Thinking look-away duration (ms)
    public static let thinkingGazeDurationMs: Int = 1500

    /// Thinking look-away duration in seconds
    public static var thinkingGazeDurationSeconds: Float {
        Float(thinkingGazeDurationMs) / 1000
    }

    /// Speaking glance-away cycle duration (seconds)
    public static let speakingGlanceCycleDuration: Float = 3.5

    /// Speaking glance-away offset time (when to look away during cycle)
    public static let speakingGlanceAwayStart: Float = 2.5

    /// VOR gain (slightly less than 1.0 for natural feel)
    public static let vorGain: Float = 0.95

    // MARK: - Turn-Yielding

    /// Expectant eyebrow intensity for questions
    public static let expectantBrowQuestionIntensity: Float = 0.6

    /// Expectant eyebrow intensity for statements
    public static let expectantBrowStatementIntensity: Float = 0.3

    /// Duration to hold expectant expression (seconds)
    public static let expectantHoldDurationSeconds: Float = 1.0

    /// Fade duration from expectant to listening (seconds)
    public static let expectantFadeDurationSeconds: Float = 0.5

    /// Silence breaker delay after TTS completion (seconds)
    public static let silenceBreakerDelaySeconds: Float = 5.0

    /// Yielding posture engagement level (leaning back)
    public static let yieldingPostureEngagement: Float = 0.3
}
