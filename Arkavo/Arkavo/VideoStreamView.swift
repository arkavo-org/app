import SwiftUI
import AVFoundation
import CryptoKit
import Combine

struct VideoStreamView: View {
    @ObservedObject var viewModel: VideoStreamViewModel
    @StateObject private var videoCaptureManager = VideoCaptureManager()
    @State private var commentText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            VideoPreviewArea(
                videoCaptureManager: videoCaptureManager,
                incomingVideoViewModel: viewModel
            )
            ControlButtons(
                videoCaptureManager: videoCaptureManager,
                toggleCamera: toggleCamera,
                toggleStreaming: toggleStreaming
            )
            CommentInputArea(
                commentText: $commentText,
                isInputFocused: _isInputFocused,
                sendComment: sendComment
            )
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
        .onReceive(videoCaptureManager.$error) { error in
            if let error = error {
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
        // Force view update
        videoCaptureManager.objectWillChange.send()
    }

    private func sendComment() {
        print("Sending comment: \(commentText)")
        commentText = ""
    }
}

struct VideoPreviewArea: View {
    @ObservedObject var videoCaptureManager: VideoCaptureManager
    var incomingVideoViewModel: VideoStreamViewModel

    var body: some View {
        HStack {
            CameraPreviewView(videoCaptureManager: videoCaptureManager)
                .frame(height: UIScreen.main.bounds.height * 0.2)
                .overlay(StreamingIndicator(isStreaming: videoCaptureManager.isStreaming))
            
            IncomingVideoView(viewModel: incomingVideoViewModel)
                .frame(height: UIScreen.main.bounds.height * 0.2)
        }
        .frame(height: UIScreen.main.bounds.height * 0.2)
    }
}

struct StreamingIndicator: View {
    var isStreaming: Bool

    var body: some View {
        if isStreaming {
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
}

struct ControlButtons: View {
    @ObservedObject var videoCaptureManager: VideoCaptureManager
    var toggleCamera: () -> Void
    var toggleStreaming: () -> Void

    var body: some View {
        HStack {
            Button(action: toggleCamera) {
                Label(
                    videoCaptureManager.isCameraActive ? "Stop Camera" : "Start Camera",
                    systemImage: videoCaptureManager.isCameraActive ? "video.slash.fill" : "video.fill"
                )
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            Button(action: toggleStreaming) {
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
    }
}

struct CommentInputArea: View {
    @Binding var commentText: String
    @FocusState var isInputFocused: Bool
    var sendComment: () -> Void

    var body: some View {
        HStack {
            TextField("Type a comment", text: $commentText)
                .focused($isInputFocused)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading)

            Button(action: sendComment) {
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
}

struct ControlButton: View {
    let action: () -> Void
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .padding()
                .background(color)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
    }
}

struct IncomingVideoView: UIViewRepresentable {
    @ObservedObject var viewModel: VideoStreamViewModel

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = viewModel.currentFrame
    }
}

struct CameraPreviewView: View {
    @ObservedObject var videoCaptureManager: VideoCaptureManager

    var body: some View {
        ZStack {
            CameraPreview(videoCaptureManager: videoCaptureManager)
                .opacity(videoCaptureManager.isCameraActive ? 1 : 0)
            
            if !videoCaptureManager.isCameraActive {
                Text("Camera is inactive")
                    .foregroundColor(.secondary)
            }

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
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var videoCaptureManager: VideoCaptureManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        DispatchQueue.main.async {
            if let layer = videoCaptureManager.previewLayer {
                layer.frame = view.bounds
                view.layer.addSublayer(layer)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if let layer = videoCaptureManager.previewLayer {
                layer.frame = uiView.bounds
                if layer.superlayer == nil {
                    uiView.layer.addSublayer(layer)
                }
            }
        }
    }
}

class VideoStreamViewModel: ObservableObject {
    @Published var webSocketManager: WebSocketManager
    var nanoTDFManager: NanoTDFManager
    @Binding var kasPublicKey: P256.KeyAgreement.PublicKey?
    private var cancellables = Set<AnyCancellable>()

    @Published var currentFrame: UIImage?
    private var videoDecoder: VideoDecoder?

    init() {
        _webSocketManager = .init(initialValue: WebSocketManager())
        _kasPublicKey = .constant(nil)
        nanoTDFManager = NanoTDFManager()
        videoDecoder = VideoDecoder()
    }

    func initialize(
        webSocketManager: WebSocketManager,
        nanoTDFManager: NanoTDFManager,
        kasPublicKey: Binding<P256.KeyAgreement.PublicKey?>
    ) {
        self.webSocketManager = webSocketManager
        _kasPublicKey = kasPublicKey
        self.nanoTDFManager = nanoTDFManager
    }

    func receiveVideoFrame(_ frameData: Data) {
        videoDecoder?.decodeFrame(frameData) { [weak self] image in
            DispatchQueue.main.async {
                self?.currentFrame = image
            }
        }
    }
}
