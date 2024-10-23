import CoreML
import SwiftUI
import UIKit
import Vision

class AgeVerificationManager: ObservableObject {
    @Published var verificationStatus: AgeVerificationStatus = .unverified
    @Published var isVerifying = false
    @Published var showingScanner = false
    let idVerificationManager = IDCardVerificationManager()

    func startVerification() {
        isVerifying = true
        verificationStatus = .pending
        showingScanner = true
    }

    func presentIDCardScanner() {
        showingScanner = true
    }
}

// MARK: - Error Handling

enum IDVerificationError: Error {
    case imageConversionFailed
    case faceDetectionFailed
    case textExtractionFailed
    case noFaceFound
    case multipleFacesFound
    case comparisonFailed
}

// MARK: - ID Card Data Structure

struct IDCardData {
    var fullName: String?
    var dateOfBirth: String?
    var idNumber: String?
    var faceImage: UIImage?
    var cardBounds: CGRect?
}

// MARK: - ID Card Verification Manager

class IDCardVerificationManager {
    // MARK: - Properties

    private let minimumTextConfidence: Float = 0.7
    private let similarityThreshold: Float = 0.8

    // MARK: - Main Processing Methods

    func compareFaces(idCardImage: UIImage, selfieImage: UIImage) async throws -> Bool {
        let idFaceRequest = VNDetectFaceRectanglesRequest()
        let selfieFaceRequest = VNDetectFaceRectanglesRequest()

        // Process both images
        guard let idCGImage = idCardImage.cgImage,
              let selfieCGImage = selfieImage.cgImage
        else {
            throw IDVerificationError.imageConversionFailed
        }

        await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try VNImageRequestHandler(cgImage: idCGImage, options: [:])
                    .perform([idFaceRequest])
            }
            group.addTask {
                try VNImageRequestHandler(cgImage: selfieCGImage, options: [:])
                    .perform([selfieFaceRequest])
            }
        }

        // Compare faces using face landmarks
        return try await compareFaceLandmarks(
            idFaces: idFaceRequest.results ?? [],
            selfieFaces: selfieFaceRequest.results ?? []
        )
    }

    // MARK: - Helper Methods

    private func detectCardBoundaries(handler: VNImageRequestHandler, idCardData: inout IDCardData) async throws {
        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumSize = 0.7 // Card should occupy at least 70% of the image

        try handler.perform([rectangleRequest])

        guard let result = rectangleRequest.results?.first else {
            throw IDVerificationError.imageConversionFailed
        }

        idCardData.cardBounds = result.boundingBox
    }

    private func extractText(handler: VNImageRequestHandler, idCardData: inout IDCardData) async throws {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true

        try handler.perform([textRequest])

        guard let results = textRequest.results else {
            throw IDVerificationError.textExtractionFailed
        }

        // Process text results
        for result in results {
            guard let text = result.topCandidates(1).first?.string,
                  result.confidence >= minimumTextConfidence else { continue }

            // Classify and store text based on patterns
            if let idNumber = extractIDNumber(from: text) {
                idCardData.idNumber = idNumber
            } else if let dateOfBirth = extractDateOfBirth(from: text) {
                idCardData.dateOfBirth = dateOfBirth
            } else if let name = extractName(from: text) {
                idCardData.fullName = name
            }
        }
    }

    private func detectFace(handler: VNImageRequestHandler, idCardData: inout IDCardData, originalImage: UIImage) async throws {
        let faceRequest = VNDetectFaceLandmarksRequest()

        try handler.perform([faceRequest])

        guard let faces = faceRequest.results,
              !faces.isEmpty
        else {
            throw IDVerificationError.noFaceFound
        }

        if faces.count > 1 {
            throw IDVerificationError.multipleFacesFound
        }

        // Extract face image using the original image
        if let face = faces.first,
           let cgImage = originalImage.cgImage
        {
            let faceRect = face.boundingBox

            // Convert normalized coordinates to pixel coordinates
            let pixelRect = VNImageRectForNormalizedRect(
                faceRect,
                Int(cgImage.width),
                Int(cgImage.height)
            )

            // Crop the face region
            if let croppedCGImage = cgImage.cropping(to: pixelRect) {
                idCardData.faceImage = UIImage(cgImage: croppedCGImage)
            }
        }
    }

    func processIDCard(image: UIImage) async throws -> IDCardData {
        guard let cgImage = image.cgImage else {
            throw IDVerificationError.imageConversionFailed
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var idCardData = IDCardData()

        // Detect card boundaries
        try await detectCardBoundaries(handler: handler, idCardData: &idCardData)

        // Extract text
        try await extractText(handler: handler, idCardData: &idCardData)

        // Detect and extract face - now passing the original image
        try await detectFace(handler: handler, idCardData: &idCardData, originalImage: image)

        return idCardData
    }

    private func compareFaceLandmarks(idFaces: [VNFaceObservation], selfieFaces: [VNFaceObservation]) async throws -> Bool {
        guard let idFace = idFaces.first, let selfieFace = selfieFaces.first else {
            throw IDVerificationError.comparisonFailed
        }

        // Compare facial landmarks and calculate similarity score
        // This is a simplified example - in production, you'd want more sophisticated comparison
        let similarityScore = try await calculateFaceSimilarity(face1: idFace, face2: selfieFace)
        return similarityScore >= similarityThreshold
    }

    // MARK: - Text Processing Helpers

    private func extractIDNumber(from _: String) -> String? {
        // Implement ID number pattern matching logic
        // Example: Could look for specific patterns like "ID: XXXXX" or match against known formats
        nil
    }

    private func extractDateOfBirth(from _: String) -> String? {
        // Implement date of birth pattern matching logic
        // Example: Could look for date patterns like DD/MM/YYYY
        nil
    }

    private func extractName(from _: String) -> String? {
        // Implement name pattern matching logic
        // Example: Could look for specific formats or positions on the card
        nil
    }

    private func calculateFaceSimilarity(face1 _: VNFaceObservation, face2 _: VNFaceObservation) async throws -> Float {
        // Implement face similarity calculation
        // This would typically involve comparing facial landmarks, features, or using a ML model
        // Return a similarity score between 0 and 1
        0.0
    }
}

// MARK: - Usage Example

extension IDCardVerificationManager {
    static func example() {
        Task {
            let manager = IDCardVerificationManager()

            guard let idCardImage = UIImage(named: "id_card"),
                  let selfieImage = UIImage(named: "selfie")
            else {
                print("Failed to load images")
                return
            }

            do {
                // Process ID card
                let cardData = try await manager.processIDCard(image: idCardImage)
                print("Extracted ID data:", cardData)

                // Compare faces
                let matches = try await manager.compareFaces(
                    idCardImage: idCardImage,
                    selfieImage: selfieImage
                )

                print("Face match result:", matches)
            } catch {
                print("Verification failed:", error)
            }
        }
    }
}
