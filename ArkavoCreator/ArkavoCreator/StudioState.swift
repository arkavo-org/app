import SwiftUI

/// Persona represents the creator's on-screen identity
/// This is set once and persisted - not changed during a session
enum Persona: String, CaseIterable, Identifiable, Codable {
    case face = "Face"
    case avatar = "Avatar"
    case audio = "Audio"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .face: return "person.fill"
        case .avatar: return "sparkles"
        case .audio: return "waveform"
        }
    }

    var description: String {
        switch self {
        case .face: return "Show your camera feed"
        case .avatar: return "Use VRM avatar with face tracking"
        case .audio: return "Audio-only podcast mode"
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
/// Identity (Persona) is set once and rarely changes
/// Stage controls (Screen/Mic) remain runtime state in RecordViewModel
@MainActor
@Observable
final class StudioState {
    static let shared = StudioState()

    // MARK: - Persisted Identity

    var persona: Persona {
        didSet {
            UserDefaults.standard.set(persona.rawValue, forKey: "studio.persona")
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

    // MARK: - Persisted Output Preference

    var defaultOutput: OutputMode {
        didSet {
            UserDefaults.standard.set(defaultOutput.rawValue, forKey: "studio.defaultOutput")
        }
    }

    // MARK: - Initialization

    private init() {
        // Load persisted values
        if let personaRaw = UserDefaults.standard.string(forKey: "studio.persona"),
           let persona = Persona(rawValue: personaRaw)
        {
            self.persona = persona
        } else {
            persona = .face
        }

        selectedCameraID = UserDefaults.standard.string(forKey: "studio.selectedCameraID")
        selectedVRMPath = UserDefaults.standard.string(forKey: "studio.selectedVRMPath")

        if let outputRaw = UserDefaults.standard.string(forKey: "studio.defaultOutput"),
           let output = OutputMode(rawValue: outputRaw)
        {
            defaultOutput = output
        } else {
            defaultOutput = .record
        }
    }

    // MARK: - Computed Properties

    /// Whether camera should be enabled based on persona
    var enableCamera: Bool {
        persona == .face
    }

    /// Whether avatar should be enabled based on persona
    var enableAvatar: Bool {
        persona == .avatar
    }

    /// Whether this is audio-only mode
    var isAudioOnly: Bool {
        persona == .audio
    }
}
