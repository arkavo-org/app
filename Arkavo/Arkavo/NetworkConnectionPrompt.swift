import SwiftUI

/// A reusable prompt encouraging users to connect to a network
/// Can be used as an overlay, sheet, or inline view
struct NetworkConnectionPrompt: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var selectedNetwork: NetworkOption = .arkavo
    @State private var customDomain: String = ""
    @State private var isConnecting = false

    var onConnect: ((String) -> Void)?
    var onSkip: (() -> Void)?

    enum NetworkOption: String, CaseIterable {
        case arkavo = "arkavo.social"
        case custom = "Custom Server"

        var icon: String {
            switch self {
            case .arkavo: return "globe.americas.fill"
            case .custom: return "server.rack"
            }
        }

        var description: String {
            switch self {
            case .arkavo: return "Official Arkavo network with global reach"
            case .custom: return "Connect to a private or self-hosted server"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("Connect to a Network")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Unlock video streaming, social feeds, and messaging with people outside your local network.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Network options
            VStack(spacing: 12) {
                ForEach(NetworkOption.allCases, id: \.self) { option in
                    NetworkOptionRow(
                        option: option,
                        isSelected: selectedNetwork == option,
                        onTap: { selectedNetwork = option }
                    )
                }

                // Custom domain field
                if selectedNetwork == .custom {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("server.example.com", text: $customDomain)
                            .textContentType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
            }

            // Benefits
            VStack(alignment: .leading, spacing: 8) {
                BenefitRow(icon: "play.circle", text: "Stream and discover videos")
                BenefitRow(icon: "bubble.left.and.bubble.right", text: "Join conversations and communities")
                BenefitRow(icon: "paperplane", text: "Message anyone on the network")
                BenefitRow(icon: "lock.shield", text: "End-to-end encrypted")
            }
            .padding(.horizontal)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedNetwork == .custom && customDomain.isEmpty || isConnecting)

                Button("Continue Offline") {
                    onSkip?()
                }
                .foregroundStyle(.secondary)
            }
            .padding(.bottom)
        }
        .padding()
    }

    private func connect() {
        let domain = selectedNetwork == .custom ? customDomain : selectedNetwork.rawValue
        isConnecting = true

        // Trigger registration flow with the selected network
        onConnect?(domain)
    }
}

// MARK: - Supporting Views

private struct NetworkOptionRow: View {
    let option: NetworkConnectionPrompt.NetworkOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.1))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.rawValue)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(option.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

private struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Compact Inline Prompt

/// A compact banner-style prompt for inline use
struct NetworkConnectionBanner: View {
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "network")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to unlock more features")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text("Stream videos, join communities, message globally")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Full Prompt") {
    NetworkConnectionPrompt()
        .environmentObject(SharedState())
}

#Preview("Banner") {
    NetworkConnectionBanner(onTap: {})
        .padding()
}
