import AVFoundation
import Combine
import SwiftUI

struct VideoStreamView: View {
    @ObservedObject var viewModel: VideoStreamViewModel
    @State private var isStreaming = false
    @State private var isCameraActive = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Video preview area
            if isCameraActive {
                CameraPreview(videoCaptureManager: viewModel.videoCaptureManager)
                    .edgesIgnoringSafeArea(.all)
                    .frame(height: 300)
            } else {
                Text("Camera is inactive")
                    .frame(height: 300)
            }

            // Control buttons
            HStack {
                Button(action: {
                    toggleCamera()
                }) {
                    Text(isCameraActive ? "stopcamera" : "startcamera")
                        .padding()
                }
                Button(action: {
                    toggleStreaming()
                }) {
                    Text(isStreaming ? "Stop Streaming" : "Streaming...")
                        .padding()
                }
                .disabled(!isCameraActive)
            }
            .padding()

            // Input area for video metadata or comments
            HStack {
                TextField("Type a comment", text: $viewModel.commentText)
                    .focused($isInputFocused)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)

                Button(action: {
                    viewModel.sendComment()
                }) {
                    Text("Send")
                }
                .padding(.trailing)
                .disabled(viewModel.commentText.isEmpty)
            }
            .padding()
        }
    }

    private func toggleCamera() {
        if isCameraActive {
            viewModel.stopCamera()
        } else {
            viewModel.startCamera()
        }
        isCameraActive.toggle()
    }

    private func toggleStreaming() {
        if isStreaming {
            viewModel.stopStreaming()
        } else {
            viewModel.startStreaming()
        }
        isStreaming.toggle()
    }
}

class VideoStreamViewModel: ObservableObject {
    @Published var videoCaptureManager = VideoCaptureManager()
    @Published var commentText = ""

    func startCamera() {
        videoCaptureManager.checkCameraPermissions()
    }

    func stopCamera() {
        videoCaptureManager.stopCapture()
    }

    func startStreaming() {
        // Add logic to start video streaming
    }

    func stopStreaming() {
        // Add logic to stop video streaming
    }

    func sendComment() {
        // Logic to send the comment
        commentText = ""
    }
}
