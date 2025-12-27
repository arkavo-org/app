import SwiftUI
import ArkavoKit

@MainActor
final class CameraPreviewStore: ObservableObject {
    static let shared = CameraPreviewStore()

    @Published private(set) var images: [String: NSImage] = [:]

    private init() { /* Singleton: prevents external instantiation */ }

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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let sourceLabel {
                    Label(sourceLabel, systemImage: "link")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 4)

            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.secondary)
                            .symbolEffect(.pulse, options: .repeating)
                        
                        Text(placeholderText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 200)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )
                }
            }
        }
        .padding(12)
        .background(.regularMaterial.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
    }
}
