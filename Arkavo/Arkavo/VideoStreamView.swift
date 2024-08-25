import AVFoundation
import Combine
import CryptoKit
import SwiftUI

struct VideoStreamView: View {
    @ObservedObject var viewModel: VideoStreamViewModel
    @StateObject private var videoCaptureManager = VideoCaptureManager()
    @State private var commentText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Video preview area
            ZStack {
                if videoCaptureManager.isCameraActive {
                    CameraPreview(videoCaptureManager: videoCaptureManager)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    Text("Camera is inactive")
                        .foregroundColor(.secondary)
                }

                // Streaming indicator
                if videoCaptureManager.isStreaming {
                    VStack {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                            Text("Live")
                                .foregroundColor(.white)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(4)
                        }
                        .padding(8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: UIScreen.main.bounds.height * 0.4)

            // Control buttons
            HStack {
                Button(action: {
                    toggleCamera()
                }) {
                    Label(
                        videoCaptureManager.isCameraActive ? "Stop Camera" : "Start Camera",
                        systemImage: videoCaptureManager.isCameraActive ? "video.slash.fill" : "video.fill"
                    )
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Button(action: {
                    toggleStreaming()
                }) {
                    Label(
                        videoCaptureManager.isStreaming ? "Stop Streaming" : "Start Streaming",
                        systemImage: videoCaptureManager.isStreaming ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .padding()
                    .background(videoCaptureManager.isCameraActive ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(8)
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(commentText.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.trailing)
                .disabled(commentText.isEmpty)
            }
            .padding()
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
        .onReceive(videoCaptureManager.$error) { error in
            if let error {
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
        .onAppear {
            videoCaptureManager.setKasPublicKeyBinding(viewModel.$kasPublicKey)
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
            videoCaptureManager.startStreaming(webSocketManager: viewModel.webSocketManager)
        }
    }

    private func sendComment() {
        print("Sending comment: \(commentText)")
        commentText = ""
    }
}

class VideoStreamViewModel: ObservableObject {
    // nano
    @Published var webSocketManager: WebSocketManager
    var nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var cancellables = Set<AnyCancellable>()

    init() {
        _webSocketManager = .init(initialValue: WebSocketManager())
        _kasPublicKey = .constant(nil)
        nanoTDFManager = NanoTDFManager()
    }

    func initialize(
        webSocketManager: WebSocketManager,
        nanoTDFManager: NanoTDFManager,
        kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>
    ) {
        self.webSocketManager = webSocketManager
        self.webSocketManager = webSocketManager
        _kasPublicKey = kasPublicKey
        self.nanoTDFManager = nanoTDFManager
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var videoCaptureManager: VideoCaptureManager

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.layer.addSublayer(videoCaptureManager.previewLayer ?? AVCaptureVideoPreviewLayer())
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        DispatchQueue.main.async {
            updatePreviewLayer(uiView)
        }
    }

    private func updatePreviewLayer(_ uiView: UIView) {
        if let layer = videoCaptureManager.previewLayer {
            layer.frame = uiView.bounds
            if layer.superlayer == nil {
                uiView.layer.addSublayer(layer)
            }
        } else {
            uiView.layer.sublayers?.removeAll(where: { $0 is AVCaptureVideoPreviewLayer })
        }
    }
}
