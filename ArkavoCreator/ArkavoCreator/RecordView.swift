import SwiftUI
import AVFoundation
import ArkavoRecorder

struct RecordView: View {
    @State private var viewModel = RecordViewModel()

    var body: some View {
        VStack(spacing: 24) {
            // Title section
            if !viewModel.isRecording {
                titleSection
            }

            Spacer()

            // Status display when recording
            if viewModel.isRecording {
                recordingStatusSection
            } else {
                setupPromptSection
            }

            Spacer()

            // Main control button
            controlButton

            // Error message
            if let error = viewModel.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Processing indicator
            if viewModel.isProcessing {
                ProgressView("Finishing recording...")
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .navigationTitle("Record")
    }

    // MARK: - View Components

    private var titleSection: some View {
        VStack(spacing: 8) {
            Text("Recording Title")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Enter title", text: $viewModel.title)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 400)
        }
    }

    private var setupPromptSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "record.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Ready to Record")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Screen + Camera + Microphone")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Quick settings
            VStack(spacing: 12) {
                Toggle("Enable Camera", isOn: $viewModel.enableCamera)
                Toggle("Enable Microphone", isOn: $viewModel.enableMicrophone)

                if viewModel.enableCamera {
                    Picker("Camera Position", selection: $viewModel.pipPosition) {
                        ForEach(PiPPosition.allCases) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                }
            }
            .frame(maxWidth: 300)
        }
    }

    private var recordingStatusSection: some View {
        VStack(spacing: 20) {
            // Recording indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isPaused ? Color.orange : Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(viewModel.isPaused ? 1.0 : (pulsing ? 1.0 : 0.3))

                Text(viewModel.isPaused ? "PAUSED" : "RECORDING")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.isPaused ? .orange : .red)
            }

            // Duration
            Text(viewModel.formattedDuration())
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.primary)

            // Audio level indicator
            if viewModel.enableMicrophone {
                VStack(spacing: 4) {
                    Text("Microphone Level")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))

                            // Level bar
                            RoundedRectangle(cornerRadius: 4)
                                .fill(levelColor(for: viewModel.audioLevelPercentage()))
                                .frame(width: geometry.size.width * viewModel.audioLevelPercentage())
                        }
                    }
                    .frame(height: 8)
                }
                .frame(maxWidth: 300)
            }

            // Pause/Resume button
            Button(action: {
                if viewModel.isPaused {
                    Task {
                        viewModel.resumeRecording()
                    }
                } else {
                    viewModel.pauseRecording()
                }
            }) {
                Label(viewModel.isPaused ? "Resume" : "Pause", systemImage: viewModel.isPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(.bordered)
        }
    }

    private var controlButton: some View {
        Button(action: {
            Task {
                if viewModel.isRecording {
                    await viewModel.stopRecording()
                } else {
                    await viewModel.startRecording()
                }
            }
        }) {
            Label(
                viewModel.isRecording ? "Stop Recording" : "Start Recording",
                systemImage: viewModel.isRecording ? "stop.circle.fill" : "record.circle.fill"
            )
            .font(.title3)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isRecording ? .red : .blue)
        .disabled(viewModel.isProcessing)
    }

    // MARK: - Helpers

    @State private var pulsing = false

    private var pulseAnimation: Animation {
        Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }

    private func levelColor(for level: Double) -> Color {
        if level < 0.5 {
            return .green
        } else if level < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}

// Start pulsing animation when view appears
extension RecordView {
    private var recordingIndicatorView: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 12, height: 12)
            .opacity(pulsing ? 1.0 : 0.3)
            .onAppear {
                withAnimation(pulseAnimation) {
                    pulsing = true
                }
            }
    }
}

#Preview {
    NavigationStack {
        RecordView()
    }
}
