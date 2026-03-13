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

/// Controls welcome animations based on time of day and user status.
/// Provides personalized greetings that feel natural and contextual.
@MainActor
public class WelcomeAnimationController {

    // MARK: - Launch State

    /// Represents the user's launch state for welcome variant selection
    public enum LaunchState {
        case firstLaunch
        case returningKnownUser
        case returningUnknownUser
    }

    // MARK: - Entrance Phase

    /// Phases of the walk-in entrance sequence
    public enum EntrancePhase {
        case offScreen       // Initial load position, physics settling
        case walkingIn       // Moving toward center
        case arriving        // Stopping, turning to face camera
        case settling        // Body settles after walk (damped oscillation)
        case greeting        // Wave animation
        case complete        // Normal idle
    }

    // MARK: - Entrance State

    private var entrancePhase: EntrancePhase = .offScreen
    private var entranceProgress: Float = 0
    // Start position: far left, at same depth as camera target
    // This ensures avatar walks in from off-screen left
    private let entranceStartPosition: SIMD3<Float> = SIMD3(-3, 0, 0)
    private let entranceEndPosition: SIMD3<Float> = .zero
    private let entranceDuration: Float = 2.0  // seconds to walk in (longer for more distance)
    private let turnDuration: Float = 0.3      // seconds to turn to face camera
    private let settlingDuration: Float = 0.5  // seconds for body to settle after stopping

    /// Whether the entrance sequence is currently active
    public var isEntranceActive: Bool {
        entrancePhase != .complete
    }

    /// Callback to trigger walk animation
    public var onStartWalk: (() -> Void)?

    /// Callback to stop walk animation
    public var onStopWalk: (() -> Void)?

    /// Callback to update model position and rotation
    public var onPositionUpdate: ((SIMD3<Float>, Float) -> Void)?

    /// Callback to apply settling spine tilt (damped oscillation when stopping)
    /// Parameter is the spine forward tilt in radians (positive = forward lean)
    public var onSettlingTilt: ((Float) -> Void)?

    /// Start the entrance sequence
    public func startEntranceSequence() {
        entrancePhase = .walkingIn
        entranceProgress = 0
        onStartWalk?()
    }

    /// Get initial off-screen position for model load
    public func getInitialPosition() -> (position: SIMD3<Float>, rotationY: Float) {
        // Face toward center during approach
        // VRM models face +Z by default, so we need to rotate to face walking direction
        let toTarget = entranceEndPosition - entranceStartPosition
        let walkRotationY = atan2(-toTarget.x, -toTarget.z)  // Negate to face toward target
        return (entranceStartPosition, walkRotationY)
    }

    /// Update entrance animation
    /// - Parameter deltaTime: Time since last frame
    /// - Returns: Current phase after update
    public func updateEntrance(deltaTime: Float) -> EntrancePhase {
        guard entrancePhase != .complete else { return .complete }

        entranceProgress += deltaTime

        switch entrancePhase {
        case .offScreen:
            // Waiting to start - should not get here normally
            break

        case .walkingIn:
            let t = easeOutCubic(min(entranceProgress / entranceDuration, 1.0))
            let currentPosition = simd_mix(entranceStartPosition, entranceEndPosition, SIMD3(repeating: t))

            // Face walking direction (negate to face toward target, not away)
            let toTarget = entranceEndPosition - currentPosition
            let walkRotationY = atan2(-toTarget.x, -toTarget.z)

            onPositionUpdate?(currentPosition, walkRotationY)

            if entranceProgress >= entranceDuration {
                entrancePhase = .arriving
                entranceProgress = 0
                onStopWalk?()
            }

        case .arriving:
            // Turn to face camera (rotationY = 0 means facing +Z toward camera)
            let turnProgress = min(entranceProgress / turnDuration, 1.0)
            let toTarget = entranceEndPosition - entranceStartPosition
            let walkRotationY = atan2(-toTarget.x, -toTarget.z)
            // Final rotation = 0 to face camera (camera is at +Z)
            let finalRotationY = simd_mix(walkRotationY, 0, turnProgress)

            onPositionUpdate?(entranceEndPosition, finalRotationY)

            if entranceProgress >= turnDuration {
                entrancePhase = .settling
                entranceProgress = 0
            }

        case .settling:
            // Body settles after stopping with damped oscillation
            // Creates natural "rocking" motion as momentum dissipates
            let t = entranceProgress / settlingDuration
            // Damped oscillation: A * e^(-damping*t) * sin(frequency*t)
            // - damping=4.0: fairly quick decay
            // - frequency=8.0: ~1.3 oscillations in 0.5s
            // - amplitude=0.08: ~4.6 deg forward tilt max
            let dampedT = min(t, 1.0) * 4.0  // Scale time for damping
            let settleAmount = 0.08 * exp(-dampedT) * sin(dampedT * 8.0)
            onSettlingTilt?(settleAmount)

            // Keep position stable during settling
            onPositionUpdate?(entranceEndPosition, 0)

            if entranceProgress >= settlingDuration {
                // Clear the settling tilt before transitioning
                onSettlingTilt?(0)
                entrancePhase = .greeting
                entranceProgress = 0
            }

        case .greeting:
            // Greeting animation is triggered externally
            // Wait for animation to complete (handled by playWelcomeAnimation)
            entrancePhase = .complete

        case .complete:
            break
        }

        return entrancePhase
    }

    /// Reset entrance state for new model load
    public func resetEntrance() {
        entrancePhase = .offScreen
        entranceProgress = 0
    }

    /// Ease-out cubic for natural deceleration
    private func easeOutCubic(_ t: Float) -> Float {
        return 1 - pow(1 - t, 3)
    }

    // MARK: - Time of Day

    public enum TimeOfDay: String, CaseIterable {
        case morning    // 5:00 - 11:59
        case afternoon  // 12:00 - 16:59
        case evening    // 17:00 - 20:59
        case night      // 21:00 - 4:59

        public static var current: TimeOfDay {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:
                return .morning
            case 12..<17:
                return .afternoon
            case 17..<21:
                return .evening
            default:
                return .night
            }
        }
    }

    // MARK: - Welcome Variant

    public struct WelcomeVariant {
        let emote: EmoteAnimationLayer.Emote
        let expression: VRMExpressionPreset
        let intensity: Float
        let secondaryEmote: EmoteAnimationLayer.Emote?

        init(
            emote: EmoteAnimationLayer.Emote,
            expression: VRMExpressionPreset,
            intensity: Float,
            secondaryEmote: EmoteAnimationLayer.Emote? = nil
        ) {
            self.emote = emote
            self.expression = expression
            self.intensity = intensity
            self.secondaryEmote = secondaryEmote
        }
    }

    // MARK: - User Defaults Keys

    private enum Keys {
        static let hasLaunchedBefore = "com.arkavo.muse.hasLaunchedBefore"
        static let lastWelcomeDate = "com.arkavo.muse.lastWelcomeDate"
    }

    // MARK: - Properties

    /// Current launch state (injected, replaces FirstLaunchCoordinator.shared dependency)
    public var launchState: LaunchState = .firstLaunch

    /// Callback to trigger emote animation
    public var onTriggerEmote: ((EmoteAnimationLayer.Emote) -> Void)?

    /// Callback to set expression
    public var onSetExpression: ((VRMExpressionPreset, Float) -> Void)?

    /// Callback to play latest VRMA clip (for dev testing)
    public var onPlayLatestVRMA: (() -> Void)?

    /// Callback when greeting animation phase completes (for first-launch speech)
    public var onGreetingPhaseComplete: (() -> Void)?

    /// Track if welcome has been shown this session
    private var hasShownWelcomeThisSession = false

    // MARK: - Public API

    /// Check if this is the user's first time launching the app
    public var isFirstTimeUser: Bool {
        !UserDefaults.standard.bool(forKey: Keys.hasLaunchedBefore)
    }

    /// Mark that the user has launched the app before
    public func markUserAsReturning() {
        UserDefaults.standard.set(true, forKey: Keys.hasLaunchedBefore)
        UserDefaults.standard.set(Date(), forKey: Keys.lastWelcomeDate)
    }

    /// Get the appropriate welcome variant based on launch state
    public func getWelcomeVariant() -> WelcomeVariant {
        switch launchState {
        case .firstLaunch:
            // First-time user: Gentle look-up, soft smile, small wave
            // Not overly eager - natural introduction
            return WelcomeVariant(
                emote: .wave,
                expression: .happy,
                intensity: 0.5  // Soft, not over-eager
            )

        case .returningKnownUser:
            // Known user: Recognition nod, familiar smile
            return WelcomeVariant(
                emote: .nod,
                expression: .happy,
                intensity: 0.6
            )

        case .returningUnknownUser:
            // Unknown returning user: Friendly wave, moderate warmth
            return WelcomeVariant(
                emote: .wave,
                expression: .relaxed,
                intensity: 0.4
            )
        }
    }

    /// Play the welcome animation sequence
    /// Call after model is loaded and visible
    public func playWelcomeAnimation() {
        guard !hasShownWelcomeThisSession else { return }

        hasShownWelcomeThisSession = true
        let variant = getWelcomeVariant()

        // Set expression first
        onSetExpression?(variant.expression, variant.intensity)

        // Trigger primary emote
        onTriggerEmote?(variant.emote)

        // If there's a secondary emote, play it after primary
        if let secondaryEmote = variant.secondaryEmote {
            Task {
                // Wait for primary emote to complete (approximate duration)
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                onTriggerEmote?(secondaryEmote)

                // Play latest.vrma after secondary emote
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                onPlayLatestVRMA?()

                // Signal greeting phase complete for first-launch speech
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s settle
                onGreetingPhaseComplete?()
            }
        } else {
            // No secondary emote - trigger greeting complete after primary
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0s
                onPlayLatestVRMA?()

                // Signal greeting phase complete for first-launch speech
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s settle
                onGreetingPhaseComplete?()
            }
        }

        // Mark user as returning for next launch (after greeting complete callback)
        // Note: FirstLaunchCoordinator manages its own state separately
        markUserAsReturning()
    }

    /// Reset welcome state for testing
    public func resetWelcomeState() {
        hasShownWelcomeThisSession = false
        UserDefaults.standard.removeObject(forKey: Keys.hasLaunchedBefore)
        UserDefaults.standard.removeObject(forKey: Keys.lastWelcomeDate)
    }
}
