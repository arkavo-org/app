import SwiftUI
import ArkavoC2PA

/// Displays C2PA provenance information for a recording
struct ProvenanceView: View {
    let recording: Recording
    @State private var validationResult: C2PAValidationResult?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundStyle(validationResult?.isValid == true ? .green : .secondary)

                VStack(alignment: .leading) {
                    Text("Content Provenance")
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let result = validationResult {
                        Text(result.hasManifest ? (result.isValid ? "Valid C2PA Signature" : "Invalid Signature") : "No C2PA Manifest")
                            .font(.subheadline)
                            .foregroundStyle(result.isValid ? .green : .secondary)
                    }
                }

                Spacer()
            }

            Divider()

            if isLoading {
                ProgressView("Verifying provenance...")
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let error = error {
                errorView(error)
            } else if let result = validationResult {
                manifestContent(result)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .task {
            await loadProvenance()
        }
    }

    // MARK: - Subviews

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Verification Failed")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
    }

    private func manifestContent(_ result: C2PAValidationResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Status Section
                statusSection(result)

                Divider()

                // Recording Info
                recordingInfoSection()

                Divider()

                // Manifest Details
                if result.hasManifest {
                    manifestDetailsSection(result)
                }

                // Raw Manifest
                if result.hasManifest, !result.manifestJSON.isEmpty {
                    Divider()
                    rawManifestSection(result)
                }
            }
        }
    }

    private func statusSection(_ result: C2PAValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Verification Status")
                .font(.headline)

            HStack {
                Label(
                    result.hasManifest ? "C2PA Manifest Present" : "No C2PA Manifest",
                    systemImage: result.hasManifest ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(result.hasManifest ? .green : .secondary)
            }

            if result.hasManifest {
                HStack {
                    Label(
                        result.isValid ? "Signature Valid" : "Signature Invalid",
                        systemImage: result.isValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(result.isValid ? .green : .red)
                }
            }

            if let errorMsg = result.error, !errorMsg.isEmpty {
                Text("Error: \(errorMsg)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.top, 4)
            }
        }
    }

    private func recordingInfoSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording Information")
                .font(.headline)

            infoRow(label: "Title", value: recording.title)
            infoRow(label: "Date", value: recording.formattedDate)
            infoRow(label: "Duration", value: recording.formattedDuration)
            infoRow(label: "File Size", value: recording.formattedFileSize)
            infoRow(label: "Location", value: recording.url.path)
        }
    }

    private func manifestDetailsSection(_ result: C2PAValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manifest Details")
                .font(.headline)

            // Parse and display key information from manifest JSON
            if let manifestData = result.manifestJSON.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] {
                manifestKeyInfo(json)
            } else {
                Text("Manifest contains provenance data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func manifestKeyInfo(_ json: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let claimGenerator = json["claim_generator"] as? String {
                infoRow(label: "Claim Generator", value: claimGenerator)
            }

            if let title = json["title"] as? String {
                infoRow(label: "Manifest Title", value: title)
            }

            if let format = json["format"] as? String {
                infoRow(label: "Format", value: format)
            }

            if let assertions = json["assertions"] as? [[String: Any]] {
                Text("Assertions: \(assertions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rawManifestSection(_ result: C2PAValidationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Raw Manifest")
                    .font(.headline)

                Spacer()

                Button(action: copyManifest) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                Text(result.manifestJSON)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 200)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)

            Text(value)
                .font(.caption)
                .textSelection(.enabled)

            Spacer()
        }
    }

    // MARK: - Actions

    private func loadProvenance() async {
        isLoading = true
        error = nil

        do {
            let signer = try C2PASigner()
            let result = try await signer.verify(file: recording.url)
            validationResult = result
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func copyManifest() {
        guard let result = validationResult else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result.manifestJSON, forType: .string)
    }
}

// MARK: - Preview

#Preview {
    ProvenanceView(recording: Recording(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/test.mov"),
        title: "Test Recording",
        date: Date(),
        duration: 120.0,
        fileSize: 1024 * 1024 * 50,
        thumbnailPath: nil,
        c2paStatus: .signed(validatedAt: Date(), isValid: true)
    ))
}
