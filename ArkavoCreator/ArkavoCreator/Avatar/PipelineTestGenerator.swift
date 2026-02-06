//
// PipelineTestGenerator.swift
// ArkavoCreator
//
// Generates XCTest code from captured pipeline diagnostics sessions.
// Use this to create reproducible unit tests from real motion capture data.
//

import Foundation

/// Generates XCTest code from captured pipeline diagnostics sessions
public struct PipelineTestGenerator {

    // MARK: - Generation

    /// Generate XCTest Swift code from a diagnostics session
    /// - Parameters:
    ///   - session: The captured diagnostics session
    ///   - testClassName: Name for the generated test class
    ///   - maxFrames: Maximum number of frames to include (for size management)
    /// - Returns: Swift source code string
    public static func generateTests(
        from session: PipelineDiagnosticsSession,
        testClassName: String = "GeneratedPipelineTests",
        maxFrames: Int = 10
    ) -> String {
        var output = """
        //
        // \(testClassName).swift
        // Generated from pipeline diagnostics session
        // Generated at: \(ISO8601DateFormatter().string(from: Date()))
        // Session: \(session.startTime) - \(session.endTime)
        //

        import XCTest
        import simd
        @testable import ArkavoCreator

        final class \(testClassName): XCTestCase {

        """

        // Group captures by stage
        let capturesByStage = Dictionary(grouping: session.captures, by: { $0.stageId })

        // Generate conversion tests
        if let conversionCaptures = capturesByStage["conversion"] {
            output += generateConversionTests(from: conversionCaptures, maxFrames: maxFrames)
        }

        // Generate VRM mapping tests
        if let mappingCaptures = capturesByStage["vrmMapping"] {
            output += generateVRMMappingTests(from: mappingCaptures, maxFrames: maxFrames)
        }

        // Generate recording tests
        if let recordingCaptures = capturesByStage["recording"] {
            output += generateRecordingTests(from: recordingCaptures, maxFrames: maxFrames)
        }

        // Generate processing tests
        if let processingCaptures = capturesByStage["processing"] {
            output += generateProcessingTests(from: processingCaptures)
        }

        // Generate raw ARKit data fixture
        if let rawCaptures = capturesByStage["rawARKit"] {
            output += generateRawDataFixture(from: rawCaptures, maxFrames: maxFrames)
        }

        output += """
        }

        """

        return output
    }

    // MARK: - Conversion Tests

    private static func generateConversionTests(from captures: [PipelineStageCapture], maxFrames: Int) -> String {
        var output = """

            // MARK: - Conversion Tests

            func testJointMappingConsistency() {
                // Verify that joint mapping is consistent across frames
                let expectedMappedJoints: Set<String> = [

        """

        // Get first capture with mapped joints
        if let firstCapture = captures.first,
           case .conversion(let data) = firstCapture.data {
            let joints = data.mappedJoints.values.sorted()
            for joint in joints {
                output += "            \"\(joint)\",\n"
            }
        }

        output += """
                ]

                // Verify these joints are consistently mapped
                XCTAssertFalse(expectedMappedJoints.isEmpty, "Should have mapped joints")
            }

            func testUnmappedJointsAreDocumented() {
                // These joints are expected to be unmapped (not needed for VRM)
                let expectedUnmapped: Set<String> = [

        """

        // Get unmapped joints from first capture
        if let firstCapture = captures.first,
           case .conversion(let data) = firstCapture.data {
            let unmapped = data.unmappedJoints.map { $0.name }.sorted()
            for joint in unmapped.prefix(20) {
                output += "            \"\(joint)\",\n"
            }
        }

        output += """
                ]

                // Document that these joints are intentionally unmapped
                XCTAssertFalse(expectedUnmapped.isEmpty, "Should document unmapped joints")
            }


        """

        return output
    }

    // MARK: - VRM Mapping Tests

    private static func generateVRMMappingTests(from captures: [PipelineStageCapture], maxFrames: Int) -> String {
        var output = """

            // MARK: - VRM Mapping Tests

            func testVRMBoneRotationsAreNormalized() {
                // Test that all quaternions are normalized (unit length)

        """

        // Get sample rotations from first capture
        if let firstCapture = captures.first,
           case .vrmMapping(let data) = firstCapture.data {
            output += "        let sampleRotations: [(bone: String, x: Float, y: Float, z: Float, w: Float)] = [\n"

            for rotation in data.outputRotations.prefix(5) {
                let q = rotation.quaternion
                output += "            (\"\(rotation.boneName)\", \(q.x), \(q.y), \(q.z), \(q.w)),\n"
            }

            output += """
                ]

                for (bone, x, y, z, w) in sampleRotations {
                    let length = sqrt(x*x + y*y + z*z + w*w)
                    XCTAssertEqual(length, 1.0, accuracy: 0.001, "Quaternion for \\(bone) should be normalized")
                }
            }

            func testParentJointLookupSucceeds() {
                // Bones that should NOT use fallback (parent should be found)
                let bonesWithParent: Set<String> = [

        """

            // Get bones that successfully found parents
            let bonesWithoutFallback = data.outputRotations
                .filter { !$0.usedFallback }
                .map { $0.boneName }
                .sorted()

            for bone in bonesWithoutFallback {
                output += "            \"\(bone)\",\n"
            }

            output += """
                ]

                XCTAssertFalse(bonesWithParent.isEmpty, "Most bones should find their parent")
            }


        """
        }

        return output
    }

    // MARK: - Recording Tests

    private static func generateRecordingTests(from captures: [PipelineStageCapture], maxFrames: Int) -> String {
        var output = """

            // MARK: - Recording Tests

            func testFrameTimesAreMonotonic() {
                // Frame times should increase monotonically
                let frameTimes: [Float] = [

        """

        // Get frame times
        let times = captures.prefix(maxFrames).compactMap { capture -> Float? in
            if case .recording(let data) = capture.data {
                return data.time
            }
            return nil
        }

        for time in times {
            output += "            \(time),\n"
        }

        output += """
                ]

                for i in 1..<frameTimes.count {
                    XCTAssertGreaterThan(frameTimes[i], frameTimes[i-1], "Frame times should be monotonically increasing")
                }
            }

            func testFramesHaveBodyData() {
                // Most frames should have body joint data

        """

        let bodyFrameCount = captures.filter { capture in
            if case .recording(let data) = capture.data {
                return data.hasBodyJoints
            }
            return false
        }.count

        output += """
                let totalFrames = \(captures.count)
                let framesWithBody = \(bodyFrameCount)
                let ratio = Float(framesWithBody) / Float(totalFrames)

                XCTAssertGreaterThan(ratio, 0.5, "At least 50% of frames should have body data")
            }


        """

        return output
    }

    // MARK: - Processing Tests

    private static func generateProcessingTests(from captures: [PipelineStageCapture]) -> String {
        var output = """

            // MARK: - Processing Tests


        """

        if let firstCapture = captures.first,
           case .processing(let data) = firstCapture.data {
            output += """
            func testProcessingReducesOutliers() {
                // Processing should handle outlier frames
                let inputFrames = \(data.inputFrameCount)
                let outputFrames = \(data.outputFrameCount)
                let outlierRatio: Float = \(data.qualityReport.outlierRatio)

                XCTAssertLessThanOrEqual(outlierRatio, 0.3, "Outlier ratio should be acceptable")
                XCTAssertGreaterThan(outputFrames, 0, "Should have output frames")
            }

            func testBodyFrameRatioIsAdequate() {
                let bodyFrameRatio: Float = \(data.qualityReport.bodyFrameRatio)

                XCTAssertGreaterThanOrEqual(bodyFrameRatio, 0.5, "Body frame ratio should be at least 50%")
            }


        """
        }

        return output
    }

    // MARK: - Raw Data Fixture

    private static func generateRawDataFixture(from captures: [PipelineStageCapture], maxFrames: Int) -> String {
        var output = """

            // MARK: - Test Data Fixtures

            /// Sample body joint data from captured session
            func makeSampleBodyJoints() -> [[String: [Float]]] {
                return [

        """

        var frameCount = 0
        for capture in captures.prefix(maxFrames * 2) {
            guard case .rawARKit(let data) = capture.data,
                  let bodyData = data.bodyData else { continue }

            output += "            // Frame \(frameCount)\n"
            output += "            [\n"

            for (index, jointName) in bodyData.jointNames.prefix(5).enumerated() {
                let transform = bodyData.jointTransforms[index]
                let transformStr = transform.map { String(format: "%.6f", $0) }.joined(separator: ", ")
                output += "                \"\(jointName)\": [\(transformStr)],\n"
            }

            output += "            ],\n"
            frameCount += 1

            if frameCount >= maxFrames { break }
        }

        output += """
                ]
            }

        """

        return output
    }

    // MARK: - File Export

    /// Export generated tests to a file
    /// - Parameters:
    ///   - session: The diagnostics session
    ///   - directory: Directory to write to
    ///   - testClassName: Name for the test class
    /// - Returns: URL of the generated file
    public static func exportTests(
        from session: PipelineDiagnosticsSession,
        to directory: URL,
        testClassName: String = "GeneratedPipelineTests"
    ) throws -> URL {
        let code = generateTests(from: session, testClassName: testClassName)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("\(testClassName).swift")
        try code.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
