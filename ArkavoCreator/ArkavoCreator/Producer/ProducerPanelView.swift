import MuseCore
import SwiftUI

/// Unified Producer panel — command center with stream health, actions, suggestions, and chat feed
struct ProducerPanelView: View {
    var viewModel: ProducerViewModel
    @Binding var isVisible: Bool
    var chatViewModel: ChatPanelViewModel?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.modelManager.isReady ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text("Producer")
                        .font(.headline)
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
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

            // Sections 1-3: Health, Actions, Suggestions (fixed height, scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    streamHealthSection
                    Divider()
                    quickActionsSection
                    Divider()
                    suggestionsSection
                }
                .padding(16)
            }
            .frame(maxHeight: 320)

            Divider()

            // Section 4: Chat Monitor (fills remaining space)
            if let chatVM = chatViewModel {
                chatMonitorSection(chatVM)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("Chat appears when streaming")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Chat Monitor

    @ViewBuilder
    private func chatMonitorSection(_ chatVM: ChatPanelViewModel) -> some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Circle()
                    .fill(chatVM.isConnected ? Color.green : Color.gray)
                    .frame(width: 6, height: 6)
                Text("Chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(chatVM.messages.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            // Dense chat feed
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(chatVM.messages) { message in
                            Text("\(Text(message.displayName).bold()): \(message.content)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .lineLimit(2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1)
                                .id(message.id)
                        }
                    }
                }
                .onChange(of: chatVM.messages.count) { _, _ in
                    if let lastID = chatVM.messages.last?.id {
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
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
