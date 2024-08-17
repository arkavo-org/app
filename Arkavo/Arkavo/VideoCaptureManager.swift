import AVFoundation
import SwiftUI

class VideoCaptureManager: NSObject, ObservableObject {
    private var captureSession: AVCaptureSession?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var hasCameraAccess = false

    func checkCameraPermissions() {
        let cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch cameraAuthStatus {
        case .authorized:
            hasCameraAccess = true
            startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.hasCameraAccess = granted
                    if granted {
                        self.startCapture()
                    }
                }
            }
        case .denied, .restricted:
            hasCameraAccess = false
        @unknown default:
            hasCameraAccess = false
        }
    }

    func startCapture() {
        // Initialize the AVCaptureSession
        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high

        // Set up the capture device
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("No video device available")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession?.canAddInput(videoInput) == true {
                captureSession?.addInput(videoInput)
            }

            // Set up the preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
            previewLayer.videoGravity = .resizeAspectFill
            self.previewLayer = previewLayer

            // Start the session
            DispatchQueue.global(qos: .userInitiated).async {
                // Start the session in the background thread
                self.captureSession?.startRunning()
            }

        } catch {
            print("Error setting up video capture: \(error)")
        }
    }

    func stopCapture() {
        captureSession?.stopRunning()
    }
}
