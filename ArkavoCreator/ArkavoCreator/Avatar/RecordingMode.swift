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
    case stream = "Stream"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .camera:
            "video.fill"
        case .avatar:
            "person.fill"
        case .stream:
            "antenna.radiowaves.left.and.right"
        }
    }

    var description: String {
        switch self {
        case .camera:
            "Record using your camera"
        case .avatar:
            "Record as a VRM avatar"
        case .stream:
            "Broadcast live stream"
        }
    }
}
