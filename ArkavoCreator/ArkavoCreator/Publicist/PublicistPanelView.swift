import MuseCore
import SwiftUI

/// Compact side panel for the Publicist role — slides in from trailing edge on Dashboard
struct PublicistPanelView: View {
    @Bindable var viewModel: PublicistViewModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.modelManager.isReady ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Publicist")
                        .font(.headline)
                }

                Spacer()

                if !viewModel.modelManager.isReady {
                    Button("Load") {
                        Task { await viewModel.modelManager.loadSelectedModel() }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Platform selector (compact)
                    platformSelector

                    // Content type (compact)
                    contentTypeSelector

                    // Source input
                    sourceInput

                    // Generate
                    generateSection

                    // Output
                    if !viewModel.generatedContent.isEmpty || viewModel.isGenerating {
                        outputSection
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(width: 1).foregroundColor(.white.opacity(0.1)),
            alignment: .leading
        )
    }

    // MARK: - Platform Selector

    private var platformSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Platform")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PublicistPlatform.allCases, id: \.self) { platform in
                        let isSelected = viewModel.selectedPlatform == platform
                        Button {
                            viewModel.selectedPlatform = platform
                        } label: {
                            Text(platform.rawValue)
                                .font(.caption2.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Content Type

    private var contentTypeSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(PublicistContentType.allCases, id: \.self) { type in
                    let isSelected = viewModel.selectedContentType == type
                    Button {
                        viewModel.selectedContentType = type
                    } label: {
                        Text(type.rawValue)
                            .font(.caption2.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.2))
            .cornerRadius(8)
        }
    }

    // MARK: - Source Input

    private var sourceInput: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Source")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.sourceText)
                    .font(.caption)
                    .frame(minHeight: 40, maxHeight: 80)
                    .padding(6)
                    .scrollContentBackground(.hidden)

                if viewModel.sourceText.isEmpty {
                    Text("Paste or type source content...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(.quaternary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.1))
            )
        }
    }

    // MARK: - Generate

    private var generateSection: some View {
        HStack {
            if viewModel.isGenerating {
                Button("Stop") { viewModel.stopGeneration() }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            } else {
                Button("Generate") { viewModel.generate() }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.modelManager.isReady)
            }

            Spacer()

            if let limit = viewModel.selectedPlatform.characterLimit {
                Text("\(limit) chars")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Output")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.generatedContent.isEmpty {
                    HStack(spacing: 2) {
                        Text("\(viewModel.characterCount)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(viewModel.isOverLimit ? .red : .secondary)
                        if let limit = viewModel.selectedPlatform.characterLimit {
                            Text("/ \(limit)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if viewModel.isGenerating {
                VStack(alignment: .leading) {
                    Text(viewModel.streamingText)
                        .font(.caption)
                        .textSelection(.enabled)
                    ProgressView()
                        .controlSize(.mini)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .cornerRadius(6)
            } else {
                Text(viewModel.generatedContent)
                    .font(.caption)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(viewModel.isOverLimit ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            }

            // Actions
            if !viewModel.generatedContent.isEmpty && !viewModel.isGenerating {
                HStack(spacing: 8) {
                    Button { viewModel.copyToClipboard() } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy")

                    Button { viewModel.generate() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Regenerate")

                    Button { viewModel.clearContent() } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
    }
}
