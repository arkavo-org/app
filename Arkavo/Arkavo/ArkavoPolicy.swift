import Foundation
import OpenTDFKit

class ArkavoPolicy {
    enum PolicyType {
        case accountProfile
        case streamProfile
        case thought
        case videoFrame
    }

    let type: PolicyType

    init(_: Policy) {
        // TODO: handle other types
        type = .thought
    }
}
