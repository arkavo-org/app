//
//  VisemeTimeline.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation
import VRMMetalKit

// MARK: - VRM Viseme

/// VRM-compatible viseme presets for lip sync
/// Maps to VRMExpressionPreset: aa, ih, ou, ee, oh
public enum VRMViseme: String, CaseIterable, Sendable {
    case aa      // Wide open mouth (a, ah sounds)
    case ih      // Narrow/smile (i, e sounds)
    case ou      // Rounded lips (o, u sounds)
    case ee      // Teeth showing (ee sound)
    case oh      // Small round (o sound)
    case neutral // Closed/rest position

    /// Convert to VRMExpressionPreset for the expression layer
    public var expressionPreset: VRMExpressionPreset {
        switch self {
        case .aa: return .aa
        case .ih: return .ih
        case .ou: return .ou
        case .ee: return .ee
        case .oh: return .oh
        case .neutral: return .neutral
        }
    }

    /// Per-viseme intensity profile for more natural lip sync
    /// Vowels get full intensity, consonants/narrow shapes get reduced intensity
    public var intensityProfile: Float {
        switch self {
        case .aa: return 1.0    // Wide open - full intensity
        case .oh: return 1.0    // Open round - full intensity
        case .ee: return 0.9    // Teeth showing - high intensity
        case .ou: return 0.85   // Rounded/pucker - moderate-high
        case .ih: return 0.7    // Narrow/subtle smile - moderate
        case .neutral: return 0.0  // Closed - no expression
        }
    }
}

// MARK: - Phoneme Type

/// Categories of phonemes for duration estimation
public enum PhonemeType: Sendable {
    case vowel          // aa, ih, ou, ee, oh - longest duration
    case stopConsonant  // p, b, t, d, k, g - brief closure
    case fricative      // f, v, s, z, sh, zh, th - sustained friction
    case nasal          // m, n, ng - nasal resonance
    case liquid         // l, r - semi-vowels
    case glide          // w, y - transitional
    case silence        // inter-word pause
}

// MARK: - Timed Viseme

/// A viseme with timing information for scheduling
public struct TimedViseme: Sendable {
    /// The target viseme
    public let viseme: VRMViseme

    /// Start time relative to audio start (seconds)
    public let startTime: Double

    /// Duration of this viseme (seconds)
    public let duration: Double

    /// End time (startTime + duration)
    public var endTime: Double { startTime + duration }

    public init(viseme: VRMViseme, startTime: Double, duration: Double) {
        self.viseme = viseme
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Viseme Timeline

/// A sequence of timed visemes for playback
public struct VisemeTimeline: Sendable {
    /// Ordered sequence of timed visemes
    public private(set) var visemes: [TimedViseme]

    /// Total duration of the timeline
    public var duration: Double {
        visemes.last?.endTime ?? 0
    }

    /// Whether the timeline is empty
    public var isEmpty: Bool {
        visemes.isEmpty
    }

    /// Number of visemes in the timeline
    public var count: Int {
        visemes.count
    }

    public init(visemes: [TimedViseme] = []) {
        self.visemes = visemes
    }

    /// Find the viseme active at a given time
    /// - Parameter time: Time in seconds from start
    /// - Returns: The active viseme and its progress (0-1), or nil if time is out of range
    public func viseme(at time: Double) -> (viseme: TimedViseme, progress: Double)? {
        guard !visemes.isEmpty else { return nil }

        // Binary search for efficiency on large timelines
        var low = 0
        var high = visemes.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let v = visemes[mid]

            if time < v.startTime {
                high = mid - 1
            } else if time >= v.endTime {
                low = mid + 1
            } else {
                // Found the active viseme
                let progress = (time - v.startTime) / v.duration
                return (v, min(1.0, max(0.0, progress)))
            }
        }

        // Time is before first viseme or after last
        if time < visemes[0].startTime {
            return (visemes[0], 0.0)
        } else {
            return (visemes[visemes.count - 1], 1.0)
        }
    }

    /// Get the viseme at a specific index
    public subscript(index: Int) -> TimedViseme? {
        guard index >= 0 && index < visemes.count else { return nil }
        return visemes[index]
    }

    /// Append a viseme to the timeline
    public mutating func append(_ viseme: TimedViseme) {
        visemes.append(viseme)
    }

    /// Scale all timings by a factor (for speech rate adjustment)
    /// - Parameter factor: Scale factor (>1 = slower, <1 = faster)
    public mutating func scale(by factor: Double) {
        visemes = visemes.map { v in
            TimedViseme(
                viseme: v.viseme,
                startTime: v.startTime * factor,
                duration: v.duration * factor
            )
        }
    }
}
