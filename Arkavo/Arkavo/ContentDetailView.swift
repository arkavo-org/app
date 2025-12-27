import ArkavoSocial
import SwiftUI

// MARK: - Content Detail View

/// Detailed view for a single content descriptor
/// Allows fetching the full TDF payload from Iroh
struct ContentDetailView: View {
    let descriptor: ContentDescriptor
    @Environment(\.dismiss) private var dismiss
    @State private var isFetching = false
    @State private var fetchError: String?
    @State private var tdfData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with thumbnail
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.1))
                            .frame(height: 200)

                        VStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)

                            Text("TDF Protected")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    // Title
                    Text(descriptor.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    // Metadata
                    VStack(alignment: .leading, spacing: 12) {
                        ContentInfoRow(label: "Type", value: descriptor.mimeType)

                        if let duration = descriptor.durationSeconds {
                            ContentInfoRow(label: "Duration", value: formatDuration(duration))
                        }

                        ContentInfoRow(label: "Original Size", value: formatSize(descriptor.originalFileSize))
                        ContentInfoRow(label: "TDF Size", value: formatSize(descriptor.payloadSize))
                        ContentInfoRow(label: "Protected", value: formatDate(descriptor.manifest.protectedAt))
                        ContentInfoRow(label: "Encryption", value: descriptor.manifest.algorithm)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Fetch button
                    if tdfData == nil {
                        Button {
                            Task { await fetchContent() }
                        } label: {
                            HStack {
                                if isFetching {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text(isFetching ? "Fetching..." : "Fetch Content")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isFetching)
                    } else {
                        VStack(spacing: 8) {
                            Label("Content fetched (\(formatSize(Int64(tdfData!.count))))",
                                  systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)

                            Text("Decryption coming soon")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = fetchError {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Content Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func fetchContent() async {
        isFetching = true
        fetchError = nil
        defer { isFetching = false }

        guard let service = await ArkavoIrohManager.shared.contentService else {
            fetchError = "Iroh not initialized"
            return
        }

        do {
            tdfData = try await service.fetchPayloadWithRetry(
                payloadTicket: descriptor.payloadTicket
            )
        } catch {
            fetchError = error.localizedDescription
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return isoString
    }
}

// MARK: - Content Info Row

private struct ContentInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentDetailView(
        descriptor: ContentDescriptor(
            id: UUID(),
            contentID: Data(repeating: 0, count: 32),
            creatorPublicID: Data(repeating: 1, count: 32),
            manifest: TDFManifestLite(
                kasURL: "https://kas.arkavo.net",
                wrappedKey: "base64key",
                algorithm: "AES-128-CBC",
                iv: "base64iv",
                assetID: UUID().uuidString,
                protectedAt: ISO8601DateFormatter().string(from: Date())
            ),
            payloadTicket: "blobaaaa...",
            payloadSize: 52_428_800,
            title: "Sample Video Recording",
            mimeType: "video/quicktime",
            durationSeconds: 125.5,
            originalFileSize: 104_857_600,
            createdAt: Date(),
            updatedAt: Date(),
            version: 1
        )
    )
}
