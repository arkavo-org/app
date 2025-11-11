import SwiftUI
import ArkavoKit

@MainActor
final class CameraPreviewStore: ObservableObject {
    static let shared = CameraPreviewStore()

    @Published private(set) var images: [String: NSImage] = [:]

    private init() {}

    func update(with event: CameraPreviewEvent) {
        let image = NSImage(cgImage: event.image, size: .zero)
        images[event.sourceID] = image
    }

    func image(for sourceID: String?) -> NSImage? {
        guard let id = sourceID else { return nil }
        return images[id]
    }

    var availableSources: [String] {
        Array(images.keys).sorted()
    }
}

struct CameraPreviewPanel: View {
    let title: String
    let image: NSImage?
    let sourceLabel: String?
    let placeholderText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let sourceLabel {
                    Text(sourceLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "video.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(placeholderText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(12)
                }
            }
        }
    }
}
