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
        // FIXME: update OpenTDFKit to expose Policy
        type = .thought
    }
}
