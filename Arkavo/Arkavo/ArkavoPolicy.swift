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
                let metadata = try Self.parseMetadata(from: bodyData)
                // Check for video content first
                if let content = metadata.content,
                   content.mediaType == .video
                {
                    type = .videoFrame
                } else {
                    type = .thought
                }
            } catch {
                print("Failed to parse embedded policy metadata: \(error)")
                type = .thought
            }
            return
        }

        // Default case if neither remote nor valid embedded policy
        type = .thought
    }

    public static func parseMetadata(from data: Data) throws -> Arkavo_Metadata {
        // Create ByteBuffer with the data
        var bb = ByteBuffer(data: data)
        let rootOffset = bb.read(def: Int32.self, position: 0)
        // Verify the FlatBuffer data structure
        var verifier = try Verifier(buffer: &bb)
        try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)
        // Create and return metadata object
        return Arkavo_Metadata(bb, o: rootOffset)
    }
}

// MARK: - CaseIterable Support

extension ArkavoPolicy.PolicyType: CaseIterable {}
