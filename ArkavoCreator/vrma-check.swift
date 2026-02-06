#!/usr/bin/env swift
//
//  vrma-check.swift
//  Quick VRMA file analyzer
//
//  Usage: swift vrma-check.swift [path-to-vrma]
//         If no path provided, checks latest in ~/Documents/VRMA/
//

import Foundation

// MARK: - GLB/glTF Structures

struct GLBHeader {
    let magic: UInt32
    let version: UInt32
    let length: UInt32
}

struct GLBChunk {
    let length: UInt32
    let type: UInt32
    let data: Data
}

// MARK: - VRMA Analysis

func analyzeVRMA(at url: URL) {
    print("Analyzing: \(url.lastPathComponent)")
    print(String(repeating: "=", count: 60))

    guard let data = try? Data(contentsOf: url) else {
        print("ERROR: Could not read file")
        return
    }

    print("File size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")

    // Parse GLB header
    guard data.count >= 12 else {
        print("ERROR: File too small for GLB header")
        return
    }

    let magic = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
    let version = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) }
    let length = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self) }

    // Check magic number (0x46546C67 = "glTF")
    guard magic == 0x46546C67 else {
        print("ERROR: Not a valid GLB file (magic: \(String(format: "0x%08X", magic)))")
        return
    }

    print("GLB version: \(version)")
    print("Total length: \(length) bytes")

    // Parse chunks
    var offset = 12
    var jsonChunk: Data?
    var binChunk: Data?

    while offset + 8 <= data.count {
        let chunkLength = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        let chunkType = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 4, as: UInt32.self) }

        let chunkStart = offset + 8
        let chunkEnd = chunkStart + Int(chunkLength)

        guard chunkEnd <= data.count else {
            print("ERROR: Chunk extends beyond file")
            break
        }

        let chunkData = data.subdata(in: chunkStart..<chunkEnd)

        if chunkType == 0x4E4F534A { // "JSON"
            jsonChunk = chunkData
            print("\nJSON chunk: \(chunkLength) bytes")
        } else if chunkType == 0x004E4942 { // "BIN\0"
            binChunk = chunkData
            print("Binary chunk: \(chunkLength) bytes")
        }

        offset = chunkEnd
    }

    // Parse JSON
    guard let json = jsonChunk,
          let jsonObj = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
        print("ERROR: Could not parse JSON chunk")
        return
    }

    print("\n" + String(repeating: "-", count: 60))
    print("CONTENT ANALYSIS")
    print(String(repeating: "-", count: 60))

    // Check extensions
    if let extensionsUsed = jsonObj["extensionsUsed"] as? [String] {
        print("\nExtensions: \(extensionsUsed.joined(separator: ", "))")
    }

    // Check nodes (skeleton)
    if let nodes = jsonObj["nodes"] as? [[String: Any]] {
        print("\nNodes: \(nodes.count)")
        let namedNodes = nodes.compactMap { $0["name"] as? String }
        if !namedNodes.isEmpty {
            print("  Named bones: \(namedNodes.prefix(10).joined(separator: ", "))\(namedNodes.count > 10 ? "..." : "")")
        }
    }

    // Check animations
    if let animations = jsonObj["animations"] as? [[String: Any]] {
        print("\nAnimations: \(animations.count)")
        for (i, anim) in animations.enumerated() {
            let name = anim["name"] as? String ?? "unnamed"
            let channels = anim["channels"] as? [[String: Any]] ?? []
            let samplers = anim["samplers"] as? [[String: Any]] ?? []
            print("  [\(i)] \"\(name)\" - \(channels.count) channels, \(samplers.count) samplers")
        }
    }

    // Check accessors for keyframe count
    if let accessors = jsonObj["accessors"] as? [[String: Any]] {
        print("\nAccessors: \(accessors.count)")

        // Find time accessor (usually first one used by animation)
        for (i, accessor) in accessors.enumerated() {
            let count = accessor["count"] as? Int ?? 0
            let type = accessor["type"] as? String ?? "?"
            let componentType = accessor["componentType"] as? Int ?? 0

            // Time accessor is typically SCALAR with count = frame count
            if type == "SCALAR" && i == 0 {
                print("  Keyframes: \(count)")

                // Calculate duration from min/max if available
                if let min = accessor["min"] as? [Double], let max = accessor["max"] as? [Double],
                   let minTime = min.first, let maxTime = max.first {
                    let duration = maxTime - minTime
                    let fps = duration > 0 ? Double(count) / duration : 0
                    print("  Duration: \(String(format: "%.2f", duration))s")
                    print("  Frame rate: \(String(format: "%.1f", fps)) fps")
                }
            }
        }
    }

    // Check VRMC_vrm_animation extension
    if let extensions = jsonObj["extensions"] as? [String: Any],
       let vrmaExt = extensions["VRMC_vrm_animation"] as? [String: Any] {
        print("\n" + String(repeating: "-", count: 60))
        print("VRMC_vrm_animation EXTENSION")
        print(String(repeating: "-", count: 60))

        // Humanoid bones
        if let humanoid = vrmaExt["humanoid"] as? [String: Any],
           let humanBones = humanoid["humanBones"] as? [String: Any] {
            print("\nHumanoid bones: \(humanBones.count)")
            let boneNames = Array(humanBones.keys).sorted()
            print("  \(boneNames.prefix(8).joined(separator: ", "))\(boneNames.count > 8 ? "..." : "")")
        }

        // Expressions
        if let expressions = vrmaExt["expressions"] as? [String: Any] {
            if let preset = expressions["preset"] as? [String: Any] {
                print("\nPreset expressions: \(preset.count)")
                print("  \(Array(preset.keys).sorted().prefix(8).joined(separator: ", "))\(preset.count > 8 ? "..." : "")")
            }
            if let custom = expressions["custom"] as? [String: Any] {
                print("Custom expressions: \(custom.count)")
                if !custom.isEmpty {
                    print("  \(Array(custom.keys).sorted().prefix(8).joined(separator: ", "))\(custom.count > 8 ? "..." : "")")
                }
            }
        }

        // LookAt
        if let lookAt = vrmaExt["lookAt"] as? [String: Any] {
            print("\nLookAt node: \(lookAt["node"] ?? "?")")
        }
    }

    print("\n" + String(repeating: "=", count: 60))
    print("VRMA file appears valid!")
}

// MARK: - Main

func findLatestVRMA() -> URL? {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let vrmaDir = documentsURL.appendingPathComponent("VRMA")

    guard let files = try? FileManager.default.contentsOfDirectory(at: vrmaDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
        return nil
    }

    let vrmaFiles = files.filter { $0.pathExtension == "vrma" }

    return vrmaFiles.max { a, b in
        let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
        return aDate < bDate
    }
}

// Entry point
let args = CommandLine.arguments

if args.count > 1 {
    // Use provided path
    let path = args[1]
    let url = URL(fileURLWithPath: path)
    analyzeVRMA(at: url)
} else {
    // Find latest VRMA
    if let latest = findLatestVRMA() {
        analyzeVRMA(at: latest)
    } else {
        print("No VRMA files found in ~/Documents/VRMA/")
        print("")
        print("Usage: swift vrma-check.swift [path-to-vrma]")
        print("       If no path provided, checks latest in ~/Documents/VRMA/")

        // List any .vrma files in common locations
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let searchPaths = [
            homeDir.appendingPathComponent("Documents"),
            homeDir.appendingPathComponent("Downloads"),
            homeDir.appendingPathComponent("Desktop")
        ]

        var foundFiles: [URL] = []
        for searchPath in searchPaths {
            if let enumerator = FileManager.default.enumerator(at: searchPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                while let url = enumerator.nextObject() as? URL {
                    if url.pathExtension == "vrma" {
                        foundFiles.append(url)
                    }
                    // Don't go too deep
                    if enumerator.level > 2 {
                        enumerator.skipDescendants()
                    }
                }
            }
        }

        if !foundFiles.isEmpty {
            print("\nFound VRMA files:")
            for file in foundFiles.prefix(10) {
                print("  \(file.path)")
            }
        }
    }
}
