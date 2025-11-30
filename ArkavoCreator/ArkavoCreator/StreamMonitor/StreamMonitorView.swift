import SwiftUI

/// Main SwiftUI view for the stream monitor window.
/// Displays the final composed frame with optional statistics overlay.
struct StreamMonitorView: View {
    @ObservedObject var viewModel: StreamMonitorViewModel
    @AppStorage("streamMonitor.showStats") private var showStats = true
    @AppStorage("streamMonitor.alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        ZStack {
            // Background
            Color.black

            // Frame display
            if let image = viewModel.latestFrameImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // No frame placeholder
                VStack(spacing: 16) {
                    Image(systemName: "tv")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No stream output")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Start recording or streaming to see preview")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Stats overlay (top-left)
            if showStats, let stats = viewModel.streamStats {
                VStack(alignment: .leading, spacing: 4) {
                    StatsOverlay(stats: stats, isLive: viewModel.isLive)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }

            // Live indicator (top-right)
            if viewModel.isLive {
                HStack(spacing: 6) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("LIVE")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.red.opacity(0.8))
                .cornerRadius(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $showStats) {
                    Image(systemName: "chart.bar")
                }
                .help("Toggle Statistics Overlay")

                Toggle(isOn: $alwaysOnTop) {
                    Image(systemName: "pin")
                }
                .help("Always on Top")
                .onChange(of: alwaysOnTop) { _, newValue in
                    StreamMonitorWindow.shared.setAlwaysOnTop(newValue)
                }
            }
        }
    }
}

/// Statistics overlay showing stream metrics.
private struct StatsOverlay: View {
    let stats: StreamStatistics
    let isLive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Duration
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(stats.formattedDuration)
                    .font(.caption.monospacedDigit())
            }

            // FPS
            HStack(spacing: 4) {
                Image(systemName: "speedometer")
                    .font(.caption2)
                Text("\(stats.fps, specifier: "%.1f") fps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(stats.fps >= 28 ? .green : (stats.fps >= 20 ? .yellow : .red))
            }

            // Bitrate (if streaming)
            if isLive {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle")
                        .font(.caption2)
                    Text(stats.formattedBitrate)
                        .font(.caption.monospacedDigit())
                }

                // Dropped frames
                if stats.droppedFrames > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption2)
                        Text("\(stats.droppedFrames) dropped")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .padding(8)
        .background(.black.opacity(0.6))
        .cornerRadius(6)
        .foregroundStyle(.white)
    }
}

#Preview {
    StreamMonitorView(viewModel: StreamMonitorViewModel.shared)
        .frame(width: 640, height: 400)
}
