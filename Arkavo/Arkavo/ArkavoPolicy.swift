import FlatBuffers
import Foundation
import OpenTDFKit

final class ArkavoPolicy: @unchecked Sendable {
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
    let metadata: Arkavo_Metadata?

    init(_ policy: Policy) {
        // Handle remote policy if it exists
        if case .remote = policy.type,
           let remoteBody = policy.remote?.body
        {
            type = PolicyType.from(remoteBody)
            metadata = nil
            return
        }

        // Handle local policy with embedded body
        if case .embeddedPlaintext = policy.type,
           let bodyData = policy.body?.body
        {
            do {
                let metadata = try Self.parseMetadata(from: bodyData)
                self.metadata = metadata
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
                // Add debug info about the data
                print("Data size: \(bodyData.count)")
                let hexString = bodyData.prefix(32).map { String(format: "%02x", $0) }.joined()
                print("First 32 bytes: \(hexString)")
                type = .thought
                metadata = nil
            }
            return
        }

        // Default case if neither remote nor valid embedded policy
        type = .thought
        metadata = nil
    }

    public static func parseMetadata(from data: Data) throws -> Arkavo_Metadata {
        do {
            var bb = ByteBuffer(data: data)
            let rootOffset = bb.read(def: Int32.self, position: 0)
//            print("Root offset: \(rootOffset)") // Debug info

            // Verify the FlatBuffer data structure
            var verifier = try Verifier(buffer: &bb)
            try Arkavo_Metadata.verify(&verifier, at: Int(rootOffset), of: Arkavo_Metadata.self)

            // Create and return metadata object
            return Arkavo_Metadata(bb, o: rootOffset)
        } catch {
            print("Error during metadata parsing: \(error)")
            throw error
        }
    }
}

// MARK: - CaseIterable Support

extension ArkavoPolicy.PolicyType: CaseIterable {}
