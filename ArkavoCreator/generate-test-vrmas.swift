#!/usr/bin/env swift
//
// generate-test-vrmas.swift
//
// Standalone script to generate test VRMA files for VRMMetalKit validation.
// Run: swift generate-test-vrmas.swift
//
// This creates .vrma files with known poses that VRMMetalKit can use to
// verify animation loading and playback.

import Foundation
import simd

// MARK: - Minimal VRMA Types for File Generation

struct TestVRMAFrame {
    let time: Float
    let boneRotations: [String: simd_quatf]  // bone name -> rotation
    let hipsTranslation: simd_float3?
}

struct TestVRMASession {
    let name: String
    let frameRate: Int
    let frames: [TestVRMAFrame]
    
    var duration: Float {
        frames.last?.time ?? 0
    }
    
    var frameCount: Int {
        frames.count
    }
}

// MARK: - VRMA Exporter

enum TestVRMAExporter {
    static func export(session: TestVRMASession, to url: URL) throws {
        // Build glTF/VRMA JSON
        let json = try buildVRMAJSON(session: session)
        
        // Build binary buffer
        let binaryData = buildBinaryBuffer(session: session)
        
        // Create GLB
        let glbData = try createGLB(json: json, binaryData: binaryData)
        
        // Write to file
        try glbData.write(to: url)
    }
    
    private static func buildVRMAJSON(session: TestVRMASession) throws -> [String: Any] {
        let animatedBones = collectAnimatedBones(session: session)
        
        // Build nodes
        let (nodes, boneNodeMap) = buildNodes(animatedBones: animatedBones)
        
        // Build accessors and buffer views
        let (bufferViews, accessors, bufferByteLength) = buildAccessors(
            session: session,
            animatedBones: animatedBones
        )
        
        // Build animation
        let animation = buildAnimation(
            session: session,
            animatedBones: animatedBones,
            boneNodeMap: boneNodeMap
        )
        
        // Build VRMC_vrm_animation extension
        let vrmaExtension = buildVRMAExtension(
            animatedBones: animatedBones,
            boneNodeMap: boneNodeMap
        )
        
        var gltf: [String: Any] = [
            "asset": [
                "version": "2.0",
                "generator": "Arkavo Test VRMA Generator"
            ],
            "scene": 0,
            "scenes": [["nodes": Array(0..<nodes.count)]],
            "nodes": nodes,
            "buffers": [["byteLength": bufferByteLength]],
            "bufferViews": bufferViews,
            "accessors": accessors,
            "animations": [animation],
            "extensions": ["VRMC_vrm_animation": vrmaExtension],
            "extensionsUsed": ["VRMC_vrm_animation"]
        ]
        
        return gltf
    }
    
    private static func collectAnimatedBones(session: TestVRMASession) -> [String] {
        var bones = Set<String>()
        for frame in session.frames {
            for bone in frame.boneRotations.keys {
                bones.insert(bone)
            }
        }
        return bones.sorted()
    }
    
    private static func buildNodes(animatedBones: [String]) -> ([[String: Any]], [String: Int]) {
        var nodes: [[String: Any]] = []
        var boneNodeMap: [String: Int] = [:]
        
        for bone in animatedBones {
            boneNodeMap[bone] = nodes.count
            nodes.append([
                "name": bone,
                "rotation": [0, 0, 0, 1],  // Identity quaternion (x, y, z, w)
                "translation": [0, 0, 0]
            ])
        }
        
        return (nodes, boneNodeMap)
    }
    
    private static func buildAccessors(
        session: TestVRMASession,
        animatedBones: [String]
    ) -> ([[String: Any]], [[String: Any]], Int) {
        var bufferViews: [[String: Any]] = []
        var accessors: [[String: Any]] = []
        var byteOffset = 0
        let frameCount = session.frames.count
        
        // Time accessor (shared)
        let timeByteLength = frameCount * MemoryLayout<Float>.size
        bufferViews.append([
            "buffer": 0,
            "byteOffset": byteOffset,
            "byteLength": timeByteLength
        ])
        accessors.append([
            "bufferView": bufferViews.count - 1,
            "componentType": 5126, // FLOAT
            "count": frameCount,
            "type": "SCALAR",
            "min": [0.0],
            "max": [Double(session.duration)]
        ])
        byteOffset += timeByteLength
        
        // Rotation accessors for each bone
        for _ in animatedBones {
            let quatByteLength = frameCount * 4 * MemoryLayout<Float>.size
            bufferViews.append([
                "buffer": 0,
                "byteOffset": byteOffset,
                "byteLength": quatByteLength
            ])
            accessors.append([
                "bufferView": bufferViews.count - 1,
                "componentType": 5126, // FLOAT
                "count": frameCount,
                "type": "VEC4"
            ])
            byteOffset += quatByteLength
        }
        
        // Hips translation accessor (if present)
        if animatedBones.contains("hips") {
            let transByteLength = frameCount * 3 * MemoryLayout<Float>.size
            bufferViews.append([
                "buffer": 0,
                "byteOffset": byteOffset,
                "byteLength": transByteLength
            ])
            accessors.append([
                "bufferView": bufferViews.count - 1,
                "componentType": 5126, // FLOAT
                "count": frameCount,
                "type": "VEC3"
            ])
            byteOffset += transByteLength
        }
        
        return (bufferViews, accessors, byteOffset)
    }
    
    private static func buildAnimation(
        session: TestVRMASession,
        animatedBones: [String],
        boneNodeMap: [String: Int]
    ) -> [String: Any] {
        var channels: [[String: Any]] = []
        var samplers: [[String: Any]] = []
        
        // Time accessor is always index 0
        let timeAccessorIndex = 0
        var outputAccessorIndex = 1
        
        // Rotation channels
        for bone in animatedBones {
            guard let nodeIndex = boneNodeMap[bone] else { continue }
            
            samplers.append([
                "input": timeAccessorIndex,
                "output": outputAccessorIndex,
                "interpolation": "LINEAR"
            ])
            
            channels.append([
                "sampler": samplers.count - 1,
                "target": [
                    "node": nodeIndex,
                    "path": "rotation"
                ]
            ])
            
            outputAccessorIndex += 1
        }
        
        // Hips translation channel
        if animatedBones.contains("hips"), let hipsNodeIndex = boneNodeMap["hips"] {
            samplers.append([
                "input": timeAccessorIndex,
                "output": outputAccessorIndex,
                "interpolation": "LINEAR"
            ])
            
            channels.append([
                "sampler": samplers.count - 1,
                "target": [
                    "node": hipsNodeIndex,
                    "path": "translation"
                ]
            ])
        }
        
        return [
            "name": session.name,
            "channels": channels,
            "samplers": samplers
        ]
    }
    
    private static func buildVRMAExtension(
        animatedBones: [String],
        boneNodeMap: [String: Int]
    ) -> [String: Any] {
        var humanBones: [String: [String: Any]] = [:]
        
        for bone in animatedBones {
            if let nodeIndex = boneNodeMap[bone] {
                humanBones[bone] = ["node": nodeIndex]
            }
        }
        
        return [
            "specVersion": "1.0",
            "humanoid": ["humanBones": humanBones]
        ]
    }
    
    private static func buildBinaryBuffer(session: TestVRMASession) -> Data {
        var buffer = Data()
        let animatedBones = collectAnimatedBones(session: session)
        
        // Time values
        for frame in session.frames {
            var time = frame.time
            buffer.append(Data(bytes: &time, count: MemoryLayout<Float>.size))
        }
        
        // Rotation values for each bone
        for bone in animatedBones {
            for frame in session.frames {
                let quat = frame.boneRotations[bone] ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
                var x = quat.imag.x
                var y = quat.imag.y
                var z = quat.imag.z
                var w = quat.real
                buffer.append(Data(bytes: &x, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &y, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &z, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &w, count: MemoryLayout<Float>.size))
            }
        }
        
        // Hips translation
        if animatedBones.contains("hips") {
            for frame in session.frames {
                var trans = frame.hipsTranslation ?? simd_float3(0, 0, 0)
                buffer.append(Data(bytes: &trans.x, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &trans.y, count: MemoryLayout<Float>.size))
                buffer.append(Data(bytes: &trans.z, count: MemoryLayout<Float>.size))
            }
        }
        
        return buffer
    }
    
    private static func createGLB(json: [String: Any], binaryData: Data) throws -> Data {
        // Serialize JSON
        let jsonData = try JSONSerialization.data(withJSONObject: json)
        
        // Pad JSON to 4-byte boundary
        let jsonPadding = (4 - (jsonData.count % 4)) % 4
        var paddedJSON = jsonData
        if jsonPadding > 0 {
            paddedJSON.append(Data(repeating: 0x20, count: jsonPadding))
        }
        
        // Pad binary to 4-byte boundary
        let binaryPadding = (4 - (binaryData.count % 4)) % 4
        var paddedBinary = binaryData
        if binaryPadding > 0 {
            paddedBinary.append(Data(repeating: 0x00, count: binaryPadding))
        }
        
        // Calculate total length
        let headerLength = 12
        let jsonChunkHeaderLength = 8
        let binaryChunkHeaderLength = 8
        let totalLength = headerLength + jsonChunkHeaderLength + paddedJSON.count + binaryChunkHeaderLength + paddedBinary.count
        
        // Build GLB
        var glbData = Data()
        
        // Header
        glbData.append(littleEndianUInt32(0x46546C67)) // magic "glTF"
        glbData.append(littleEndianUInt32(2)) // version 2
        glbData.append(littleEndianUInt32(UInt32(totalLength)))
        
        // JSON chunk
        glbData.append(littleEndianUInt32(UInt32(paddedJSON.count)))
        glbData.append(littleEndianUInt32(0x4E4F534A)) // "JSON"
        glbData.append(paddedJSON)
        
        // Binary chunk
        glbData.append(littleEndianUInt32(UInt32(paddedBinary.count)))
        glbData.append(littleEndianUInt32(0x004E4942)) // "BIN\0"
        glbData.append(paddedBinary)
        
        return glbData
    }
    
    private static func littleEndianUInt32(_ value: UInt32) -> Data {
        var value = value.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

// MARK: - Test Pose Generators

func generateIdentityPoseFrames(count: Int, duration: Float) -> [TestVRMAFrame] {
    return (0..<count).map { i in
        TestVRMAFrame(
            time: Float(i) * (duration / Float(count)),
            boneRotations: ["hips": simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)],
            hipsTranslation: nil
        )
    }
}

func generateRotatingHipsFrames(count: Int, duration: Float) -> [TestVRMAFrame] {
    return (0..<count).map { i in
        let t = Float(i) / Float(count)
        let angle = t * 2 * .pi  // Full rotation
        let rotation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
        
        return TestVRMAFrame(
            time: t * duration,
            boneRotations: ["hips": rotation],
            hipsTranslation: nil
        )
    }
}

func generateWalkingFrames(count: Int, duration: Float) -> [TestVRMAFrame] {
    return (0..<count).map { i in
        let t = Float(i) / Float(count)
        let time = t * duration
        
        // Alternating leg swing
        let leftLegAngle = sin(t * 4 * .pi) * 0.3
        let rightLegAngle = sin(t * 4 * .pi + .pi) * 0.3
        
        return TestVRMAFrame(
            time: time,
            boneRotations: [
                "hips": simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                "leftUpperLeg": simd_quatf(angle: leftLegAngle, axis: SIMD3<Float>(1, 0, 0)),
                "rightUpperLeg": simd_quatf(angle: rightLegAngle, axis: SIMD3<Float>(1, 0, 0))
            ],
            hipsTranslation: nil
        )
    }
}

// MARK: - Main

let outputDir = FileManager.default.currentDirectoryPath + "/TestVRMAs"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("Generating test VRMA files in: \(outputDir)")

// Test 1: Identity pose (T-pose)
let identitySession = TestVRMASession(
    name: "identity_test",
    frameRate: 30,
    frames: generateIdentityPoseFrames(count: 30, duration: 1.0)
)

let identityURL = URL(fileURLWithPath: "\(outputDir)/identity_test.vrma")
try? TestVRMAExporter.export(session: identitySession, to: identityURL)
print("✅ Created: identity_test.vrma")

// Test 2: Rotating hips
let rotatingSession = TestVRMASession(
    name: "rotating_hips",
    frameRate: 30,
    frames: generateRotatingHipsFrames(count: 60, duration: 2.0)
)

let rotatingURL = URL(fileURLWithPath: "\(outputDir)/rotating_hips.vrma")
try? TestVRMAExporter.export(session: rotatingSession, to: rotatingURL)
print("✅ Created: rotating_hips.vrma")

// Test 3: Walking motion
let walkingSession = TestVRMASession(
    name: "walking_motion",
    frameRate: 30,
    frames: generateWalkingFrames(count: 60, duration: 2.0)
)

let walkingURL = URL(fileURLWithPath: "\(outputDir)/walking_motion.vrma")
try? TestVRMAExporter.export(session: walkingSession, to: walkingURL)
print("✅ Created: walking_motion.vrma")

print("\nDone! Generated 3 test VRMA files.")
print("These can be used to validate VRMMetalKit animation loading.")
