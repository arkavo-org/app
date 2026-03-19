import MuseCore
import SwiftUI

/// Private overlay panel for the Producer role — slides in from trailing edge in Studio
struct ProducerPanelView: View {
    var viewModel: ProducerViewModel
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.streamState.isLive ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Producer")
                        .font(.headline)
                }

                Spacer()

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
                    // Stream Health
                    streamHealthSection

                    Divider()

                    // Quick Actions
                    quickActionsSection

                    Divider()

                    // Suggestions
                    suggestionsSection
                }
                .padding(16)
            }
        }
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle().frame(width: 1).foregroundColor(.white.opacity(0.1)),
            alignment: .leading
        )
    }

    // MARK: - Stream Health

    private var streamHealthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stream Health")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if viewModel.streamState.isLive {
                HStack(spacing: 16) {
                    statItem(
                        icon: "eye.fill",
                        value: "\(viewModel.streamState.viewerCount)",
                        label: "viewers"
                    )
                    statItem(
                        icon: "clock.fill",
                        value: formatDuration(viewModel.streamState.streamDuration),
                        label: "uptime"
                    )
                }

                HStack(spacing: 4) {
                    Text("Sentiment:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    sentimentIndicator(viewModel.streamState.chatSentiment)
                }
            } else {
                Text("Not streaming")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sentimentIndicator(_ value: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: value < 0.3 ? "face.dashed" : value < 0.7 ? "face.smiling" : "face.smiling.fill")
                .font(.caption)
                .foregroundStyle(value < 0.3 ? .red : value < 0.7 ? .yellow : .green)
            Text(value < 0.3 ? "Negative" : value < 0.7 ? "Neutral" : "Positive")
                .font(.caption)
                .foregroundStyle(value < 0.3 ? .red : value < 0.7 ? .yellow : .green)
        }
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Actions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickActionButton("Break", icon: "cup.and.saucer") {
                    viewModel.generateSuggestion(prompt: "Suggest a good time to take a break based on stream state.")
                }
                quickActionButton("Scene", icon: "rectangle.on.rectangle") {
                    viewModel.generateSuggestion(prompt: "Suggest the next scene change based on current activity.")
                }
                quickActionButton("Raid", icon: "person.wave.2") {
                    viewModel.generateSuggestion(prompt: "Suggest a good raid target and timing.")
                }
            }
        }
    }

    private func quickActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGenerating || !viewModel.modelManager.isReady)
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggestions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            if viewModel.suggestions.isEmpty {
                Text("No suggestions yet. Use quick actions or wait for auto-suggestions.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.suggestions.prefix(10)) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: ProducerSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(suggestion.category.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(categoryColor(suggestion.category))
                Spacer()
                Text(suggestion.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(suggestion.text)
                .font(.caption)
                .lineLimit(4)
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .cornerRadius(8)
    }

    private func categoryColor(_ category: ProducerSuggestion.Category) -> Color {
        switch category {
        case .alert: .red
        case .suggestion: .blue
        case .info: .secondary
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}
