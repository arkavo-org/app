//
//  RecordingMode.swift
//  ArkavoCreator
//
//  Created for VRM Avatar Integration (#140)
//

import Foundation

/// Recording mode selection for creator content
enum RecordingMode: String, CaseIterable, Identifiable {
    case camera = "Camera"
    case avatar = "Avatar"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .camera:
            "video.fill"
        case .avatar:
            "person.fill"
        }
    }

    var description: String {
        switch self {
        case .camera:
            "Record using your camera"
        case .avatar:
            "Record as a VRM avatar"
        }
    }
}
