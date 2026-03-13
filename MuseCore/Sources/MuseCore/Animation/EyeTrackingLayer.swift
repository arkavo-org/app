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
import simd
import VRMMetalKit

// MARK: - Gaze State Machine

/// State machine for biologically accurate saccadic eye movement.
/// Human eyes don't smoothly track - they fixate, then jump ballistically to new targets.
public enum GazeState {
    /// Holding gaze at current position with microsaccades
    case fixation(targetDuration: Float, elapsed: Float)

    /// Ballistic movement to new target (no tracking during movement)
    case saccade(from: SIMD2<Float>, to: SIMD2<Float>, duration: Float, elapsed: Float)
}

// MARK: - Eye Tracking Layer

/// Cognitive gaze system with biologically accurate eye tracking.
/// Features:
/// - Saccadic movement (fixate -> ballistic jump -> fixate)
/// - Cognitive aversion (thinking = look away, listening = focused)
/// - Vestibulo-ocular reflex (counter-rotate eyes when head moves)
/// - Blink-gaze coupling (large saccades trigger blinks)
///
/// Uses morph expressions (lookLeft/Right/Up/Down) since eye bones are optional in VRM.
/// Priority 7 ensures eyes override other layers' head movements.
public class EyeTrackingLayer: AnimationLayer {

    // MARK: - AnimationLayer Protocol

    public let identifier = "muse.eyetracking"
    public let priority = 8  // High priority for eye control (after physics interaction at 7)
    public var isEnabled = true

    /// This layer doesn't affect bones directly - uses morph expressions instead
    public var affectedBones: Set<VRMHumanoidBone> {
        []
    }

    // MARK: - Gaze State Machine

    /// Current state in the saccade/fixation cycle
    private var gazeState: GazeState = .fixation(
        targetDuration: AnimationTimingConfig.randomFixationDuration,
        elapsed: 0
    )

    /// Current gaze position (yaw, pitch) in radians
    private var currentGaze: SIMD2<Float> = .zero

    /// Target gaze from cognitive processing
    private var cognitiveTarget: SIMD2<Float>? = nil

    // MARK: - Cognitive State

    /// Current conversation state for cognitive aversion
    private var conversationState: ProceduralConversationState = .idle

    /// Direction for thinking look (1.0 = right, -1.0 = left)
    private var thinkingLookDirection: Float = 1.0

    /// Timer for speaking glance cycle
    private var speakingGlanceTimer: Float = 0

    /// Whether we've chosen thinking direction for this thinking episode
    private var hasChosenThinkingDirection: Bool = false

    // MARK: - Vestibulo-Ocular Reflex (VOR)

    /// Previous frame head yaw for velocity calculation
    private var previousHeadYaw: Float = 0

    /// Previous frame head pitch for velocity calculation
    private var previousHeadPitch: Float = 0

    /// Accumulated VOR compensation (applied in evaluate)
    private var vorCompensation: SIMD2<Float> = .zero

    /// VOR gain (0.95 = slightly under-compensate for natural feel)
    public var vorGain: Float = AnimationTimingConfig.vorGain

    // MARK: - Head Tracking

    /// Current head yaw from animation context
    private var headYaw: Float = 0

    /// Current head pitch from animation context
    private var headPitch: Float = 0

    // MARK: - Blink Coordination

    /// Callback to trigger blink when gaze shifts significantly
    public var onBlinkRequest: (() -> Void)?

    /// Cooldown timer to prevent excessive blink requests
    private var blinkCooldown: Float = 0

    /// Minimum time between blink requests (seconds)
    private let blinkCooldownDuration: Float = 0.3

    // MARK: - Configuration

    /// Maximum eye yaw angle (~30 degrees)
    public var maxYaw: Float = 0.52

    /// Maximum eye pitch angle (~25 degrees)
    public var maxPitch: Float = 0.44

    /// Saccade speed in radians/second (~500 deg/sec)
    public var saccadeSpeed: Float = AnimationTimingConfig.gazeSaccadeSpeedRadPerSec

    /// Minimum angle change to trigger saccade (~2 deg)
    public var saccadeThreshold: Float = AnimationTimingConfig.gazeSaccadeThresholdRad

    /// Microsaccade amplitude (~0.2 deg)
    public var microsaccadeAmplitude: Float = AnimationTimingConfig.gazeMicrosaccadeAmplitudeRad

    /// Angle threshold to trigger blink during saccade (~20 deg)
    public var blinkTriggerAngle: Float = AnimationTimingConfig.gazeBlinkTriggerRad

    /// Head compensation factor for static compensation
    public var headCompensation: Float = 0.8

    /// Fixation duration multiplier (inverse of saccade frequency)
    public var fixationDurationMultiplier: Float = 1.0

    // MARK: - Camera/Avatar Positions

    private var cameraPosition: SIMD3<Float> = SIMD3<Float>(0, 1.6, 2.5)
    private var avatarPosition: SIMD3<Float> = .zero

    // MARK: - Cached Output

    private var cachedOutput = LayerOutput(blendMode: .additive)

    // MARK: - Initialization

    public init() {
        // Randomize initial thinking direction
        thinkingLookDirection = Bool.random() ? 1.0 : -1.0
    }

    // MARK: - Public API

    /// Set the current conversation state for cognitive gaze behavior
    /// - Parameter state: Current conversation state
    public func setConversationState(_ state: ProceduralConversationState) {
        let previousState = conversationState
        conversationState = state

        // Reset thinking direction choice when entering thinking state
        if state == .thinking && previousState != .thinking {
            hasChosenThinkingDirection = false
        }

        // Reset speaking timer when entering speaking state
        if state == .speaking && previousState != .speaking {
            speakingGlanceTimer = 0
        }
    }

    /// Force immediate saccade to user/camera for interruption protocol.
    /// Bypasses normal fixation timing to snap gaze to user instantly.
    /// Triggers blink for large gaze changes (>20 deg) to match biological behavior.
    public func forceSaccadeToUser() {
        // Calculate target gaze at camera (center = user)
        let target = calculateCameraGaze()

        // Calculate angle change for blink decision
        let angleChange = angleBetween(currentGaze, target)

        // Trigger blink for large saccades (>20 deg)
        if angleChange > blinkTriggerAngle && blinkCooldown <= 0 {
            onBlinkRequest?()
            blinkCooldown = blinkCooldownDuration
        }

        // Force immediate saccade to target (30ms duration)
        gazeState = .saccade(
            from: currentGaze,
            to: target,
            duration: 0.03,  // 30ms ballistic movement
            elapsed: 0
        )
    }

    // MARK: - AnimationLayer Protocol

    public func update(deltaTime: Float, context: AnimationContext) {
        // Store positions from context
        cameraPosition = context.cameraPosition
        avatarPosition = context.avatarPosition

        // Update conversation state from context
        setConversationState(context.conversationState)

        // Update blink cooldown
        if blinkCooldown > 0 {
            blinkCooldown -= deltaTime
        }

        // Update speaking glance timer
        if conversationState == .speaking {
            speakingGlanceTimer += deltaTime
            if speakingGlanceTimer >= AnimationTimingConfig.speakingGlanceCycleDuration {
                speakingGlanceTimer = 0
            }
        }

        // Calculate VOR compensation from head velocity
        updateVOR(deltaTime: deltaTime)

        // Update gaze state machine
        updateGazeStateMachine(deltaTime: deltaTime)
    }

    public func evaluate() -> LayerOutput {
        cachedOutput.morphWeights.removeAll(keepingCapacity: true)

        // Get final gaze with VOR compensation
        let compensatedYaw = currentGaze.x - headYaw * headCompensation + vorCompensation.x
        let compensatedPitch = currentGaze.y - headPitch * headCompensation + vorCompensation.y

        // Clamp to eye movement range
        let clampedYaw = clamp(compensatedYaw, -maxYaw, maxYaw)
        let clampedPitch = clamp(compensatedPitch, -maxPitch, maxPitch)

        // Apply VRM lookAt morph expressions
        applyLookMorphs(yaw: clampedYaw, pitch: clampedPitch)

        return cachedOutput
    }

    // MARK: - Head Rotation Input

    /// Update head rotation for compensation
    /// - Parameters:
    ///   - yaw: Current head yaw in radians
    ///   - pitch: Current head pitch in radians
    public func updateHeadRotation(yaw: Float, pitch: Float) {
        headYaw = yaw
        headPitch = pitch
    }

    // MARK: - Private: VOR

    /// Update vestibulo-ocular reflex - counter-rotate eyes based on head velocity
    private func updateVOR(deltaTime: Float) {
        guard deltaTime > 0.001 else {
            vorCompensation = .zero
            return
        }

        // Calculate head angular velocity
        let headYawVelocity = (headYaw - previousHeadYaw) / deltaTime
        let headPitchVelocity = (headPitch - previousHeadPitch) / deltaTime

        // Store for next frame
        previousHeadYaw = headYaw
        previousHeadPitch = headPitch

        // Apply inverse velocity as immediate compensation
        // This counter-rotates eyes to maintain world-space gaze direction
        vorCompensation = SIMD2<Float>(
            -headYawVelocity * deltaTime * vorGain,
            -headPitchVelocity * deltaTime * vorGain
        )
    }

    // MARK: - Private: Gaze State Machine

    /// Update the saccade/fixation state machine
    private func updateGazeStateMachine(deltaTime: Float) {
        switch gazeState {
        case .fixation(let targetDuration, var elapsed):
            elapsed += deltaTime

            // Add microsaccades during fixation (tiny jitter)
            currentGaze += microsaccadeOffset()

            // Check if fixation duration complete
            if elapsed >= targetDuration {
                // Calculate new target based on cognitive state
                let newTarget = calculateGazeTarget()
                let angleToTarget = angleBetween(currentGaze, newTarget)

                if angleToTarget > saccadeThreshold {
                    // Large enough change - initiate saccade
                    if angleToTarget > blinkTriggerAngle && blinkCooldown <= 0 {
                        onBlinkRequest?()
                        blinkCooldown = blinkCooldownDuration
                    }

                    // Calculate saccade duration based on distance
                    // Typical saccade: 30-50ms for most movements
                    let saccadeDuration = max(0.03, min(0.05, angleToTarget / saccadeSpeed))

                    gazeState = .saccade(
                        from: currentGaze,
                        to: newTarget,
                        duration: saccadeDuration,
                        elapsed: 0
                    )
                } else {
                    // Target hasn't changed much - stay in fixation
                    gazeState = .fixation(
                        targetDuration: randomFixationDuration(),
                        elapsed: 0
                    )
                }
            } else {
                // Continue fixation
                gazeState = .fixation(targetDuration: targetDuration, elapsed: elapsed)
            }

        case .saccade(let from, let to, let duration, var elapsed):
            elapsed += deltaTime
            let t = min(elapsed / duration, 1.0)

            // Linear interpolation during saccade (ballistic - no tracking)
            currentGaze = from + (to - from) * t

            if t >= 1.0 {
                // Saccade complete - enter fixation at target
                currentGaze = to
                gazeState = .fixation(
                    targetDuration: randomFixationDuration(),
                    elapsed: 0
                )
            } else {
                gazeState = .saccade(from: from, to: to, duration: duration, elapsed: elapsed)
            }
        }
    }

    // MARK: - Private: Cognitive Gaze Targeting

    /// Calculate gaze target based on cognitive/conversation state
    private func calculateGazeTarget() -> SIMD2<Float> {
        // First check for cognitive state overrides
        if let cognitiveTarget = calculateCognitiveTarget() {
            return cognitiveTarget
        }

        // Default: gaze at camera
        return calculateCameraGaze()
    }

    /// Calculate cognitive state override target
    private func calculateCognitiveTarget() -> SIMD2<Float>? {
        switch conversationState {
        case .idle:
            // Natural gaze at camera with normal saccade behavior
            return nil

        case .listening:
            // Focused on user - force camera gaze, reduce saccade variation
            return nil

        case .thinking:
            // Look up and to the side (visual memory access pattern)
            if !hasChosenThinkingDirection {
                thinkingLookDirection = Bool.random() ? 1.0 : -1.0
                hasChosenThinkingDirection = true
            }

            // 20 deg lateral + 30 deg up
            return SIMD2<Float>(
                0.35 * thinkingLookDirection,  // ~20 deg left or right
                0.52                            // ~30 deg up
            )

        case .speaking:
            // Alternate between user and glance away
            // 70% look at user, 30% glance to side
            if speakingGlanceTimer < AnimationTimingConfig.speakingGlanceAwayStart {
                return nil  // Look at user
            } else {
                // Glance to side during brief away period
                return SIMD2<Float>(0.26, 0.1)  // ~15 deg right, slight up
            }
        }
    }

    /// Calculate gaze direction to camera
    private func calculateCameraGaze() -> SIMD2<Float> {
        let headPosition = avatarPosition + SIMD3<Float>(0, 1.5, 0)
        let toCamera = cameraPosition - headPosition
        let distance = simd_length(toCamera)

        guard distance > 0.1 else {
            return currentGaze
        }

        let direction = toCamera / distance

        let targetYaw = atan2(direction.x, direction.z)
        let targetPitch = asin(clamp(direction.y, -1.0, 1.0))

        return SIMD2<Float>(targetYaw, targetPitch)
    }

    // MARK: - Private: Microsaccades

    /// Generate tiny random offset for microsaccades during fixation
    private func microsaccadeOffset() -> SIMD2<Float> {
        SIMD2<Float>(
            Float.random(in: -microsaccadeAmplitude...microsaccadeAmplitude),
            Float.random(in: -microsaccadeAmplitude...microsaccadeAmplitude) * 0.5
        )
    }

    // MARK: - Private: Helper Methods

    /// Random fixation duration based on conversation state
    private func randomFixationDuration() -> Float {
        let baseDuration: Float
        switch conversationState {
        case .listening:
            // Longer fixations when listening (focused attention)
            baseDuration = Float.random(in: 0.8...2.5)
        case .thinking:
            // Medium fixations during thinking
            baseDuration = Float.random(in: 0.5...1.5)
        case .speaking, .idle:
            // Normal range
            baseDuration = AnimationTimingConfig.randomFixationDuration
        }
        return baseDuration * fixationDurationMultiplier
    }

    /// Update from persona configuration
    /// - Parameter saccadeFrequency: Saccade frequency multiplier (higher = more frequent saccades)
    public func updateConfig(saccadeFrequency: Float) {
        // Inverse: higher frequency = shorter fixation durations
        self.fixationDurationMultiplier = 1.0 / max(saccadeFrequency, 0.1)
    }

    /// Calculate angle between two gaze directions
    private func angleBetween(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let diff = b - a
        return sqrt(diff.x * diff.x + diff.y * diff.y)
    }

    /// Apply look morph weights based on yaw and pitch
    private func applyLookMorphs(yaw: Float, pitch: Float) {
        // lookLeft/lookRight for horizontal gaze
        if yaw < 0 {
            let intensity = min(abs(yaw) / maxYaw, 1.0)
            cachedOutput.morphWeights["lookLeft"] = intensity
            cachedOutput.morphWeights["lookRight"] = 0
        } else {
            let intensity = min(yaw / maxYaw, 1.0)
            cachedOutput.morphWeights["lookRight"] = intensity
            cachedOutput.morphWeights["lookLeft"] = 0
        }

        // lookUp/lookDown for vertical gaze
        if pitch > 0 {
            let intensity = min(pitch / maxPitch, 1.0)
            cachedOutput.morphWeights["lookUp"] = intensity
            cachedOutput.morphWeights["lookDown"] = 0
        } else {
            let intensity = min(abs(pitch) / maxPitch, 1.0)
            cachedOutput.morphWeights["lookDown"] = intensity
            cachedOutput.morphWeights["lookUp"] = 0
        }
    }

    private func clamp(_ value: Float, _ minVal: Float, _ maxVal: Float) -> Float {
        min(max(value, minVal), maxVal)
    }
}
