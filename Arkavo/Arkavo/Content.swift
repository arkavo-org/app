import Foundation
import SwiftData

struct Content: Identifiable, Codable {
    let id: UUID
    let type: ContentType
    let data: ContentData
    let metadata: [String: String]
    let createdAt: Date
    let createdBy: UUID
}

struct ContentData: Codable {
    let title: String
    let description: String?
    let url: URL?
    let textContent: String?
    let fileSize: Int64?
    let duration: TimeInterval?
}

enum ContentType: String, Codable {
    case text
    case image
    case video
    case audio
    case document
    case link
}

enum ContentError: Error {
    case notAMember
    case contentNotFound
    case notAuthorized
}
