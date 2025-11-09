import Foundation
import SwiftUI

/// Feature flags for controlling which Arkavo features are enabled
/// This allows the app to run in different modes:
/// - Full Mode: All features including social network
/// - P2P Mode: Local agents + WiFi messaging only
/// - Offline Mode: Recording and local processing only
@MainActor
final class FeatureConfig: ObservableObject {
    /// Available features in Arkavo
    enum Feature: String, CaseIterable, Codable {
        case social      // Arkavo social network (auth, WebSocket, profiles)
        case agents      // Edge agent management
        case p2p         // WiFi/MultipeerConnectivity
        case creator     // Camera, VRM, recording
        case nfc         // NFC key exchange (not yet implemented)

        var displayName: String {
            switch self {
            case .social: return "Social Network"
            case .agents: return "Agent Management"
            case .p2p: return "P2P Messaging"
            case .creator: return "Creator Tools"
            case .nfc: return "NFC Key Exchange"
            }
        }

        var description: String {
            switch self {
            case .social:
                return "Connect to Arkavo social network with authentication and cloud sync"
            case .agents:
                return "Discover and manage AI agents on your local network"
            case .p2p:
                return "Secure peer-to-peer messaging via WiFi Direct"
            case .creator:
                return "Record videos, use VRM avatars, and create content"
            case .nfc:
                return "Exchange keys securely using NFC (coming soon)"
            }
        }

        var icon: String {
            switch self {
            case .social: return "network"
            case .agents: return "cpu"
            case .p2p: return "antenna.radiowaves.left.and.right"
            case .creator: return "video.fill"
            case .nfc: return "wave.3.right"
            }
        }
    }

    /// Currently enabled features
    @Published private(set) var enabledFeatures: Set<Feature>

    /// UserDefaults key for persistence
    private static let storageKey = "com.arkavo.enabledFeatures"

    /// Singleton instance
    static let shared = FeatureConfig()

    /// Default features for first launch
    private static let defaultFeatures: Set<Feature> = [.agents, .p2p, .creator]

    private init() {
        // Load from UserDefaults or use defaults
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(Set<Feature>.self, from: data) {
            self.enabledFeatures = decoded
        } else {
            // First launch: default to non-social features
            self.enabledFeatures = Self.defaultFeatures
        }
    }

    /// Check if a feature is enabled
    func isEnabled(_ feature: Feature) -> Bool {
        enabledFeatures.contains(feature)
    }

    /// Enable a feature
    func enable(_ feature: Feature) {
        guard !enabledFeatures.contains(feature) else { return }
        enabledFeatures.insert(feature)
        save()
        objectWillChange.send()
    }

    /// Disable a feature
    func disable(_ feature: Feature) {
        guard enabledFeatures.contains(feature) else { return }
        enabledFeatures.remove(feature)
        save()
        objectWillChange.send()
    }

    /// Enable multiple features at once
    func enable(_ features: Set<Feature>) {
        enabledFeatures.formUnion(features)
        save()
        objectWillChange.send()
    }

    /// Set enabled features (replaces current set)
    func setEnabledFeatures(_ features: Set<Feature>) {
        enabledFeatures = features
        save()
        objectWillChange.send()
    }

    /// Reset to default features
    func resetToDefaults() {
        enabledFeatures = Self.defaultFeatures
        save()
        objectWillChange.send()
    }

    /// Enable all features (Full Mode)
    func enableAllFeatures() {
        enabledFeatures = Set(Feature.allCases)
        save()
        objectWillChange.send()
    }

    /// Save to UserDefaults
    private func save() {
        if let encoded = try? JSONEncoder().encode(enabledFeatures) {
            UserDefaults.standard.set(encoded, forKey: Self.storageKey)
        }
    }
}

/// Global feature flags (static convenience)
enum FeatureFlags {
    /// Check if social network is enabled
    @MainActor
    static var socialNetworkEnabled: Bool {
        FeatureConfig.shared.isEnabled(.social)
    }

    /// Check if agent management is enabled
    @MainActor
    static var agentDiscoveryEnabled: Bool {
        FeatureConfig.shared.isEnabled(.agents)
    }

    /// Check if P2P messaging is enabled
    @MainActor
    static var p2pMessagingEnabled: Bool {
        FeatureConfig.shared.isEnabled(.p2p)
    }

    /// Check if creator tools are enabled
    @MainActor
    static var creatorToolsEnabled: Bool {
        FeatureConfig.shared.isEnabled(.creator)
    }

    /// Check if NFC is enabled
    @MainActor
    static var nfcEnabled: Bool {
        FeatureConfig.shared.isEnabled(.nfc)
    }
}
