//
//  LipSyncController.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import AVFoundation
import Foundation

/// Captures microphone audio and converts to lip sync blend shape weights
@MainActor
class LipSyncController: ObservableObject {
    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var currentMouthWeight: Float = 0.0

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var lastUpdateTime = Date()
    private let updateInterval: TimeInterval = 1.0 / 60.0 // 60 FPS

    // MARK: - Audio Setup

    func startCapture() throws {
        guard !isRecording else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let bus = 0

        let format = input.inputFormat(forBus: bus)

        // Install tap to analyze audio amplitude
        input.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            processAudioBuffer(buffer)
        }

        audioEngine = engine
        inputNode = input

        try engine.start()
        isRecording = true
    }

    nonisolated func stopCapture() {
        Task { @MainActor in
            guard isRecording else { return }

            inputNode?.removeTap(onBus: 0)
            audioEngine?.stop()

            audioEngine = nil
            inputNode = nil
            isRecording = false
            currentMouthWeight = 0.0
        }
    }

    // MARK: - Audio Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(
            from: 0,
            to: Int(buffer.frameLength),
            by: buffer.stride,
        ).map { channelDataValue[$0] }

        // Calculate RMS (root mean square) amplitude
        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))

        // Convert to decibels and normalize
        let decibels = 20 * log10(max(rms, 0.00001))
        let normalized = min(max((decibels + 50) / 50, 0), 1) // -50dB to 0dB range

        // Apply smoothing and update weight
        let smoothingFactor: Float = 0.3
        let smoothedWeight = (smoothingFactor * normalized) + ((1 - smoothingFactor) * currentMouthWeight)

        // Throttle updates to avoid excessive UI refreshes
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= updateInterval else { return }
        lastUpdateTime = now

        Task { @MainActor in
            self.currentMouthWeight = smoothedWeight
        }
    }

    // MARK: - Cleanup

    deinit {
        stopCapture()
    }
}
