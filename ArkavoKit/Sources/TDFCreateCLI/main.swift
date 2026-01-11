import ArkavoSocial
import CryptoKit
import Darwin
import Foundation
import IrohSwift

/// TDF Create CLI - Creates TDF-protected content and publishes to Iroh
///
/// Usage:
///   tdf-create <input-file> [--kas-url URL] [--output FILE]
///
/// Examples:
///   tdf-create video.mov
///   tdf-create video.mov --kas-url https://100.arkavo.net
///   tdf-create video.mov --output protected.tdf

@main
struct TDFCreateCLI {
    static let defaultKASURL = URL(string: "https://100.arkavo.net")!

    static func main() async {
        // Unbuffered output
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        let args = CommandLine.arguments

        // Parse arguments
        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        var inputPath: String?
        var kasURL = defaultKASURL
        var outputPath: String?
        var publishToIroh = true

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--kas-url":
                i += 1
                guard i < args.count, let url = URL(string: args[i]) else {
                    printError("Invalid KAS URL")
                    exit(1)
                }
                kasURL = url
            case "--output", "-o":
                i += 1
                guard i < args.count else {
                    printError("Missing output path")
                    exit(1)
                }
                outputPath = args[i]
            case "--no-publish":
                publishToIroh = false
            case "--help", "-h":
                printUsage()
                exit(0)
            default:
                if args[i].hasPrefix("-") {
                    printError("Unknown option: \(args[i])")
                    exit(1)
                }
                inputPath = args[i]
            }
            i += 1
        }

        guard let inputPath else {
            printError("Missing input file")
            printUsage()
            exit(1)
        }

        // Run main workflow
        do {
            try await run(
                inputPath: inputPath,
                kasURL: kasURL,
                outputPath: outputPath,
                publishToIroh: publishToIroh
            )
        } catch {
            printError("Failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run(
        inputPath: String,
        kasURL: URL,
        outputPath: String?,
        publishToIroh: Bool
    ) async throws {
        print("============================================")
        print("TDF Create CLI")
        print("============================================")
        print("Input: \(inputPath)")
        print("KAS URL: \(kasURL)")
        print("Publish to Iroh: \(publishToIroh)")
        print("============================================\n")

        // 1. Read input file
        print("Step 1: Reading input file...")
        let inputURL = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw CLIError.fileNotFound(inputPath)
        }
        let inputData = try Data(contentsOf: inputURL)
        print("  Read \(inputData.count) bytes")

        // Determine MIME type from extension
        let mimeType = mimeTypeForExtension(inputURL.pathExtension)
        print("  MIME type: \(mimeType)")

        // 2. Generate asset ID
        let assetID = UUID().uuidString
        print("\nStep 2: Generated asset ID: \(assetID)")

        // 3. Create TDF protection
        print("\nStep 3: Creating TDF protection...")
        let protectionService = TDFProtectionService(kasURL: kasURL)
        let tdfData = try await protectionService.protect(
            data: inputData,
            assetID: assetID,
            mimeType: mimeType
        )
        print("  Created TDF archive: \(tdfData.count) bytes")

        // 4. Save TDF file if output path specified
        let tdfOutputPath: String
        if let outputPath {
            tdfOutputPath = outputPath
        } else {
            // Default output path
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            tdfOutputPath = "\(baseName).tdf"
        }

        print("\nStep 4: Saving TDF archive to \(tdfOutputPath)...")
        try tdfData.write(to: URL(fileURLWithPath: tdfOutputPath))
        print("  Saved!")

        // 5. Extract manifest for display
        print("\nStep 5: Verifying TDF archive...")
        let manifest = try TDFArchiveReader.extractManifest(from: tdfData)
        print("  Asset ID: \(manifest.assetID)")
        print("  Algorithm: \(manifest.algorithm)")
        print("  KAS URL: \(manifest.kasURL)")
        print("  Protected at: \(manifest.protectedAt)")

        // 6. Publish to Iroh
        if publishToIroh {
            print("\nStep 6: Publishing to Iroh network...")
            let node = try await IrohNode()

            // Publish TDF archive
            print("  Uploading TDF archive...")
            let payloadTicket = try await node.put(tdfData)
            print("  Payload ticket: \(payloadTicket.prefix(60))...")

            // Create and publish descriptor
            print("  Creating content descriptor...")
            let contentID = generateContentID(from: assetID)
            let descriptor = ContentDescriptor(
                id: UUID(),
                contentID: contentID,
                creatorPublicID: Data(repeating: 0, count: 32), // Placeholder
                manifest: manifest,
                payloadTicket: payloadTicket,
                payloadSize: Int64(tdfData.count),
                title: inputURL.lastPathComponent,
                mimeType: mimeType,
                durationSeconds: nil,
                originalFileSize: Int64(inputData.count),
                createdAt: Date(),
                updatedAt: Date(),
                version: 1
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let descriptorData = try encoder.encode(descriptor)
            let descriptorTicket = try await node.put(descriptorData)

            print("\n============================================")
            print("SUCCESS!")
            print("============================================")
            print("\nTDF File: \(tdfOutputPath)")
            print("\nDescriptor Ticket (share this):")
            print(descriptorTicket)
            print("\nPayload Ticket (direct TDF access):")
            print(payloadTicket)
            print("============================================")

            try await node.close()
        } else {
            print("\n============================================")
            print("SUCCESS!")
            print("============================================")
            print("\nTDF File: \(tdfOutputPath)")
            print("Asset ID: \(assetID)")
            print("============================================")
        }
    }

    static func printUsage() {
        print("""
        TDF Create CLI - Creates TDF-protected content and publishes to Iroh

        Usage:
          tdf-create <input-file> [options]

        Options:
          --kas-url URL     KAS server URL (default: https://100.arkavo.net)
          --output, -o FILE Output TDF file path (default: <input>.tdf)
          --no-publish      Don't publish to Iroh, only create local TDF file
          --help, -h        Show this help message

        Examples:
          tdf-create video.mov
          tdf-create video.mov --kas-url https://kas.example.com
          tdf-create video.mov --output protected.tdf --no-publish
        """)
    }

    static func printError(_ message: String) {
        fputs("Error: \(message)\n", stderr)
    }

    static func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mov", "qt":
            "video/quicktime"
        case "mp4", "m4v":
            "video/mp4"
        case "avi":
            "video/x-msvideo"
        case "mkv":
            "video/x-matroska"
        case "webm":
            "video/webm"
        case "mp3":
            "audio/mpeg"
        case "m4a", "aac":
            "audio/mp4"
        case "wav":
            "audio/wav"
        case "flac":
            "audio/flac"
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "gif":
            "image/gif"
        case "pdf":
            "application/pdf"
        default:
            "application/octet-stream"
        }
    }

    static func generateContentID(from assetID: String) -> Data {
        let data = assetID.data(using: .utf8) ?? Data()
        return Data(SHA256.hash(data: data))
    }
}

enum CLIError: Error, LocalizedError {
    case fileNotFound(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .invalidArgument(msg):
            "Invalid argument: \(msg)"
        }
    }
}
