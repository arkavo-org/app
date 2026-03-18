import MuseCore
import SwiftUI

/// Full AI assistant chat view for the Assistant section
struct AssistantChatView: View {
    @Bindable var viewModel: AssistantViewModel

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Model status bar
            modelStatusBar

            // Platform context indicator
            platformContextBar

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming indicator
                        if viewModel.isGenerating, !viewModel.streamingText.isEmpty {
                            MessageBubble(
                                message: AssistantMessage(role: .assistant, content: viewModel.streamingText)
                            )
                            .id("streaming")
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation {
                        if let lastID = viewModel.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.streamingText) {
                    if viewModel.isGenerating {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Quick actions
            quickActionsBar

            // Input bar
            inputBar
        }
    }

    // MARK: - Components

    private var modelStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // Model picker
            Menu {
                ForEach(viewModel.modelManager.availableModels) { model in
                    Button {
                        Task { await viewModel.modelManager.selectModel(model) }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if model == viewModel.modelManager.selectedModel {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.modelManager.selectedModel.displayName)
                        .font(.caption)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Load/unload button
            if viewModel.modelManager.state == .idle || viewModel.modelManager.state == .error("") || isUnloaded {
                Button("Load") {
                    Task { await viewModel.modelManager.loadSelectedModel() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var isUnloaded: Bool {
        if case .unloaded = viewModel.modelManager.state { return true }
        return false
    }

    private var statusColor: Color {
        switch viewModel.modelManager.state {
        case .ready: .green
        case .loading, .downloading: .orange
        case .error: .red
        default: .gray
        }
    }

    private var statusText: String {
        switch viewModel.modelManager.state {
        case .idle: "Model not loaded"
        case .downloading(let progress): "Downloading \(Int(progress * 100))%"
        case .loading: "Loading model..."
        case .ready: "Ready"
        case .error(let msg): "Error: \(msg)"
        case .unloaded(let reason): reason
        }
    }

    private var platformContextBar: some View {
        let context = viewModel.modelManager.selectedModel.displayName
        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Local inference with \(context)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var quickActionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentActions, id: \.self) { action in
                    Button(action.rawValue) {
                        viewModel.performAction(action)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!viewModel.modelManager.isReady || viewModel.isGenerating)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    private var currentActions: [AssistantAction] {
        // Get actions from the current navigation context
        GenericContext().suggestedActions
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask the assistant...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit {
                    sendMessage()
                }

            if viewModel.isGenerating {
                Button {
                    viewModel.stopGeneration()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(inputText.isEmpty ? .gray : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
        }
        .padding()
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        viewModel.send(message: text)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(message.role == .system ? .caption : .body)
                    .foregroundStyle(message.role == .system ? .secondary : .primary)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 40)

            if message.role == .assistant {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var avatar: some View {
        switch message.role {
        case .user:
            Image(systemName: "person.circle.fill")
                .foregroundStyle(.blue)
                .font(.title3)
        case .assistant:
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
                .font(.title3)
        case .system:
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }
}
