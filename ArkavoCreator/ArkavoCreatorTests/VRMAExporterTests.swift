//
//  VRMAExporterTests.swift
//  ArkavoCreatorTests
//
//  Tests for VRMAExporter to verify GLB file generation,
//  quaternion serialization order, and timestamp normalization.
//

@testable import ArkavoCreator
import Foundation
import simd
import VRMMetalKit
import XCTest

final class VRMAExporterTests: XCTestCase {

    // MARK: - Quaternion Serialization Order

    func testQuaternionSerializationOrder() throws {
        // Create a session with a known quaternion: 90 degrees around Y axis
        // This gives us: x=0, y=sin(45)~0.707, z=0, w=cos(45)~0.707
        let angle = Float.pi / 2  // 90 degrees
        let yAxisRotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))

        // Create frame with this rotation for hips bone
        let frame = VRMAFrame(
            time: 0.0,
            faceBlendShapes: nil,
            headTransform: nil,
            bodyJoints: [.hips: yAxisRotation],
            hipsTranslation: SIMD3<Float>(0, 0, 0)
        )

        let session = VRMASession(
            name: "test",
            duration: 0.0,
            frameRate: 30,
            frames: [frame]
        )

        // Export to GLB
        let glbData = try VRMAExporter.export(session: session)

        // Parse GLB to extract binary chunk
        // GLB structure: 12-byte header, then JSON chunk (8-byte header + data), then BIN chunk
        XCTAssertGreaterThanOrEqual(glbData.count, 12, "GLB too small")

        // Read header
        let magic = glbData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(magic, 0x46546C67, "GLB magic should be 'glTF'")

        // Skip to JSON chunk header (12 bytes into file)
        let jsonChunkLength = glbData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }

        // Binary chunk starts after JSON chunk (12 + 8 + jsonChunkLength)
        let binChunkOffset = 12 + 8 + Int(jsonChunkLength)

        // Ensure padding is accounted for (JSON padded to 4 bytes)
        XCTAssertGreaterThan(glbData.count, binChunkOffset + 8, "GLB doesn't have binary chunk")

        let binChunkType = glbData.subdata(in: (binChunkOffset + 4)..<(binChunkOffset + 8)).withUnsafeBytes { $0.load(as: UInt32.self) }

        XCTAssertEqual(binChunkType, 0x004E4942, "Binary chunk type should be 'BIN\\0'")

        // Binary data starts at binChunkOffset + 8
        let binDataStart = binChunkOffset + 8

        // Layout: [time (1 float)] [rotation (4 floats)] [translation (3 floats)]
        // Time accessor: 1 frame * 4 bytes = 4 bytes (offset 0)
        // Rotation accessor: 1 frame * 16 bytes = 16 bytes (offset 4)
        // Translation accessor: 1 frame * 12 bytes = 12 bytes (offset 20)

        let rotationOffset = binDataStart + 4  // After time value

        // Read the 4 floats of the quaternion
        let x = glbData.subdata(in: rotationOffset..<(rotationOffset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        let y = glbData.subdata(in: (rotationOffset + 4)..<(rotationOffset + 8)).withUnsafeBytes { $0.load(as: Float.self) }
        let z = glbData.subdata(in: (rotationOffset + 8)..<(rotationOffset + 12)).withUnsafeBytes { $0.load(as: Float.self) }
        let w = glbData.subdata(in: (rotationOffset + 12)..<(rotationOffset + 16)).withUnsafeBytes { $0.load(as: Float.self) }

        // Expected values for 90-degree Y rotation
        let expectedX: Float = 0.0
        let expectedY: Float = sin(Float.pi / 4)  // ~0.707
        let expectedZ: Float = 0.0
        let expectedW: Float = cos(Float.pi / 4)  // ~0.707

        // Verify glTF order: x, y, z, w
        XCTAssertEqual(x, expectedX, accuracy: 0.001, "x component should be 0")
        XCTAssertEqual(y, expectedY, accuracy: 0.001, "y component should be ~0.707")
        XCTAssertEqual(z, expectedZ, accuracy: 0.001, "z component should be 0")
        XCTAssertEqual(w, expectedW, accuracy: 0.001, "w component should be ~0.707")
    }

    // MARK: - Timestamp Normalization

    func testTimestampNormalization() throws {
        // Create session with frames starting at t=1.5, not t=0
        let frames = [
            VRMAFrame(time: 1.5, bodyJoints: [.hips: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)], hipsTranslation: .zero),
            VRMAFrame(time: 2.0, bodyJoints: [.hips: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)], hipsTranslation: .zero),
            VRMAFrame(time: 2.5, bodyJoints: [.hips: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)], hipsTranslation: .zero)
        ]

        let session = VRMASession(
            name: "test",
            duration: 2.5,
            frameRate: 30,
            frames: frames
        )

        let glbData = try VRMAExporter.export(session: session)

        // Parse GLB to extract time values from binary chunk
        XCTAssertGreaterThanOrEqual(glbData.count, 12, "GLB too small")

        let jsonChunkLength = glbData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let binChunkOffset = 12 + 8 + Int(jsonChunkLength)
        let binDataStart = binChunkOffset + 8

        // Read time values (3 frames * 4 bytes each)
        let time0 = glbData.subdata(in: binDataStart..<(binDataStart + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        let time1 = glbData.subdata(in: (binDataStart + 4)..<(binDataStart + 8)).withUnsafeBytes { $0.load(as: Float.self) }
        let time2 = glbData.subdata(in: (binDataStart + 8)..<(binDataStart + 12)).withUnsafeBytes { $0.load(as: Float.self) }

        // Verify timestamps are normalized (start at 0, not 1.5)
        XCTAssertEqual(time0, 0.0, accuracy: 0.001, "First frame time should be 0.0, got \(time0)")
        XCTAssertEqual(time1, 0.5, accuracy: 0.001, "Second frame time should be 0.5, got \(time1)")
        XCTAssertEqual(time2, 1.0, accuracy: 0.001, "Third frame time should be 1.0, got \(time2)")
    }

    // MARK: - GLB Structure

    func testGLBFileStructure() throws {
        let frame = VRMAFrame(
            time: 0.0,
            bodyJoints: [.hips: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)],
            hipsTranslation: .zero
        )

        let session = VRMASession(
            name: "test",
            duration: 0.0,
            frameRate: 30,
            frames: [frame]
        )

        let glbData = try VRMAExporter.export(session: session)

        // Verify minimum size (header + chunks)
        XCTAssertGreaterThanOrEqual(glbData.count, 28, "GLB should be at least 28 bytes")

        // Verify magic number
        let magic = glbData.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(magic, 0x46546C67, "Magic should be 'glTF' (0x46546C67)")

        // Verify version
        let version = glbData.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(version, 2, "Version should be 2")

        // Verify total length matches actual data
        let totalLength = glbData.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(Int(totalLength), glbData.count, "Header length should match actual data length")

        // Verify JSON chunk type
        let jsonChunkType = glbData.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }
        XCTAssertEqual(jsonChunkType, 0x4E4F534A, "First chunk type should be 'JSON' (0x4E4F534A)")
    }

    // MARK: - VRMC Extension

    func testVRMCExtension() throws {
        let frame = VRMAFrame(
            time: 0.0,
            bodyJoints: [.hips: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)],
            hipsTranslation: .zero
        )

        let session = VRMASession(
            name: "test",
            duration: 0.0,
            frameRate: 30,
            frames: [frame]
        )

        let glbData = try VRMAExporter.export(session: session)

        // Extract JSON chunk
        let jsonChunkLength = glbData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let jsonData = glbData.subdata(in: 20..<(20 + Int(jsonChunkLength)))

        // Parse JSON
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }

        // Verify extensionsUsed
        guard let extensionsUsed = json["extensionsUsed"] as? [String] else {
            XCTFail("extensionsUsed not found")
            return
        }
        XCTAssertTrue(extensionsUsed.contains("VRMC_vrm_animation"), "extensionsUsed should contain VRMC_vrm_animation")

        // Verify extension data exists
        guard let extensions = json["extensions"] as? [String: Any],
              let vrmaExt = extensions["VRMC_vrm_animation"] as? [String: Any] else {
            XCTFail("VRMC_vrm_animation extension not found")
            return
        }

        // Verify specVersion
        XCTAssertEqual(vrmaExt["specVersion"] as? String, "1.0", "specVersion should be 1.0")

        // Verify humanoid section exists
        XCTAssertNotNil(vrmaExt["humanoid"], "humanoid section should exist")
    }

    // MARK: - Empty Session

    func testEmptySessionThrows() throws {
        let session = VRMASession(
            name: "empty",
            duration: 0.0,
            frameRate: 30,
            frames: []
        )

        XCTAssertThrowsError(try VRMAExporter.export(session: session)) { error in
            XCTAssertTrue(error is VRMAExportError)
        }
    }

    // MARK: - Multiple Bones

    func testMultipleBones() throws {
        let identityQuat = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

        let frame = VRMAFrame(
            time: 0.0,
            bodyJoints: [
                .hips: identityQuat,
                .spine: identityQuat,
                .chest: identityQuat,
                .head: identityQuat,
                .leftUpperArm: identityQuat,
                .rightUpperArm: identityQuat
            ],
            hipsTranslation: .zero
        )

        let session = VRMASession(
            name: "test",
            duration: 0.0,
            frameRate: 30,
            frames: [frame]
        )

        let glbData = try VRMAExporter.export(session: session)

        // Extract and parse JSON
        let jsonChunkLength = glbData.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self) }
        let jsonData = glbData.subdata(in: 20..<(20 + Int(jsonChunkLength)))
        guard let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            XCTFail("Failed to parse JSON")
            return
        }

        // Verify all bones are in the extension
        guard let extensions = json["extensions"] as? [String: Any],
              let vrmaExt = extensions["VRMC_vrm_animation"] as? [String: Any],
              let humanoid = vrmaExt["humanoid"] as? [String: Any],
              let humanBones = humanoid["humanBones"] as? [String: Any] else {
            XCTFail("Failed to extract humanBones")
            return
        }

        XCTAssertNotNil(humanBones["hips"], "hips should be in humanBones")
        XCTAssertNotNil(humanBones["spine"], "spine should be in humanBones")
        XCTAssertNotNil(humanBones["chest"], "chest should be in humanBones")
        XCTAssertNotNil(humanBones["head"], "head should be in humanBones")
        XCTAssertNotNil(humanBones["leftUpperArm"], "leftUpperArm should be in humanBones")
        XCTAssertNotNil(humanBones["rightUpperArm"], "rightUpperArm should be in humanBones")
    }
}
