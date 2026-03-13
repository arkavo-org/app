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

import AVFoundation
import Foundation

/// Extracts and smooths RMS amplitude from audio buffers during TTS playback.
/// Used by SpeakingDynamicsLayer for audio-driven gesticulation.
@MainActor
public final class AudioAnalyzer {

    // MARK: - State

    /// Current smoothed RMS amplitude (0-1)
    public private(set) var currentRMS: Float = 0

    /// Peak RMS for normalization (adapts over time)
    private var peakRMS: Float = 0.3

    /// Smoothing factor (higher = more responsive, 0-1)
    public var smoothing: Float = 0.3

    /// Whether analysis is currently active
    public private(set) var isAnalyzing: Bool = false

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Start analysis session (call when TTS begins)
    public func start() {
        isAnalyzing = true
        // Reset to neutral values
        currentRMS = 0
        peakRMS = 0.3
    }

    /// Stop analysis session (call when TTS ends)
    public func stop() {
        isAnalyzing = false
        currentRMS = 0
    }

    /// Update from audio buffer (called during TTS playback)
    /// - Parameter buffer: The audio buffer being played
    public func analyze(buffer: AVAudioPCMBuffer) {
        guard isAnalyzing else { return }

        let rms = calculateRMS(buffer)
        processRMS(rms)
    }

    /// Update from pre-computed RMS value (used by segmented playback)
    /// - Parameter rms: Pre-computed RMS amplitude
    public func analyze(rms: Float) {
        guard isAnalyzing else { return }
        processRMS(rms)
    }

    /// Process RMS value with normalization and smoothing
    private func processRMS(_ rms: Float) {
        // Update peak for normalization (slow decay)
        if rms > peakRMS {
            peakRMS = rms
        } else {
            peakRMS += (0.3 - peakRMS) * 0.01  // Decay toward baseline
        }

        // Normalize to 0-1 range
        let normalizedRMS = min(rms / max(peakRMS, 0.1), 1.0)

        // Apply low-pass filter for smooth transitions
        currentRMS += (normalizedRMS - currentRMS) * smoothing
    }

    // MARK: - Private Methods

    /// Calculate RMS (Root Mean Square) of audio buffer
    private func calculateRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        // Use first channel
        let samples = channelData[0]

        // Calculate sum of squares
        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let sample = samples[i]
            sumOfSquares += sample * sample
        }

        // Return RMS
        return sqrt(sumOfSquares / Float(frameLength))
    }
}
