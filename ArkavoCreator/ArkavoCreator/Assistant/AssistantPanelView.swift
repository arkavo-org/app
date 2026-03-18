import MuseCore
import SwiftUI

/// Compact floating panel for quick assistant access
struct AssistantPanelView: View {
    @Bindable var viewModel: AssistantViewModel

    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("AI Assistant", systemImage: "sparkles")
                    .font(.headline)
                Spacer()

                // Model status
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.modelManager.isReady ? .green : .gray)
                        .frame(width: 6, height: 6)
                    Text(viewModel.modelManager.selectedModel.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Recent messages (last 5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages.suffix(5)) { message in
                            PanelMessageRow(message: message)
                                .id(message.id)
                        }

                        if viewModel.isGenerating, !viewModel.streamingText.isEmpty {
                            PanelMessageRow(
                                message: AssistantMessage(role: .assistant, content: viewModel.streamingText)
                            )
                            .id("streaming")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastID = viewModel.messages.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(AssistantAction.allCases.prefix(4), id: \.self) { action in
                        Button(action.rawValue) {
                            viewModel.performAction(action)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(!viewModel.modelManager.isReady || viewModel.isGenerating)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            // Input
            HStack(spacing: 8) {
                TextField("Ask something...", text: $inputText)
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }

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
        .frame(width: 400, height: 500)
        .onAppear {
            isInputFocused = true
        }
    }

    private func sendMessage() {
        let text = inputText
        inputText = ""
        viewModel.send(message: text)
    }
}

// MARK: - Panel Message Row

private struct PanelMessageRow: View {
    let message: AssistantMessage

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            switch message.role {
            case .user:
                Image(systemName: "person.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            case .assistant:
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
                    .font(.caption)
            case .system:
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Text(message.content)
                .font(.callout)
                .textSelection(.enabled)
                .foregroundStyle(message.role == .system ? .secondary : .primary)

            Spacer(minLength: 20)
        }
    }
}
