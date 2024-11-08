#if os(iOS) || os(tvOS) || targetEnvironment(macCatalyst)
    import AVFoundation
    import Combine
    import CryptoKit
    import SwiftUI

    struct VideoStreamView: View {
        @StateObject var viewModel: VideoStreamViewModel
        @State private var commentText = ""
        @FocusState private var isInputFocused: Bool
        @State private var showingErrorAlert = false
        @State private var errorMessage = ""
        @StateObject private var videoCaptureViewController = VideoCaptureViewController()
        @State private var isShowingLocalVideo = true

        var body: some View {
            ZStack {
                if isShowingLocalVideo {
                    VideoPreviewArea(videoCaptureViewController: videoCaptureViewController, incomingVideoViewModel: viewModel)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    VideoIncomingArea(viewModel: viewModel)
                        .edgesIgnoringSafeArea(.all)
                }
                Spacer()
                HStack {
                    Button(action: toggleCamera) {
                        Label(
                            videoCaptureViewController.isCameraActive ? "Stop" : "Start",
                            systemImage: videoCaptureViewController.isCameraActive ? "video.slash.fill" : "video.fill"
                        )
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    Button(action: toggleStreaming) {
                        Label(
                            videoCaptureViewController.isStreaming ? "Stop" : "Share",
                            systemImage: videoCaptureViewController.isStreaming ? "stop.circle.fill" : "play.circle.fill"
                        )
                        .padding()
                        .background(videoCaptureViewController.isCameraActive ? Color.green : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(!videoCaptureViewController.isCameraActive)
                    Button(action: switchCamera) {
                        Image(systemName: "camera.rotate.fill")
                            .padding()
                            .background(Color.orange)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .disabled(!videoCaptureViewController.isCameraActive)
                    Button(action: toggleVideoSource) {
                        Image(systemName: isShowingLocalVideo ? "arrow.down.left.video.fill" : "video.fill")
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }

        private func toggleCamera() {
            if videoCaptureViewController.isCameraActive {
                // First stop streaming if it's active
                if videoCaptureViewController.isStreaming {
                    videoCaptureViewController.stopStreaming()
                }
                videoCaptureViewController.stopCapture()
            } else {
                videoCaptureViewController.startCapture()
            }
        }

        private func toggleStreaming() {
            if videoCaptureViewController.isStreaming {
                videoCaptureViewController.stopStreaming()
            } else {
                videoCaptureViewController.startStreaming(viewModel: viewModel)
            }
        }

        private func switchCamera() {
            videoCaptureViewController.switchCamera()
        }

        private func toggleVideoSource() {
            isShowingLocalVideo.toggle()
        }
    }

    struct VideoPreviewArea: View {
        @StateObject var videoCaptureViewController: VideoCaptureViewController
        var incomingVideoViewModel: VideoStreamViewModel

        var body: some View {
            // Use MockVideoPreviewArea for preview, actual implementation for runtime
            #if DEBUG
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                    MockVideoPreviewArea()
                } else {
                    VideoPreviewAreaImpl(videoCaptureViewController: videoCaptureViewController, incomingVideoViewModel: incomingVideoViewModel)
                }
            #else
                VideoPreviewAreaImpl(videoCaptureViewController: $videoCaptureViewController, incomingVideoViewModel: incomingVideoViewModel)
            #endif
        }
    }

    class VideoStreamViewModel: ObservableObject {
        private var cancellables = Set<AnyCancellable>()

        @Published var currentFrame: UIImage?
        private var videoDecoder: VideoDecoder
        private let frameProcessingQueue = DispatchQueue(label: "com.arkavo.frameProcessing", qos: .userInteractive)

        init() {
            videoDecoder = VideoDecoder()
        }

        func receiveVideoFrame(_ frameData: Data) {
            videoDecoder.decodeFrame(frameData) { [weak self] image in
                DispatchQueue.main.async {
                    self?.currentFrame = image
                }
            }
        }
    }

    struct VideoIncomingArea: View {
        @StateObject var viewModel: VideoStreamViewModel

        var body: some View {
            GeometryReader { geometry in
                if let image = viewModel.currentFrame {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Color.black
                }
            }
        }
    }

    // MARK: - Preview

    struct VideoStreamView_Previews: PreviewProvider {
        static var previews: some View {
            VideoStreamView(viewModel: MockVideoStreamViewModel())
        }
    }

    // MARK: - Mock ViewModel for Preview

    class MockVideoStreamViewModel: VideoStreamViewModel {
        override init() {
            super.init()
            // Initialize with mock data if needed
        }
    }

    // MARK: - Mock VideoPreviewArea for Preview

    struct MockVideoPreviewArea: View {
        var body: some View {
            Color.gray // Placeholder for video preview
        }
    }

    // Actual VideoPreviewArea implementation
    struct VideoPreviewAreaImpl: UIViewControllerRepresentable {
        @StateObject var videoCaptureViewController: VideoCaptureViewController
        var incomingVideoViewModel: VideoStreamViewModel

        func makeUIViewController(context _: Context) -> VideoCaptureViewController {
            videoCaptureViewController
        }

        func updateUIViewController(_: VideoCaptureViewController, context _: Context) {
            // Update the view controller if needed
        }
    }
#endif
