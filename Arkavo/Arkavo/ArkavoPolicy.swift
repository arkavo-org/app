import Foundation
import OpenTDFKit

class ArkavoPolicy {
    enum PolicyType: String {
        case accountProfile = "ap"
        case streamProfile = "sp"
        case thought = "th"
        case videoFrame = "vf"
    }

    let type: PolicyType

    init(_ policy: Policy) {
//        print("policy: \(policy)")
        if let remoteBody = policy.remote?.body {
            if remoteBody.contains(PolicyType.accountProfile.rawValue) {
                type = .accountProfile
            } else if remoteBody.contains(PolicyType.streamProfile.rawValue) {
                type = .streamProfile
            } else if remoteBody.contains(PolicyType.videoFrame.rawValue) {
                type = .videoFrame
            } else if remoteBody.contains(PolicyType.thought.rawValue) {
                type = .thought
            } else {
                type = .thought // Default case
            }
        } else {
            type = .thought // Default case if remote body is nil
        }
    }
}
