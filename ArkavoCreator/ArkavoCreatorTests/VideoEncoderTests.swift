//
//  VideoEncoderTests.swift
//  ArkavoCreatorTests
//
//  Tests for VideoEncoder to ensure recordings are properly closed and valid
//

import AVFoundation
@testable import ArkavoCreator
import ArkavoKit
import XCTest

final class VideoEncoderTests: XCTestCase {
    var tempDirectory: URL!

    override func setUpWithError() throws {
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoEncoderTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temp files
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Video Validation Helper

    /// Validates that a video file has a proper moov atom and is playable
    func validateVideoFile(at url: URL) throws -> (isValid: Bool, duration: Double?, tracks: Int) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return (false, nil, 0)
        }

        let asset = AVAsset(url: url)

        // Check if the asset can load its duration (indicates moov atom is present)
        let semaphore = DispatchSemaphore(value: 0)
        var loadedDuration: CMTime?
        var loadedTracks: [AVAssetTrack] = []
        var loadError: Error?

        Task {
            do {
                loadedDuration = try await asset.load(.duration)
                loadedTracks = try await asset.load(.tracks)
            } catch {
                loadError = error
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10)

        if let error = loadError {
            print("Failed to load asset: \(error)")
            return (false, nil, 0)
        }

        guard let duration = loadedDuration else {
            return (false, nil, 0)
        }

        let isValid = duration.isValid && duration.seconds > 0
        return (isValid, duration.seconds, loadedTracks.count)
    }

    // MARK: - Tests

    /// Tests that the encoder can start and stop audio-only recording
    /// Note: Without actual audio samples, the encoder cancels the empty file (expected behavior)
    @MainActor
    func testAudioOnlyRecordingLifecycle() async throws {
        let encoder = VideoEncoder()
        let outputURL = tempDirectory.appendingPathComponent("test_audio_only.m4a")

        // Start audio-only recording
        try await encoder.startRecording(
            to: outputURL,
            title: "Test Audio",
            audioSourceIDs: ["microphone"],
            videoEnabled: false
        )

        let isRec = await encoder.isRecording
        XCTAssertTrue(isRec, "Should be recording after startRecording")

        // Recording without actual audio samples - encoder will cancel writing
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Stop recording - this returns a URL even if the file was cancelled/empty
        // The encoder handles this gracefully by cancelling the asset writer
        let resultURL = try await encoder.finishRecording()

        let isRecAfter = await encoder.isRecording
        XCTAssertFalse(isRecAfter, "Should not be recording after finishRecording")

        // The returned URL is valid (path we provided)
        XCTAssertEqual(resultURL.path, outputURL.path, "Should return the expected output path")
    }

    func testValidateCorruptedVideoDetection() throws {
        // Create a fake "corrupted" video file (just random data)
        let corruptURL = tempDirectory.appendingPathComponent("corrupt.mov")
        let randomData = Data((0 ..< 1000).map { _ in UInt8.random(in: 0 ... 255) })
        try randomData.write(to: corruptURL)

        let result = try validateVideoFile(at: corruptURL)

        XCTAssertFalse(result.isValid, "Corrupt file should not be valid")
        XCTAssertNil(result.duration, "Corrupt file should not have duration")
    }

    func testValidateProperVideoFile() throws {
        // This test requires an actual recording session which needs permissions
        // Skip in CI environment
        #if DEBUG
            // Look for any existing recording in the container
            let containerPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/com.arkavo.ArkavoCreator/Data/Documents/Recordings")

            if FileManager.default.fileExists(atPath: containerPath.path),
               let files = try? FileManager.default.contentsOfDirectory(at: containerPath, includingPropertiesForKeys: nil),
               let firstMov = files.first(where: { $0.pathExtension == "mov" })
            {
                let result = try validateVideoFile(at: firstMov)
                print("Validated existing recording: \(firstMov.lastPathComponent)")
                print("  Valid: \(result.isValid)")
                print("  Duration: \(result.duration ?? 0) seconds")
                print("  Tracks: \(result.tracks)")

                // If there are existing recordings, verify at least one is valid
                // This is informational - actual recordings should be valid
                if !result.isValid {
                    XCTFail("Existing recording \(firstMov.lastPathComponent) is corrupted!")
                }
            }
        #endif
    }
}

// MARK: - Integration Tests for Recording Flow

final class RecordingFlowTests: XCTestCase {
    /// Tests that a complete recording cycle produces a valid file
    @MainActor
    func testCompleteRecordingCycleProducesValidFile() async throws {
        // This test would require mocking or actual hardware access
        // For now, we document what should be tested

        // 1. Create RecordViewModel
        // 2. Configure for audio-only mode (no camera/screen permissions needed)
        // 3. Start recording
        // 4. Wait 2+ seconds
        // 5. Stop recording
        // 6. Verify file exists and is valid using AVAsset

        // The UI tests cover this flow, but we should add unit test validation
    }
}
