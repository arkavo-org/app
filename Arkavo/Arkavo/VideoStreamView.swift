import AVFoundation
import Combine
import SwiftUI

struct VideoStreamView: View {
    @StateObject private var videoCaptureManager = VideoCaptureManager()
    @State private var commentText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Video preview area
            ZStack {
                if videoCaptureManager.isCameraActive {
                    CameraPreview(videoCaptureManager: videoCaptureManager)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    Text("Camera is inactive")
                }
            }
            .frame(height: 300)

            // Control buttons
            HStack {
                Button(action: {
                    toggleCamera()
                }) {
                    Text(videoCaptureManager.isCameraActive ? "Stop Camera" : "Start Camera")
                        .padding()
                }
                Button(action: {
                    toggleStreaming()
                }) {
                    Text(videoCaptureManager.isStreaming ? "Stop Streaming" : "Start Streaming")
                        .padding()
                }
                .disabled(!videoCaptureManager.isCameraActive)
            }
            .padding()

            // Input area for video metadata or comments
            HStack {
                TextField("Type a comment", text: $commentText)
                    .focused($isInputFocused)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.leading)

                Button(action: {
                    sendComment()
                }) {
                    Text("Send")
                }
                .padding(.trailing)
                .disabled(commentText.isEmpty)
            }
            .padding()
        }
    }

    private func toggleCamera() {
        if videoCaptureManager.isCameraActive {
            videoCaptureManager.stopCapture()
        } else {
            videoCaptureManager.startCapture()
        }
    }

    private func toggleStreaming() {
        if videoCaptureManager.isStreaming {
            videoCaptureManager.stopStreaming()
        } else {
            videoCaptureManager.startStreaming()
        }
    }

    private func sendComment() {
        // Logic to send the comment
        print("Sending comment: \(commentText)")
        commentText = ""
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var videoCaptureManager: VideoCaptureManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.addSublayer(videoCaptureManager.previewLayer ?? AVCaptureVideoPreviewLayer())
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        updatePreviewLayer(uiView)
    }

    private func updatePreviewLayer(_ uiView: UIView) {
        if let layer = videoCaptureManager.previewLayer {
            layer.frame = uiView.bounds
            if layer.superlayer == nil {
                uiView.layer.addSublayer(layer)
            }
        } else {
            // Remove the preview layer if it exists but videoCaptureManager.previewLayer is nil
            uiView.layer.sublayers?.removeAll(where: { $0 is AVCaptureVideoPreviewLayer })
        }
    }
}
