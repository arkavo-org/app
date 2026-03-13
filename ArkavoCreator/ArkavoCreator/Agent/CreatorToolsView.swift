import ArkavoKit
import SwiftUI

/// Quick-action AI tools for creators
struct CreatorToolsView: View {
    @ObservedObject var agentService: CreatorAgentService
    @State private var selectedTool: CreatorTool?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Creator AI Tools")
                    .font(.headline)

                Text("Quick-action tools that use AI to help you create content.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
                    ForEach(CreatorTool.allCases) { tool in
                        ToolCard(tool: tool) {
                            selectedTool = tool
                        }
                    }
                }
            }
            .padding()
        }
        .sheet(item: $selectedTool) { tool in
            ToolFormView(
                agentService: agentService,
                tool: tool
            )
            .frame(minWidth: 500, minHeight: 400)
        }
    }
}

// MARK: - Creator Tool Enum

enum CreatorTool: String, CaseIterable, Identifiable {
    case draftPost = "Draft Social Post"
    case streamTitle = "Generate Stream Title"
    case describeRecording = "Describe Recording"
    case analyzeContent = "Analyze Content"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .draftPost: "square.and.pencil"
        case .streamTitle: "sparkles.tv"
        case .describeRecording: "doc.text.magnifyingglass"
        case .analyzeContent: "chart.bar.doc.horizontal"
        }
    }

    var description: String {
        switch self {
        case .draftPost: "Generate a platform-optimized social media post"
        case .streamTitle: "Create a catchy stream title with tags"
        case .describeRecording: "Write a video description with SEO tags"
        case .analyzeContent: "Analyze text for sentiment, reading level, and themes"
        }
    }

    var color: Color {
        switch self {
        case .draftPost: .blue
        case .streamTitle: .purple
        case .describeRecording: .orange
        case .analyzeContent: .green
        }
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let tool: CreatorTool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: tool.icon)
                    .font(.title2)
                    .foregroundColor(tool.color)

                Text(tool.rawValue)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(tool.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tool Form View

struct ToolFormView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var agentService: CreatorAgentService

    let tool: CreatorTool

    // Form state
    @State private var platform = "Bluesky"
    @State private var tone = "professional"
    @State private var topic = ""
    @State private var game = ""
    @State private var context = ""
    @State private var textContent = ""

    // Result state
    @State private var result = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var chatSession: ChatSession?

    private let platforms = ["Bluesky", "Reddit", "Patreon", "YouTube", "Micro.blog"]
    private let tones = ["professional", "casual", "enthusiastic", "informative", "humorous"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: tool.icon)
                    .foregroundColor(tool.color)
                Text(tool.rawValue)
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Form fields
                    formContent

                    // Generate button
                    Button(action: { Task { await generate() } }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoading ? "Generating..." : "Generate")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || !isFormValid)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    // Result
                    if !result.isEmpty {
                        resultView
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Form Content

    @ViewBuilder
    private var formContent: some View {
        switch tool {
        case .draftPost:
            Picker("Platform", selection: $platform) {
                ForEach(platforms, id: \.self) { Text($0) }
            }
            Picker("Tone", selection: $tone) {
                ForEach(tones, id: \.self) { Text($0.capitalized) }
            }
            TextField("Topic", text: $topic)
                .textFieldStyle(.roundedBorder)

        case .streamTitle:
            TextField("Game / Category", text: $game)
                .textFieldStyle(.roundedBorder)
            TextField("Topic / Theme", text: $topic)
                .textFieldStyle(.roundedBorder)

        case .describeRecording:
            TextField("Recording context (what happened, key moments)", text: $context, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

        case .analyzeContent:
            TextField("Paste content to analyze", text: $textContent, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(5...10)
        }
    }

    private var isFormValid: Bool {
        switch tool {
        case .draftPost: !topic.isEmpty
        case .streamTitle: !topic.isEmpty
        case .describeRecording: !context.isEmpty
        case .analyzeContent: !textContent.isEmpty
        }
    }

    // MARK: - Result View

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Result")
                    .font(.headline)
                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            Text(result)
                .font(.body)
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Generate

    private func generate() async {
        isLoading = true
        errorMessage = nil
        result = ""

        do {
            // Find a connected agent to use
            guard let agent = agentService.discoveredAgents.first(where: {
                agentService.isConnected(to: $0.id)
            }) else {
                errorMessage = "No connected agent. Connect to an agent first."
                isLoading = false
                return
            }

            // Open a session if needed
            let session: ChatSession
            if let existing = chatSession {
                session = existing
            } else {
                session = try await agentService.openChatSession(with: agent.id)
                chatSession = session
            }

            // Set up observation for streaming response
            let sessionId = session.id

            // Send the appropriate request
            switch tool {
            case .draftPost:
                try await agentService.draftSocialPost(
                    platform: platform,
                    tone: tone,
                    topic: topic,
                    sessionId: sessionId
                )
            case .streamTitle:
                try await agentService.generateStreamTitle(
                    game: game,
                    topic: topic,
                    sessionId: sessionId
                )
            case .describeRecording:
                try await agentService.describeRecording(
                    context: context,
                    sessionId: sessionId
                )
            case .analyzeContent:
                try await agentService.analyzeContent(
                    text: textContent,
                    sessionId: sessionId
                )
            }

            // Wait for streaming to complete
            for _ in 0..<600 { // 60 second timeout
                try await Task.sleep(nanoseconds: 100_000_000)

                if let streamingState = agentService.streamingStates[sessionId], !streamingState {
                    // Stream ended, get final text
                    if let text = agentService.finalizeStream(sessionId: sessionId) {
                        result = text
                    }
                    break
                }

                // Update with streaming text
                if let text = agentService.streamingText[sessionId], !text.isEmpty {
                    result = text
                }
            }

            if result.isEmpty {
                errorMessage = "No response received from agent."
            }
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
