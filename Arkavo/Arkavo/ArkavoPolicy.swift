import FlatBuffers
import Foundation
import OpenTDFKit

class ArkavoPolicy {
    enum PolicyType: String {
        case accountProfile = "ap"
        case streamProfile = "sp"
        case thought = "th"
        case videoFrame = "vf"

        static func from(_ string: String) -> PolicyType {
            // Find first matching policy type or default to thought
            PolicyType.allCases.first { string.contains($0.rawValue) } ?? .thought
        }
    }

    let type: PolicyType

    init(_ policy: Policy) {
        // Handle remote policy if it exists
        if case .remote = policy.type,
           let remoteBody = policy.remote?.body
        {
            type = PolicyType.from(remoteBody)
            return
        }

        // Handle local policy with embedded body
        if case .embeddedPlaintext = policy.type,
           let bodyData = policy.body?.body
        {
            do {
                type = try Self.parseMetadata(from: bodyData)
            } catch {
                print("Failed to parse embedded policy metadata: \(error)")
                type = .thought
            }
            return
        }

        // Default case if neither remote nor valid embedded policy
        type = .thought
    }

    private static func parseMetadata(from data: Data) throws -> PolicyType {
//        print("Raw FlatBuffer Data: \(data.map { String(format: "%02x", $0) }.joined())")
        // Create ByteBuffer with the data
        var bb = ByteBuffer(data: data)
        let rootOffset = bb.read(def: Int32.self, position: 0)

        // Verify the FlatBuffer data structure
        var verifier = try Verifier(buffer: &bb)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)
//        print("Successfully verified Arkavo_Metadata structure")

        // Create metadata object with verified offset
        let metadata = Arkavo_Metadata(bb, o: rootOffset)
//        print(metadata)
//
//        // Print or use the deserialized data
//        print("Created: \(metadata.created)")
//        print("ID: \(metadata.id)")
//        print("Related: \(metadata.related)")
//
//        if let rating = metadata.rating {
//            print("Rating - Violent: \(rating.violent)")
//            print("Rating - Sexual: \(rating.sexual)")
//        }
//
//        if let purpose = metadata.purpose {
//            print("Purpose - Educational: \(purpose.educational)")
//            print("Purpose - Entertainment: \(purpose.entertainment)")
//        }
//
//        print("Topics: \(metadata.topics)")
//
//        if let archive = metadata.archive {
//            print("Archive - Type: \(archive.type)")
//            print("Archive - Version: \(archive.version ?? "N/A")")
//            print("Archive - Profile: \(archive.profile ?? "N/A")")
//        }
//
//        if let content = metadata.content {
//            print("Content - Media Type: \(content.mediaType)")
//            print("Content - Data Encoding: \(content.dataEncoding)")
//
//            if let format = content.format {
//                print("Format - Type: \(format.type)")
//                print("Format - Version: \(format.version ?? "N/A")")
//                print("Format - Profile: \(format.profile ?? "N/A")")
//            }
//        }
        // Check for video content first
        if let content = metadata.content,
           content.mediaType == .video
        {
            return .videoFrame
        }
        return .thought
    }
}

// MARK: - CaseIterable Support

extension ArkavoPolicy.PolicyType: CaseIterable {}
