import AVFoundation
import SwiftUI
import UIKit

struct CameraPreview: UIViewRepresentable { // macOS: replace UIViewRepresentable with NSViewRepresentable
    @ObservedObject var videoCaptureManager: VideoCaptureManager

    func makeUIView(context _: Context) -> UIView {
        let view = UIView()
        if let previewLayer = videoCaptureManager.previewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context _: Context) {
        // Update the view's layout when needed
        if let previewLayer = videoCaptureManager.previewLayer {
            previewLayer.frame = uiView.bounds
        }
    }
}
