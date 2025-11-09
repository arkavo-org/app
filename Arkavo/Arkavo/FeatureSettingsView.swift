import SwiftUI

/// Settings view for managing which Arkavo features are enabled
struct FeatureSettingsView: View {
    @EnvironmentObject var featureConfig: FeatureConfig
    @EnvironmentObject var sharedState: SharedState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Choose which features to enable. Disabling features can improve privacy and reduce resource usage.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                Section("Core Features") {
                    FeatureToggle(
                        feature: .social,
                        isEnabled: featureConfig.isEnabled(.social)
                    )

                    FeatureToggle(
                        feature: .agents,
                        isEnabled: featureConfig.isEnabled(.agents)
                    )

                    FeatureToggle(
                        feature: .p2p,
                        isEnabled: featureConfig.isEnabled(.p2p)
                    )

                    FeatureToggle(
                        feature: .creator,
                        isEnabled: featureConfig.isEnabled(.creator)
                    )
                }

                Section("Coming Soon") {
                    FeatureToggle(
                        feature: .nfc,
                        isEnabled: featureConfig.isEnabled(.nfc),
                        disabled: true
                    )
                }

                Section {
                    Button("Reset to Defaults") {
                        featureConfig.resetToDefaults()
                    }
                    .foregroundColor(.red)

                    Button("Enable All Features") {
                        featureConfig.enableAllFeatures()
                    }
                }
            }
            .navigationTitle("Feature Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Individual feature toggle row
private struct FeatureToggle: View {
    @EnvironmentObject var featureConfig: FeatureConfig
    @EnvironmentObject var sharedState: SharedState

    let feature: FeatureConfig.Feature
    let isEnabled: Bool
    let disabled: Bool

    init(feature: FeatureConfig.Feature, isEnabled: Bool, disabled: Bool = false) {
        self.feature = feature
        self.isEnabled = isEnabled
        self.disabled = disabled
    }

    var body: some View {
        Toggle(isOn: binding) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: feature.icon)
                        .foregroundColor(isEnabled ? .blue : .secondary)
                    Text(feature.displayName)
                        .font(.body)
                }
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(disabled)
        .onChange(of: isEnabled) { _, newValue in
            handleToggleChange(newValue)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                if newValue {
                    featureConfig.enable(feature)
                } else {
                    featureConfig.disable(feature)
                }
            }
        )
    }

    private func handleToggleChange(_ enabled: Bool) {
        // Handle side effects of toggling features
        switch feature {
        case .social:
            if !enabled {
                // Disable social network
                sharedState.isOfflineMode = true
                // Switch away from social tab if currently selected
                if sharedState.selectedTab == .social {
                    sharedState.selectedTab = .home
                }
            } else {
                // Re-enable social network
                // Note: Will require app restart or manual reconnection
                // TODO: Add reconnection logic
            }

        case .agents:
            // Switch away from agents tab if currently selected
            if !enabled && sharedState.selectedTab == .agents {
                sharedState.selectedTab = .home
            }

        default:
            break
        }
    }
}

#Preview {
    FeatureSettingsView()
        .environmentObject(FeatureConfig.shared)
        .environmentObject(SharedState())
}
