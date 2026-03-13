//
//  PhonemeToVisemeMapper.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation

// MARK: - Phoneme to Viseme Mapper

/// Maps ARPABET phonemes to VRM visemes and estimates timing
public struct PhonemeToVisemeMapper: Sendable {

    /// Default speech rate (AVSpeechUtteranceDefaultSpeechRate = 0.5)
    public static let defaultSpeechRate: Float = 0.5

    // MARK: - Phoneme to Viseme Mapping

    /// ARPABET phoneme to VRM viseme mapping
    /// Based on phonetic articulation patterns
    private static let visemeMap: [String: VRMViseme] = [
        // Vowels - AA group (wide open mouth)
        "AA": .aa,  // odd, father
        "AE": .aa,  // at, bat
        "AH": .aa,  // hut, but (schwa-like)
        "AO": .oh,  // awe, caught
        "AW": .aa,  // out, cow (diphthong starts open)
        "AY": .aa,  // eye, my (diphthong starts open)

        // Vowels - IH group (narrow/smile)
        "IH": .ih,  // it, bit
        "IY": .ee,  // eat, bee
        "EY": .ee,  // ate, say
        "EH": .ih,  // get, bed

        // Vowels - OU group (rounded lips)
        "OW": .ou,  // go, boat
        "UW": .ou,  // boot, too
        "UH": .ou,  // book, put
        "OY": .ou,  // boy, toy

        // R-colored vowels
        "ER": .ih,  // bird, her

        // Consonants - Bilabial (lips together)
        "P": .neutral,
        "B": .neutral,
        "M": .neutral,

        // Consonants - Labiodental (teeth on lip)
        "F": .ih,
        "V": .ih,

        // Consonants - Dental (tongue between teeth)
        "TH": .ih,
        "DH": .ih,

        // Consonants - Alveolar (tongue on ridge)
        "T": .neutral,
        "D": .neutral,
        "N": .neutral,
        "S": .ih,
        "Z": .ih,
        "L": .neutral,
        "R": .neutral,

        // Consonants - Palatal/Postalveolar
        "SH": .ih,
        "ZH": .ih,
        "CH": .ih,
        "JH": .ih,
        "Y": .ih,

        // Consonants - Velar (back of mouth)
        "K": .neutral,
        "G": .neutral,
        "NG": .neutral,

        // Consonants - Glides
        "W": .ou,
        "HH": .neutral,
    ]

    /// Phoneme type classification for duration estimation
    private static let phonemeTypes: [String: PhonemeType] = [
        // Vowels
        "AA": .vowel, "AE": .vowel, "AH": .vowel, "AO": .vowel,
        "AW": .vowel, "AY": .vowel, "IH": .vowel, "IY": .vowel,
        "EY": .vowel, "EH": .vowel, "OW": .vowel, "UW": .vowel,
        "UH": .vowel, "OY": .vowel, "ER": .vowel,

        // Stop consonants
        "P": .stopConsonant, "B": .stopConsonant, "T": .stopConsonant,
        "D": .stopConsonant, "K": .stopConsonant, "G": .stopConsonant,

        // Fricatives
        "F": .fricative, "V": .fricative, "TH": .fricative, "DH": .fricative,
        "S": .fricative, "Z": .fricative, "SH": .fricative, "ZH": .fricative,
        "HH": .fricative,

        // Affricates (treated as fricatives)
        "CH": .fricative, "JH": .fricative,

        // Nasals
        "M": .nasal, "N": .nasal, "NG": .nasal,

        // Liquids
        "L": .liquid, "R": .liquid,

        // Glides
        "W": .glide, "Y": .glide,
    ]

    /// Base durations in seconds for each phoneme type at normal speech rate
    private static let baseDurations: [PhonemeType: Double] = [
        .vowel: 0.080,          // Vowels are longest
        .stopConsonant: 0.040,  // Brief closure and release
        .fricative: 0.060,      // Sustained friction
        .nasal: 0.050,          // Nasal resonance
        .liquid: 0.055,         // Semi-vowels
        .glide: 0.045,          // Transitional
        .silence: 0.100,        // Inter-word pause
    ]

    public init() {}

    // MARK: - Public API

    /// Convert phonemes to a viseme timeline
    /// - Parameters:
    ///   - phonemes: Array of ARPABET phoneme strings
    ///   - speechRate: AVSpeechUtterance rate (0.0-1.0, default 0.5)
    /// - Returns: VisemeTimeline with timed viseme sequence
    public func createTimeline(phonemes: [String], speechRate: Float = defaultSpeechRate) -> VisemeTimeline {
        var timeline = VisemeTimeline()
        var currentTime: Double = 0

        // Rate multiplier: lower rate = longer duration
        // At rate 0.5 (default), multiplier is 1.0
        // At rate 1.0 (max), multiplier is 0.5
        // At rate 0.0 (min), multiplier is 2.0
        let rateMultiplier = 1.0 / Double(max(speechRate, 0.1)) * 0.5

        for phoneme in phonemes {
            let viseme = mapPhonemeToViseme(phoneme)
            let duration = estimateDuration(for: phoneme) * rateMultiplier

            let timedViseme = TimedViseme(
                viseme: viseme,
                startTime: currentTime,
                duration: duration
            )
            timeline.append(timedViseme)
            currentTime += duration
        }

        return timeline
    }

    /// Map a single phoneme to a viseme
    /// - Parameter phoneme: ARPABET phoneme string
    /// - Returns: Corresponding VRM viseme
    public func mapPhonemeToViseme(_ phoneme: String) -> VRMViseme {
        // Handle silence marker
        if phoneme == TextToPhonemeMapper.silenceMarker {
            return .neutral
        }

        // Strip stress markers (0, 1, 2) from vowels
        let normalized = phoneme.filter { !$0.isNumber }

        return Self.visemeMap[normalized] ?? .neutral
    }

    /// Estimate duration for a phoneme
    /// - Parameter phoneme: ARPABET phoneme string
    /// - Returns: Duration in seconds at default speech rate
    public func estimateDuration(for phoneme: String) -> Double {
        // Handle silence marker
        if phoneme == TextToPhonemeMapper.silenceMarker {
            return Self.baseDurations[.silence] ?? 0.100
        }

        // Strip stress markers
        let normalized = phoneme.filter { !$0.isNumber }

        // Look up phoneme type
        let phonemeType = Self.phonemeTypes[normalized] ?? .fricative

        return Self.baseDurations[phonemeType] ?? 0.060
    }

    /// Get the phoneme type for a phoneme
    /// - Parameter phoneme: ARPABET phoneme string
    /// - Returns: PhonemeType category
    public func phonemeType(for phoneme: String) -> PhonemeType {
        if phoneme == TextToPhonemeMapper.silenceMarker {
            return .silence
        }

        let normalized = phoneme.filter { !$0.isNumber }
        return Self.phonemeTypes[normalized] ?? .fricative
    }
}

// MARK: - Coarticulation Helper

/// Helper for smooth viseme transitions (coarticulation)
public struct CoarticulationBlender: Sendable {

    /// Blend smoothly between two visemes
    /// - Parameters:
    ///   - from: Starting viseme
    ///   - to: Target viseme
    ///   - progress: Blend progress (0.0 = from, 1.0 = to)
    /// - Returns: Tuple of (primary viseme, blend weight for primary, secondary viseme, blend weight for secondary)
    public static func blend(
        from: VRMViseme,
        to: VRMViseme,
        progress: Double
    ) -> (primary: VRMViseme, primaryWeight: Float, secondary: VRMViseme?, secondaryWeight: Float) {
        // Use smooth step for more natural transitions
        let t = smoothStep(Float(progress))

        if t < 0.5 {
            // First half: primary is "from", blending toward "to"
            let weight = 1.0 - (t * 2.0)  // 1.0 → 0.0
            return (from, weight, to, 1.0 - weight)
        } else {
            // Second half: primary is "to", coming from "from"
            let weight = (t - 0.5) * 2.0  // 0.0 → 1.0
            return (to, weight, from, 1.0 - weight)
        }
    }

    /// Smooth step interpolation (ease in-out)
    private static func smoothStep(_ t: Float) -> Float {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }
}
