//
//  LipSyncCoordinator.swift
//  AvatarMuse
//
//  Copyright 2025 Arkavo
//

import Foundation
import OSLog
import QuartzCore
import VRMMetalKit

// MARK: - Lip Sync Coordinator

/// Orchestrates the text-based lip sync pipeline
/// Converts text to phonemes, maps to visemes, and schedules playback
@MainActor
public final class LipSyncCoordinator {

    // MARK: - Components

    private let textToPhonemeMapper = TextToPhonemeMapper()
    private let phonemeToVisemeMapper = PhonemeToVisemeMapper()
    private let japaneseMapper = JapanesePhonemeMapper()
    public let scheduler = VisemeScheduler()

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.arkavo.avatarmuse", category: "LipSync")

    /// Current speech rate (matches AVSpeechUtterance rate)
    public var speechRate: Float = 0.48 {
        didSet {
            logger.debug("Speech rate updated to: \(self.speechRate)")
        }
    }

    /// Enable/disable lip sync
    public var isEnabled: Bool = true

    /// Debug mode - logs phoneme and viseme sequences
    public var debugMode: Bool = false

    // MARK: - Callbacks

    /// Called when a viseme changes (for debugging/UI)
    public var onVisemeChange: ((VRMViseme, Float) -> Void)? {
        get { scheduler.onVisemeChange }
        set { scheduler.onVisemeChange = newValue }
    }

    /// Called when playback completes
    public var onPlaybackComplete: (() -> Void)? {
        get { scheduler.onPlaybackComplete }
        set { scheduler.onPlaybackComplete = newValue }
    }

    // MARK: - Initialization

    public init() {
        logger.info("LipSyncCoordinator initialized")
    }

    // MARK: - Public API

    /// Prepare lip sync for text (call before TTS starts)
    /// - Parameter text: The text that will be spoken
    /// - Returns: Estimated duration of the viseme timeline
    @discardableResult
    public func prepare(text: String) -> Double {
        guard isEnabled else {
            logger.debug("Lip sync disabled, skipping preparation")
            return 0
        }
        


        // Detect language and create appropriate timeline
        let timeline: VisemeTimeline
        let isJapanese = containsJapanese(text)

        if isJapanese {
            // Japanese: use mora-based mapper
            timeline = japaneseMapper.createTimeline(text: text, speechRate: speechRate)

            if debugMode {
                let phonemes = japaneseMapper.convert(text)
                logger.debug("Japanese phonemes: \(phonemes.joined(separator: " "))")
            }
        } else {
            // English: use ARPABET-based mapper
            let phonemes = textToPhonemeMapper.convert(text)

            if debugMode {
                logger.debug("Phonemes: \(phonemes.joined(separator: " "))")
            }

            timeline = phonemeToVisemeMapper.createTimeline(
                phonemes: phonemes,
                speechRate: speechRate
            )
        }

        if debugMode {
            let visemeSequence = timeline.visemes
                .map { "\($0.viseme.rawValue)@\(String(format: "%.2f", $0.startTime))" }
                .joined(separator: " ")
            logger.debug("Viseme timeline: \(visemeSequence)")
            logger.debug("Timeline duration: \(timeline.duration)s")
        }

        // Prepare scheduler
        scheduler.prepare(timeline: timeline)

        let lang = isJapanese ? "JP" : "EN"
        logger.info("Prepared lip sync [\(lang)] for \(text.prefix(30))... (\(timeline.count) visemes, \(String(format: "%.2f", timeline.duration))s)")

        return timeline.duration
    }

    /// Detect if text contains Japanese characters
    private func containsJapanese(_ text: String) -> Bool {
        for char in text.unicodeScalars {
            // Hiragana: U+3040 - U+309F
            // Katakana: U+30A0 - U+30FF
            // CJK Unified Ideographs: U+4E00 - U+9FFF
            let value = char.value
            if (0x3040...0x309F).contains(value) ||  // Hiragana
               (0x30A0...0x30FF).contains(value) ||  // Katakana
               (0x4E00...0x9FFF).contains(value) {   // Kanji
                return true
            }
        }
        return false
    }

    /// Start lip sync playback (call when TTS audio starts)
    public func startSync() {
        guard isEnabled else { return }
        scheduler.start(audioStartTime: CACurrentMediaTime())
        logger.debug("Started lip sync playback")
    }

    /// Start lip sync playback with a specific audio start time
    /// - Parameter audioStartTime: CACurrentMediaTime when audio started
    public func startSync(audioStartTime: Double) {
        guard isEnabled else { return }
        scheduler.start(audioStartTime: audioStartTime)
        logger.debug("Started lip sync at audio time: \(audioStartTime)")
    }

    /// Pause lip sync playback
    public func pause() {
        scheduler.pause()
    }

    /// Resume lip sync playback
    public func resume() {
        scheduler.resume()
    }

    /// Stop and reset lip sync
    public func stop() {
        scheduler.stop()
        logger.debug("Stopped lip sync")
    }

    /// Hard reset for interruption protocol - immediately snaps all visemes to neutral
    /// Bypasses smoothing for instant mouth closure during barge-in
    public func hardReset() {
        scheduler.forceStop()
        logger.debug("Hard reset lip sync - visemes snapped to neutral")
    }

    /// Update lip sync state (call every frame)
    /// - Parameter deltaTime: Time since last frame
    public func update(deltaTime: Float) {
        scheduler.update(deltaTime: deltaTime)
    }

    // MARK: - Expression Layer Integration

    /// Apply current viseme to expression layer
    /// - Parameter expressionLayer: The VRM expression layer
    public func applyToExpressionLayer(_ expressionLayer: ExpressionLayer) {
        guard isEnabled else { return }
        scheduler.applyToExpressionLayer(expressionLayer)
    }

    /// Get current morph weights for direct application
    /// - Returns: Dictionary of morph names to weights
    public func getMorphWeights() -> [String: Float] {
        guard isEnabled else { return [:] }
        return scheduler.getMorphWeights()
    }

    // MARK: - Status

    /// Current scheduler state
    public var state: VisemeSchedulerState {
        scheduler.state
    }

    /// Current viseme being displayed
    public var currentViseme: VRMViseme {
        scheduler.currentViseme
    }

    /// Current viseme intensity
    public var currentIntensity: Float {
        scheduler.currentIntensity
    }

    /// Playback progress (0-1)
    public var progress: Double {
        scheduler.progress
    }

    /// Whether lip sync is currently playing
    public var isPlaying: Bool {
        scheduler.state == .playing
    }
}

// MARK: - Convenience Extensions

extension LipSyncCoordinator {

    /// Prepare and immediately start lip sync
    /// - Parameter text: The text being spoken
    /// - Returns: Estimated duration
    @discardableResult
    public func prepareAndStart(text: String) -> Double {
        let duration = prepare(text: text)
        startSync()
        return duration
    }

    /// Get phonemes for text (for debugging/testing)
    /// - Parameter text: Input text
    /// - Returns: Array of ARPABET phoneme strings
    public func getPhonemes(for text: String) -> [String] {
        textToPhonemeMapper.convert(text)
    }

    /// Get viseme timeline for text (for debugging/testing)
    /// - Parameters:
    ///   - text: Input text
    ///   - speechRate: Speech rate (default uses coordinator's rate)
    /// - Returns: VisemeTimeline
    public func getTimeline(for text: String, speechRate: Float? = nil) -> VisemeTimeline {
        let rate = speechRate ?? self.speechRate

        if containsJapanese(text) {
            return japaneseMapper.createTimeline(text: text, speechRate: rate)
        } else {
            let phonemes = textToPhonemeMapper.convert(text)
            return phonemeToVisemeMapper.createTimeline(
                phonemes: phonemes,
                speechRate: rate
            )
        }
    }
}
