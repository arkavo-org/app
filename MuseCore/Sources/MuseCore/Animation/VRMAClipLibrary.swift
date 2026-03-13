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

import Foundation
import VRMMetalKit

/// Library for managing motion capture clips (VRMA files).
/// Discovers and loads clips from bundle and user Documents folder.
/// User clips take priority over bundled clips for the same emote.
@MainActor
public class VRMAClipLibrary {

    // MARK: - Properties

    /// Loaded clips keyed by filename (without extension)
    private var clips: [String: AnimationClip] = [:]

    /// Idle clips loaded from files with "idle_" prefix
    private var idleClips: [AnimationClip] = []

    /// VRM model for retargeting during load
    private var model: VRMModel?

    /// Whether initial loading has completed
    private(set) var isLoaded = false

    // MARK: - Emote Mapping

    /// Map from emote type to VRMA filename (without .vrma extension)
    private let emoteFileMap: [EmoteAnimationLayer.Emote: String] = [
        .wave: "wave",
        .jump: "jump",
        .nod: "nod",
        .bow: "bow",
        .hop: "hop",
        .thinking: "thinking",
        .surprised: "surprised",
        .laugh: "laugh",
        .shrug: "shrug",
        .clap: "clap",
        .sad: "sad",
        .angry: "angry",
        .pout: "pout",
        .excited: "excited",
        .scared: "scared",
        .flex: "flex",
        .heart: "heart",
        .point: "point",
        .bashful: "bashful",
        .victory: "victory",
        .exhausted: "exhausted",
        .dance: "dance",
        .yawn: "yawn",
        .curious: "curious",
        .nervous: "nervous",
        .proud: "proud",
        .relieved: "relieved",
        .disgust: "disgust",
        .goodbye: "goodbye",
        .love: "love",
        .confused: "confused",
        .grateful: "grateful",
        .danceGangnam: "danceGangnam",
        .danceDab: "danceDab",
        .walk: "walk",
        .arGreeting: "arGreeting",
    ]

    // MARK: - Initialization

    public init() {}

    // MARK: - Setup

    /// Setup the library with a VRM model for retargeting
    /// - Parameter model: The VRM model that clips will be applied to
    public func setup(model: VRMModel) {
        self.model = model
        print("[VRMAClipLibrary] Setup with model: \(model.meta.name ?? "Unknown")")
    }

    // MARK: - Loading

    /// Load all VRMA clips from bundle and Documents folder
    public func loadAllClips() async {
        await loadClipsFromBundle()
        await loadClipsFromDocuments()
        isLoaded = true
        print("[VRMAClipLibrary] Loaded \(clips.count) emote clips + \(idleClips.count) idle clips = \(clips.count + idleClips.count) total")
    }

    /// Load clips from the app bundle (Resources/VRMA/)
    public func loadClipsFromBundle() async {
        // Try multiple possible bundle paths
        let possiblePaths = ["Resources/VRMA", "VRMA", "Muse/Resources/VRMA"]

        for subpath in possiblePaths {
            if let vrmaURL = Bundle.main.resourceURL?.appendingPathComponent(subpath),
               FileManager.default.fileExists(atPath: vrmaURL.path) {
                print("[VRMAClipLibrary] Found bundle VRMA at: \(subpath)")
                await loadClips(from: vrmaURL, source: "bundle")
                return
            }
        }

        print("[VRMAClipLibrary] No VRMA bundle directory found (tried: \(possiblePaths.joined(separator: ", ")))")
    }

    /// Load clips from the user's Documents folder (VRMA/)
    /// User clips take priority over bundled clips with the same name
    public func loadClipsFromDocuments() async {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let vrmaURL = documentsURL.appendingPathComponent("VRMA")

        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: vrmaURL, withIntermediateDirectories: true)

        await loadClips(from: vrmaURL, source: "documents")
    }

    /// Load clips from a directory
    private func loadClips(from directoryURL: URL, source: String) async {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            print("[VRMAClipLibrary] Directory not found: \(directoryURL.path)")
            return
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )

            let vrmaFiles = contents.filter { $0.pathExtension.lowercased() == "vrma" }
            print("[VRMAClipLibrary] Found \(vrmaFiles.count) VRMA files in \(source)")

            for fileURL in vrmaFiles {
                await loadClip(from: fileURL, source: source)
            }
        } catch {
            print("[VRMAClipLibrary] Failed to enumerate \(source): \(error)")
        }
    }

    /// Load a single clip from URL
    private func loadClip(from url: URL, source: String) async {
        let name = url.deletingPathExtension().lastPathComponent

        do {
            let clip = try VRMAnimationLoader.loadVRMA(from: url, model: model)

            // Idle clips stored separately for the idle cycle layer
            if name.hasPrefix("idle_") {
                idleClips.append(clip)
                print("[VRMAClipLibrary] Loaded idle '\(name)' from \(source): \(clip.jointTracks.count) tracks, \(String(format: "%.2f", clip.duration))s")
            } else {
                clips[name] = clip
                print("[VRMAClipLibrary] Loaded '\(name)' from \(source): \(clip.jointTracks.count) tracks, \(String(format: "%.2f", clip.duration))s")
            }
        } catch {
            print("[VRMAClipLibrary] Failed to load '\(name)' from \(source): \(error)")
        }
    }

    // MARK: - Clip Access

    /// Get a clip by name
    /// - Parameter name: Clip name (filename without .vrma extension)
    /// - Returns: The loaded AnimationClip or nil if not found
    public func clip(named name: String) -> AnimationClip? {
        return clips[name]
    }

    /// Get a clip for an emote type
    /// - Parameter emote: The emote to get a clip for
    /// - Returns: The loaded AnimationClip or nil if no VRMA clip exists for this emote
    public func clip(for emote: EmoteAnimationLayer.Emote) -> AnimationClip? {
        guard let filename = emoteFileMap[emote] else { return nil }
        return clips[filename]
    }

    /// Check if a VRMA clip exists for an emote
    /// - Parameter emote: The emote to check
    /// - Returns: True if a VRMA clip is available
    public func hasClip(for emote: EmoteAnimationLayer.Emote) -> Bool {
        guard let filename = emoteFileMap[emote] else { return false }
        return clips[filename] != nil
    }

    /// Get all loaded idle clips for the idle cycle layer
    public var loadedIdleClips: [AnimationClip] {
        idleClips
    }

    /// Get all loaded clip names
    public var loadedClipNames: [String] {
        Array(clips.keys).sorted()
    }

    /// Get count of loaded clips
    public var clipCount: Int {
        clips.count + idleClips.count
    }

    // MARK: - Hot Reload

    /// Reload a specific clip from Documents (for hot-reload during development)
    /// - Parameter name: Clip name to reload
    public func reloadClip(named name: String) async {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let fileURL = documentsURL
            .appendingPathComponent("VRMA")
            .appendingPathComponent("\(name).vrma")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            await loadClip(from: fileURL, source: "documents (reload)")
        }
    }

    /// Clear all loaded clips
    public func clearAll() {
        clips.removeAll()
        idleClips.removeAll()
        isLoaded = false
        print("[VRMAClipLibrary] Cleared all clips")
    }
}
