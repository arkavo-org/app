import SwiftUI

enum ScenePreset: String, CaseIterable, Identifiable, Codable {
    case live = "Live"
    case startingSoon = "Starting Soon"
    case brb = "Be Right Back"
    case ending = "Ending"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .live: "play.fill"
        case .startingSoon: "clock"
        case .brb: "cup.and.saucer"
        case .ending: "hand.wave"
        }
    }

    var muteMic: Bool { self != .live }
    var hideCamera: Bool { self != .live }

    var overlayText: String {
        switch self {
        case .live: ""
        case .startingSoon: "Starting Soon..."
        case .brb: "Be Right Back"
        case .ending: "Thanks for watching!"
        }
    }
}

struct SceneOverlayView: View {
    let scene: ScenePreset
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: scene.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.9))

                Text(scene.overlayText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .scaleEffect(appeared ? 1.0 : 0.9)
            .opacity(appeared ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
        .onDisappear {
            appeared = false
        }
    }

    private var gradientColors: [Color] {
        switch scene {
        case .live: [.clear]
        case .startingSoon: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
        case .brb: [Color.orange.opacity(0.8), Color.pink.opacity(0.8)]
        case .ending: [Color.indigo.opacity(0.8), Color.purple.opacity(0.8)]
        }
    }
}
