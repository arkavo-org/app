import SwiftUI

/// A reusable prompt encouraging users to connect to a network
/// Can be used as an overlay, sheet, or inline view
struct NetworkConnectionPrompt: View {
    @EnvironmentObject var sharedState: SharedState
    @State private var showCustomServerField = false
    @State private var customDomain: String = ""
    @State private var connectingOption: NetworkOption?

    var onConnect: ((String) -> Void)?
    var onSkip: (() -> Void)?

    enum NetworkOption: String, CaseIterable {
        case arkavo = "arkavo.social"
        case custom = "Custom Server"
        case offline = "Continue Offline"

        var icon: String {
            switch self {
            case .arkavo: return "globe.americas.fill"
            case .custom: return "server.rack"
            case .offline: return "wifi.slash"
            }
        }

        var description: String {
            switch self {
            case .arkavo: return "Official Arkavo network with global reach"
            case .custom: return "Connect to a private or self-hosted server"
            case .offline: return "Use local features only"
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

            // Network options - one tap to select and connect
            VStack(spacing: 12) {
                ForEach(NetworkOption.allCases, id: \.self) { option in
                    NetworkOptionRow(
                        option: option,
                        isConnecting: connectingOption == option,
                        onTap: { handleOptionTap(option) }
                    )
                }

                // Custom domain field
                if showCustomServerField {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "link")
                                .foregroundStyle(.secondary)
                            TextField("server.example.com", text: $customDomain)
                                .textContentType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit {
                                    if !customDomain.isEmpty {
                                        connectToCustomServer()
                                    }
                                }
                        }
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                        Button {
                            connectToCustomServer()
                        } label: {
                            if connectingOption == .custom {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect to Server")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(customDomain.isEmpty || connectingOption != nil)
                    }
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
        }
        .padding()
    }

    private func handleOptionTap(_ option: NetworkOption) {
        switch option {
        case .arkavo:
            connectingOption = .arkavo
            onConnect?(option.rawValue)
        case .custom:
            showCustomServerField.toggle()
        case .offline:
            onSkip?()
        }
    }

    private func connectToCustomServer() {
        guard !customDomain.isEmpty else { return }
        connectingOption = .custom
        onConnect?(customDomain)
    }
}

// MARK: - Supporting Views

private struct NetworkOptionRow: View {
    let option: NetworkConnectionPrompt.NetworkOption
    let isConnecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: option.icon)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.1))
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

                if isConnecting {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
        .disabled(isConnecting)
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
