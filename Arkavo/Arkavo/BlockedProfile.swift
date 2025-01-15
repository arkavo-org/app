import Foundation
import SwiftData

@Model
final class BlockedProfile {
    var id: UUID
    var blockedPublicID: Data
    var reportTimestamp: Date
    var reportReasons: [String: Int] // Store reason:severity pairs

    init(blockedPublicID: Data, report: ContentReport) {
        id = UUID()
        self.blockedPublicID = blockedPublicID
        reportTimestamp = report.timestamp
        reportReasons = Dictionary(uniqueKeysWithValues: report.reasons.map {
            ($0.key.rawValue, $0.value.rawValue)
        })
    }
}

struct ContentReport {
    let reasons: [ReportReason: ContentRatingLevel]
    let includeSnapshot: Bool
    let blockUser: Bool
    let timestamp: Date
    let contentId: String
    let reporterId: String
}

enum ContentRatingLevel: Int, CaseIterable {
    case mild = 2
    case moderate = 3
    case severe = 4

    var title: String {
        switch self {
        case .mild:
            "Mild"
        case .moderate:
            "Moderate"
        case .severe:
            "Severe"
        }
    }

    var icon: String {
        switch self {
        case .mild:
            "exclamationmark.circle"
        case .moderate:
            "exclamationmark.triangle"
        case .severe:
            "exclamationmark.shield"
        }
    }

    var colorName: String {
        switch self {
        case .mild: "gray"
        case .moderate: "orange"
        case .severe: "red"
        }
    }

    var description: String {
        switch self {
        case .mild:
            "Content that may be mildly inappropriate"
        case .moderate:
            "Content that clearly violates community guidelines"
        case .severe:
            "Content requiring immediate review and action"
        }
    }
}

enum ReportReason: String, CaseIterable {
    case violence = "Violence"
    case sexual = "Sexual Content"
    case profanity = "Profanity"
    case substance = "Substance Abuse"
    case hate = "Hate Speech"
    case harm = "Harmful Content"
    case mature = "Mature Content"
    case bullying = "Bullying"

    var description: String {
        switch self {
        case .violence:
            "Content containing violence or graphic material"
        case .sexual:
            "Inappropriate sexual content or nudity"
        case .profanity:
            "Excessive profanity or offensive language"
        case .substance:
            "Content promoting substance abuse"
        case .hate:
            "Hate speech or discriminatory content"
        case .harm:
            "Content promoting self-harm or harmful activities"
        case .mature:
            "Age-inappropriate or mature content"
        case .bullying:
            "Harassment or bullying behavior"
        }
    }

    var icon: String {
        switch self {
        case .violence:
            "person.crop.circle.badge.exclamationmark"
        case .sexual:
            "eye.trianglebadge.exclamationmark"
        case .profanity:
            "bubble.left.and.exclamationmark.bubble.right"
        case .substance:
            "pills.circle"
        case .hate:
            "hand.raised.slash.fill"
        case .harm:
            "bandage"
        case .mature:
            "exclamationmark.triangle"
        case .bullying:
            "person.2.slash"
        }
    }

    var colorName: String {
        switch self {
        case .violence, .hate: "red"
        case .sexual, .mature: "orange"
        case .profanity: "yellow"
        case .substance: "purple"
        case .harm: "pink"
        case .bullying: "indigo"
        }
    }
}
