import CryptoKit
import Foundation
import OpenTDFKit

// Enum to represent action types
enum ActionType: String, Codable {
    case join
    case apply
    case approve
    case leave
    case sendMessage
}

// Enum to represent lifecycle states of the target object
enum LifecycleState: String, Codable {
    case preparing
    case fulfilling
    case fulfilled
}

// Enum to represent the current status of the action
enum ActionStatus: String, Codable {
    case preparing
    case fulfilling
    case fulfilled
    case failed
}

// UserAction model for user-initiated actions
struct UserAction: Codable {
    var userID: UUID
    var targetObjectID: UUID
    var actionType: ActionType
    var targetLifecycleState: LifecycleState
    var timestamp: Date
    var status: ActionStatus
    var publicID: Data // Public ID (hashed)

    init(userID: UUID, targetObjectID: UUID, actionType: ActionType, targetLifecycleState: LifecycleState, status: ActionStatus) {
        self.userID = userID
        self.targetObjectID = targetObjectID
        self.actionType = actionType
        self.targetLifecycleState = targetLifecycleState
        self.status = status
        timestamp = Date()
        let hashData = userID.uuidString.data(using: .utf8)! + targetObjectID.uuidString.data(using: .utf8)! + actionType.rawValue.data(using: .utf8)!
        publicID = SHA256.hash(data: hashData).withUnsafeBytes { Data($0) }
    }
}

extension UserAction {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    // Public ID string representation
    var publicIDString: String {
        publicID.base58EncodedString
    }

    // Serialization to binary data
    func serialize() throws -> Data {
        try UserAction.encoder.encode(self)
    }

    // Deserialization from binary data
    static func deserialize(from data: Data) throws -> UserAction {
        try decoder.decode(UserAction.self, from: data)
    }
}
