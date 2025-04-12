import Foundation
import SwiftData

@Model
final class BlockedProfile {
    var id: UUID
    // Relationship to the Profile being blocked
    var blockedProfile: Profile?
    var reportTimestamp: Date
    var reportReasons: [String: Int] // Store reason:severity pairs

    init(blockedProfile: Profile, report: ContentReport) {
        id = UUID()
        self.blockedProfile = blockedProfile // Assign the related Profile object
        reportTimestamp = report.timestamp
        // Explicitly map to Int values
        reportReasons = Dictionary(uniqueKeysWithValues: report.reasons.map { reason, severity in
            (reason.rawValue, severity.rawValue)
        })
    }
}

struct ContentReport: Codable {
    let id: UUID
    let reasons: [ReportReason: ContentRatingLevel]
    let includeSnapshot: Bool
    let blockUser: Bool
    let timestamp: Date
    let contentId: String
    let reporterId: String
    var blockedPublicID: String?

    init(reasons: [ReportReason: ContentRatingLevel],
         includeSnapshot: Bool,
         blockUser: Bool,
         timestamp: Date,
         contentId: String,
         reporterId: String,
         blockedPublicID: String? = nil)
    {
        id = UUID()
        self.reasons = reasons
        self.includeSnapshot = includeSnapshot
        self.blockUser = blockUser
        self.timestamp = timestamp
        self.contentId = contentId
        self.reporterId = reporterId
        self.blockedPublicID = blockedPublicID
    }
}

enum ReportReason: String, Codable, CaseIterable {
    case spam = "Spam"
    case harassment = "Harassment"
    case hateSpeech = "Hate Speech"
    case violence = "Violence"
    case adultContent = "Adult Content"
    case copyright = "Copyright Violation"
    case privacy = "Privacy Violation"
    case misinformation = "Misinformation"
    case other = "Other"

    var description: String {
        switch self {
        case .spam: "Commercial spam, scams, or unwanted promotional content"
        case .harassment: "Targeted harassment or bullying"
        case .hateSpeech: "Hate speech or discriminatory content"
        case .violence: "Violence, threats, or dangerous behavior"
        case .adultContent: "Adult content, nudity, or sexual content"
        case .copyright: "Copyright or trademark infringement"
        case .privacy: "Personal information or privacy violation"
        case .misinformation: "False or misleading information"
        case .other: "Other violation of community guidelines"
        }
    }

    var icon: String {
        switch self {
        case .spam: "exclamationmark.triangle"
        case .harassment: "person.2.slash"
        case .hateSpeech: "speaker.slash"
        case .violence: "exclamationmark.shield"
        case .adultContent: "eye.slash"
        case .copyright: "doc.on.doc"
        case .privacy: "lock.shield"
        case .misinformation: "exclamationmark.bubble"
        case .other: "flag"
        }
    }

    var colorName: String {
        switch self {
        case .spam: "orange"
        case .harassment: "red"
        case .hateSpeech: "red"
        case .violence: "red"
        case .adultContent: "pink"
        case .copyright: "purple"
        case .privacy: "indigo"
        case .misinformation: "yellow"
        case .other: "orange"
        }
    }
}

enum ContentRatingLevel: Int, Codable, CaseIterable {
    case low = 1
    case medium = 2
    case high = 3

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var description: String {
        switch self {
        case .low: "Minor violation that should be reviewed"
        case .medium: "Significant violation requiring attention"
        case .high: "Severe violation needing immediate action"
        }
    }

    var icon: String {
        switch self {
        case .low: "exclamationmark.circle"
        case .medium: "exclamationmark.triangle"
        case .high: "exclamationmark.shield"
        }
    }

    var colorName: String {
        switch self {
        case .low: "gray"
        case .medium: "orange"
        case .high: "red"
        }
    }
}
