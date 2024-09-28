import CryptoKit
import Foundation

// Enum to represent action types
enum ActionType: String, Codable {
    case join
    case apply
    case approve
    case leave
    case sendMessage
}

// Enum to represent the current status of the action
enum ActionStatus: String, Codable {
    case preparing
    case fulfilling
    case fulfilled
    case failed
}

enum EntityType: String, Codable {
    case streamProfile
    case accountProfile
}

// UserAction model for user-initiated actions
struct UserAction: Codable {
    var actionType: ActionType
    var sourceType: EntityType
    var targetType: EntityType
    var sourcePublicID: Data
    var targetPublicID: Data
    var timestamp: Date
    var status: ActionStatus

    init(
        actionType: ActionType,
        sourceType: EntityType,
        targetType: EntityType,
        sourcePublicID: Data,
        targetPublicID: Data,
        timestamp: Date = .now,
        status: ActionStatus = .preparing
    ) {
        self.actionType = actionType
        self.sourceType = sourceType
        self.targetType = targetType
        self.sourcePublicID = sourcePublicID
        self.targetPublicID = targetPublicID
        self.timestamp = timestamp
        self.status = status
    }
}

extension UserAction {
    private static let decoder = PropertyListDecoder()
    private static let encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()

    // Serialization to binary data
    func serialize() throws -> Data {
        try UserAction.encoder.encode(self)
    }

    // Deserialization from binary data
    static func deserialize(from data: Data) throws -> UserAction {
        try decoder.decode(UserAction.self, from: data)
    }
}
