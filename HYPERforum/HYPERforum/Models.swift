import Foundation
import SwiftUI

// MARK: - Message Models

struct ForumMessage: Identifiable, Codable {
    let id: String
    let groupId: String
    let senderId: String
    let senderName: String
    let content: String
    let timestamp: Date
    let threadId: String?
    var isEncrypted: Bool = true

    init(id: String = UUID().uuidString,
         groupId: String,
         senderId: String,
         senderName: String,
         content: String,
         timestamp: Date = Date(),
         threadId: String? = nil,
         isEncrypted: Bool = true) {
        self.id = id
        self.groupId = groupId
        self.senderId = senderId
        self.senderName = senderName
        self.content = content
        self.timestamp = timestamp
        self.threadId = threadId
        self.isEncrypted = isEncrypted
    }
}

// MARK: - Group Models

struct ForumGroup: Identifiable {
    let id: String
    let name: String
    let color: Color
    let memberCount: Int
    let description: String
    var lastMessage: ForumMessage?

    init(id: String = UUID().uuidString,
         name: String,
         color: Color,
         memberCount: Int,
         description: String = "",
         lastMessage: ForumMessage? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.memberCount = memberCount
        self.description = description
        self.lastMessage = lastMessage
    }

    static let sampleGroups = [
        ForumGroup(
            name: "General",
            color: Color(red: 1.0, green: 0.4, blue: 0.0),
            memberCount: 142,
            description: "General discussion for all topics"
        ),
        ForumGroup(
            name: "Tech Discussions",
            color: .blue,
            memberCount: 89,
            description: "Technology, programming, and innovation"
        ),
        ForumGroup(
            name: "Philosophy",
            color: .purple,
            memberCount: 67,
            description: "Deep thoughts and philosophical discussions"
        ),
        ForumGroup(
            name: "AI & Future",
            color: .cyan,
            memberCount: 103,
            description: "Artificial intelligence and the future of humanity"
        )
    ]
}

// MARK: - Message Payload

struct MessagePayload: Codable {
    let type: String
    let groupId: String
    let content: String
    let senderId: String
    let senderName: String
    let timestamp: Double
    let messageId: String

    enum CodingKeys: String, CodingKey {
        case type
        case groupId = "group_id"
        case content
        case senderId = "sender_id"
        case senderName = "sender_name"
        case timestamp
        case messageId = "message_id"
    }
}

// MARK: - Thread Models

struct MessageThread: Identifiable {
    let id: String
    let topic: String
    let groupId: String
    let startedBy: String
    let startedAt: Date
    var messageCount: Int
    var lastActivity: Date

    init(id: String = UUID().uuidString,
         topic: String,
         groupId: String,
         startedBy: String,
         startedAt: Date = Date(),
         messageCount: Int = 0,
         lastActivity: Date = Date()) {
        self.id = id
        self.topic = topic
        self.groupId = groupId
        self.startedBy = startedBy
        self.startedAt = startedAt
        self.messageCount = messageCount
        self.lastActivity = lastActivity
    }
}
