import Foundation
import SwiftUI

final class ActivityServiceModel {
    var dateCreated: Date
    var expertLevel: String
    var activityLevel: ActivityLevel
    var trustLevel: String

    init(dateCreated: Date = Date(), expertLevel: String = "", activityLevel: ActivityLevel = .medium, trustLevel: String = "") {
        self.dateCreated = dateCreated
        self.expertLevel = expertLevel
        self.activityLevel = activityLevel
        self.trustLevel = trustLevel
    }
}

enum ActivityLevel: String, CaseIterable, Codable {
    case veryLow = "Very Low"
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case veryHigh = "Very High"

    var color: Color {
        switch self {
        case .veryLow: .red
        case .low: .orange
        case .medium: .yellow
        case .high: .green
        case .veryHigh: .blue
        }
    }
}
