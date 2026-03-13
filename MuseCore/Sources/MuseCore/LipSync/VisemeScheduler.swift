//
//  VisemeScheduler.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation
import QuartzCore
import VRMMetalKit

// MARK: - Viseme Scheduler State

/// Current state of the viseme scheduler
public enum VisemeSchedulerState: Sendable {
    case idle          // No timeline loaded
    case prepared      // Timeline loaded, waiting for start signal
    case playing       // Actively playing visemes
    case paused        // Playback paused
    case completed     // Playback finished
}

// MARK: - Viseme Scheduler

/// Drives viseme playback synchronized to audio time
/// Updates each frame from ProceduralAnimationController
@MainActor
public final class VisemeScheduler {

    // MARK: - Properties

    /// Current scheduler state
    public private(set) var state: VisemeSchedulerState = .idle

    /// Current viseme timeline
    private var timeline: VisemeTimeline = VisemeTimeline()
    
    /// Number of visemes in the timeline (for debugging)
    public var visemeCount: Int { timeline.count }
    
    /// Total duration of the timeline (for debugging)
    public var timelineDuration: Double { timeline.duration }

    /// Time when audio playback started (CACurrentMediaTime)
    private var audioStartTime: Double = 0

    /// Current index in the timeline
    private var currentIndex: Int = 0

    /// Current viseme being displayed
    public private(set) var currentViseme: VRMViseme = .neutral

    /// Current viseme intensity (0-1)
    public private(set) var currentIntensity: Float = 0

    /// Secondary viseme for blending (coarticulation)
    public private(set) var secondaryViseme: VRMViseme? = nil

    /// Secondary viseme intensity
    public private(set) var secondaryIntensity: Float = 0

    /// Callback when viseme changes (for debugging/UI)
    public var onVisemeChange: ((VRMViseme, Float) -> Void)?

    /// Callback when playback completes
    public var onPlaybackComplete: (() -> Void)?

    // MARK: - Configuration

    /// How quickly visemes transition (higher = faster)
    public var transitionSpeed: Float = 8.0

    /// Base intensity for viseme expression
    public var baseIntensity: Float = 0.8

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Scale the prepared timeline to match actual audio duration
    /// Must be called after prepare() and before start()
    /// - Parameter factor: Scale factor (>1 = stretch longer, <1 = compress shorter)
    public func scaleTimeline(by factor: Double) {
        guard state == .prepared else { return }
        timeline.scale(by: factor)
    }

    /// Prepare a timeline for playback
    /// - Parameter timeline: The viseme timeline to play
    public func prepare(timeline: VisemeTimeline) {
        self.timeline = timeline
        self.currentIndex = 0
        self.currentViseme = .neutral
        self.currentIntensity = 0
        self.secondaryViseme = nil
        self.secondaryIntensity = 0
        self.state = timeline.isEmpty ? .idle : .prepared
    }

    /// Start synchronized playback
    /// - Parameter audioStartTime: The CACurrentMediaTime when audio started
    public func start(audioStartTime: Double = CACurrentMediaTime()) {
        guard state == .prepared else { return }
        self.audioStartTime = audioStartTime
        self.state = .playing
    }

    /// Pause playback
    public func pause() {
        guard state == .playing else { return }
        state = .paused
    }

    /// Resume playback
    public func resume() {
        guard state == .paused else { return }
        state = .playing
    }

    /// Stop playback and reset
    public func stop() {
        state = .idle
        timeline = VisemeTimeline()
        currentIndex = 0
        currentViseme = .neutral
        currentIntensity = 0
        secondaryViseme = nil
        secondaryIntensity = 0
    }

    /// Force stop with immediate viseme reset (no smoothing)
    /// Used for interruption protocol to snap mouth to neutral instantly
    public func forceStop() {
        state = .idle
        timeline = VisemeTimeline()
        currentIndex = 0
        currentViseme = .neutral
        currentIntensity = 0  // Skip smoothing - immediate zero
        secondaryViseme = nil
        secondaryIntensity = 0
        // Notify listeners of immediate neutral
        onVisemeChange?(.neutral, 0)
    }

    /// Update viseme state (called every frame from animation controller)
    /// - Parameter deltaTime: Time since last frame
    public func update(deltaTime: Float) {
        guard state == .playing, !timeline.isEmpty else {
            // Fade out when not playing
            if currentIntensity > 0.01 {
                currentIntensity = max(0, currentIntensity - deltaTime * transitionSpeed)
            }
            if secondaryIntensity > 0.01 {
                secondaryIntensity = max(0, secondaryIntensity - deltaTime * transitionSpeed)
            }
            return
        }

        // Calculate current audio time
        let currentAudioTime = CACurrentMediaTime() - audioStartTime

        // Check if we've passed the end of the timeline
        if currentAudioTime >= timeline.duration {
            state = .completed
            onPlaybackComplete?()
            return
        }

        // Find current viseme based on audio time
        guard let (currentTimedViseme, progress) = timeline.viseme(at: currentAudioTime) else {
            return
        }

        // Update current index for efficient lookup
        while currentIndex < timeline.count - 1 {
            if let next = timeline[currentIndex + 1],
               currentAudioTime >= next.startTime {
                currentIndex += 1
            } else {
                break
            }
        }

        // Get next viseme for blending
        let nextTimedViseme = timeline[currentIndex + 1]

        // Calculate blend for coarticulation
        let (primary, primaryWeight, secondary, secondaryWeight) = CoarticulationBlender.blend(
            from: currentTimedViseme.viseme,
            to: nextTimedViseme?.viseme ?? currentTimedViseme.viseme,
            progress: progress
        )

        // Update viseme state with per-viseme intensity profiles
        let previousViseme = currentViseme
        currentViseme = primary
        currentIntensity = primaryWeight * baseIntensity * primary.intensityProfile
        secondaryViseme = secondary
        secondaryIntensity = secondaryWeight * baseIntensity * (secondary?.intensityProfile ?? 0)

        // Notify if viseme changed
        if currentViseme != previousViseme {
            onVisemeChange?(currentViseme, currentIntensity)
        }
    }

    /// Get the current time within the timeline
    public var currentTime: Double {
        guard state == .playing || state == .paused else { return 0 }
        return CACurrentMediaTime() - audioStartTime
    }

    /// Get the total duration of the timeline
    public var duration: Double {
        timeline.duration
    }

    /// Get playback progress (0-1)
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, currentTime / duration)
    }
}

// MARK: - Expression Layer Integration

extension VisemeScheduler {

    /// Apply current viseme state to an expression layer
    /// - Parameter expressionLayer: The expression layer to update
    public func applyToExpressionLayer(_ expressionLayer: ExpressionLayer) {
        // Apply primary viseme
        if currentIntensity > 0.01 {
            expressionLayer.setExpression(currentViseme.expressionPreset, intensity: currentIntensity)
        }

        // Note: ExpressionLayer only supports one expression at a time,
        // so secondary viseme would need direct morph weight manipulation
        // for true coarticulation. For Phase 1, we use the primary only.
    }

    /// Get morph weights for direct application
    /// Per-viseme intensity profiles are already applied in currentIntensity/secondaryIntensity
    /// - Returns: Dictionary of morph target names to weights
    public func getMorphWeights() -> [String: Float] {
        var weights: [String: Float] = [:]

        // Add primary viseme weight (intensity already includes per-viseme profile)
        if currentIntensity > 0.01 {
            weights[currentViseme.expressionPreset.rawValue] = currentIntensity
        }

        // Add secondary viseme weight for smooth blending
        if let secondary = secondaryViseme, secondaryIntensity > 0.01 {
            weights[secondary.expressionPreset.rawValue] = secondaryIntensity
        }

        return weights
    }
}
