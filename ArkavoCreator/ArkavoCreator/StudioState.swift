import SwiftUI

/// Visual source represents what's shown in the PIP
enum VisualSource: String, CaseIterable, Identifiable, Codable {
    case face = "Face"
    case avatar = "Avatar"
    case muse = "Muse"

    /// Sources gated by feature flags
    static var availableSources: [VisualSource] {
        var sources: [VisualSource] = [.face]
        if FeatureFlags.avatar {
            sources.append(.avatar)
            sources.append(.muse)
        }
        return sources
    }

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .face: return "person.fill"
        case .avatar: return "sparkles"
        case .muse: return "brain.head.profile"
        }
    }

    var description: String {
        switch self {
        case .face: return "Show your camera feed"
        case .avatar: return "Use VRM avatar with face tracking"
        case .muse: return "AI-driven avatar with speech and animation"
        }
    }
}

/// Output mode for the studio
enum OutputMode: String, CaseIterable, Identifiable, Codable {
    case record = "Record"
    case stream = "Stream"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .record: return "record.circle"
        case .stream: return "antenna.radiowaves.left.and.right"
        }
    }
}

/// Persisted studio preferences
/// Visual source (Face/Avatar) is toggleable - can be none for audio-only
/// Audio controls (Mic/Desktop Audio toggles and volumes) are persisted here
@MainActor
@Observable
final class StudioState {
    static let shared = StudioState()

    // MARK: - Persisted Visual Source (nil = audio only)

    var visualSource: VisualSource? {
        didSet {
            if let source = visualSource {
                UserDefaults.standard.set(source.rawValue, forKey: "studio.visualSource")
            } else {
                UserDefaults.standard.removeObject(forKey: "studio.visualSource")
            }
        }
    }

    var selectedCameraID: String? {
        didSet {
            UserDefaults.standard.set(selectedCameraID, forKey: "studio.selectedCameraID")
        }
    }

    var selectedVRMPath: String? {
        didSet {
            UserDefaults.standard.set(selectedVRMPath, forKey: "studio.selectedVRMPath")
        }
    }

    /// Enable floating head mode (person segmentation with transparent background)
    var floatingHeadEnabled: Bool {
        didSet {
            UserDefaults.standard.set(floatingHeadEnabled, forKey: "studio.floatingHeadEnabled")
        }
    }

    /// Active scene preset
    var activeScene: ScenePreset = .live {
        didSet {
            UserDefaults.standard.set(activeScene.rawValue, forKey: "studio.activeScene")
        }
    }

    /// Whether a non-live scene overlay is active
    var isSceneOverlayActive: Bool { activeScene != .live }

    // MARK: - Persisted Audio Controls

    var enableMicrophone: Bool {
        didSet { UserDefaults.standard.set(enableMicrophone, forKey: "studio.enableMicrophone") }
    }

    var enableDesktopAudio: Bool {
        didSet { UserDefaults.standard.set(enableDesktopAudio, forKey: "studio.enableDesktopAudio") }
    }

    var micVolume: Float {
        didSet { UserDefaults.standard.set(micVolume, forKey: "studio.micVolume") }
    }

    var desktopAudioVolume: Float {
        didSet { UserDefaults.standard.set(desktopAudioVolume, forKey: "studio.desktopAudioVolume") }
    }

    // MARK: - Persisted Output Preference

    var defaultOutput: OutputMode {
        didSet {
            UserDefaults.standard.set(defaultOutput.rawValue, forKey: "studio.defaultOutput")
        }
    }

    // MARK: - Initialization

    private init() {
        // Load persisted values
        if let sourceRaw = UserDefaults.standard.string(forKey: "studio.visualSource"),
           let source = VisualSource(rawValue: sourceRaw),
           VisualSource.availableSources.contains(source)
        {
            self.visualSource = source
        } else {
            // Default to no visual source (camera off)
            visualSource = nil
        }

        selectedCameraID = UserDefaults.standard.string(forKey: "studio.selectedCameraID")
        selectedVRMPath = UserDefaults.standard.string(forKey: "studio.selectedVRMPath")
        floatingHeadEnabled = UserDefaults.standard.bool(forKey: "studio.floatingHeadEnabled")

        enableMicrophone = UserDefaults.standard.bool(forKey: "studio.enableMicrophone")
        enableDesktopAudio = UserDefaults.standard.bool(forKey: "studio.enableDesktopAudio")
        let savedMicVol = UserDefaults.standard.float(forKey: "studio.micVolume")
        micVolume = savedMicVol > 0 ? savedMicVol : 1.0
        let savedDesktopVol = UserDefaults.standard.float(forKey: "studio.desktopAudioVolume")
        desktopAudioVolume = savedDesktopVol > 0 ? savedDesktopVol : 1.0

        if let sceneRaw = UserDefaults.standard.string(forKey: "studio.activeScene"),
           let scene = ScenePreset(rawValue: sceneRaw) {
            activeScene = scene
        }

        if let outputRaw = UserDefaults.standard.string(forKey: "studio.defaultOutput"),
           let output = OutputMode(rawValue: outputRaw)
        {
            defaultOutput = output
        } else {
            defaultOutput = .record
        }
    }

    // MARK: - Computed Properties

    /// Whether camera should be enabled
    var enableCamera: Bool {
        visualSource == .face
    }

    /// Whether avatar should be enabled
    var enableAvatar: Bool {
        visualSource == .avatar
    }

    /// Whether Muse AI avatar should be enabled
    var enableMuse: Bool {
        visualSource == .muse
    }

    /// Whether this is audio-only mode (no visual source selected)
    var isAudioOnly: Bool {
        visualSource == nil
    }

    // MARK: - Actions

    /// Toggle a visual source on/off
    func toggleVisualSource(_ source: VisualSource) {
        if visualSource == source {
            visualSource = nil  // Deselect -> audio only
        } else {
            visualSource = source  // Select this source
        }
    }
}
