import MuseCore
import SwiftUI

/// Content creation workspace for the Publicist role
struct PublicistView: View {
    @Bindable var viewModel: PublicistViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with model status
            modelStatusBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Platform selector
                    platformSelector

                    // Content type selector
                    contentTypeSelector

                    // Source input
                    sourceInputSection

                    // Generate button
                    generateButton

                    // Output
                    if !viewModel.generatedContent.isEmpty || viewModel.isGenerating {
                        outputSection
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Model Status

    private var modelStatusBar: some View {
        HStack(spacing: 8) {
            switch viewModel.modelManager.state {
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                Text(viewModel.modelManager.selectedModel.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .downloading(let progress):
                ProgressView(value: progress)
                    .frame(width: 80)
                    .controlSize(.small)
                Text("Downloading \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .loading:
                ProgressView()
                    .controlSize(.mini)
                Text("Loading \(viewModel.modelManager.selectedModel.displayName)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

            case .idle, .unloaded:
                if viewModel.modelManager.isSelectedModelCached {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text("\(viewModel.modelManager.selectedModel.displayName) — cached")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Model not downloaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            modelActionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var modelActionButton: some View {
        switch viewModel.modelManager.state {
        case .idle, .unloaded, .error:
            Button("Load Model") {
                Task { await viewModel.modelManager.loadSelectedModel() }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        case .downloading, .loading:
            Button("Cancel", role: .cancel) {
                Task { await viewModel.modelManager.unloadModel() }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        case .ready:
            EmptyView()
        }
    }

    // MARK: - Platform Selector

    private var platformSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Platform")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PublicistPlatform.allCases, id: \.self) { platform in
                        let isSelected = viewModel.selectedPlatform == platform
                        Button {
                            viewModel.selectedPlatform = platform
                        } label: {
                            Text(platform.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("Platform_\(platform.rawValue)")
                    }
                }
            }
        }
    }

    // MARK: - Content Type Selector

    private var contentTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content Type")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(PublicistContentType.allCases, id: \.self) { type in
                    let isSelected = viewModel.selectedContentType == type
                    Button {
                        viewModel.selectedContentType = type
                    } label: {
                        Text(type.rawValue)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary))
                            .foregroundStyle(isSelected ? Color.accentColor : .primary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ContentType_\(type.rawValue)")
                }
            }
        }
    }

    // MARK: - Source Input

    private var sourceInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source (optional)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.sourceText)
                .font(.body)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(8)
                .background(.quaternary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                )

            Text("Paste text, topic, or leave empty for a general draft")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        HStack {
            if viewModel.isGenerating {
                Button("Stop") {
                    viewModel.stopGeneration()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .accessibilityIdentifier("Btn_Stop")
            } else {
                Button("Generate") {
                    viewModel.generate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!viewModel.modelManager.isReady)
                .accessibilityIdentifier("Btn_Generate")
            }

            Spacer()

            if let limit = viewModel.selectedPlatform.characterLimit {
                Text("\(limit) char limit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Output Section

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !viewModel.generatedContent.isEmpty {
                    // Character count
                    HStack(spacing: 4) {
                        Text("\(viewModel.characterCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(viewModel.isOverLimit ? .red : .secondary)
                        if let limit = viewModel.selectedPlatform.characterLimit {
                            Text("/ \(limit)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            if viewModel.isGenerating {
                VStack(alignment: .leading) {
                    Text(viewModel.streamingText)
                        .font(.body)
                        .textSelection(.enabled)
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary)
                .cornerRadius(8)
            } else {
                Text(viewModel.generatedContent)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(viewModel.isOverLimit ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            }

            // Action buttons
            if !viewModel.generatedContent.isEmpty && !viewModel.isGenerating {
                HStack(spacing: 12) {
                    Button {
                        viewModel.copyToClipboard()
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.generate()
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        viewModel.clearContent()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}
