import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

// MARK: - Main Content View

struct ProtectorView: View {
    @State private var currentScreen: Screen = .intro

    enum Screen {
        case intro, info, settings, privacy, scanning, impact, dashboard
    }

    var body: some View {
        NavigationView {
            switch currentScreen {
            case .intro:
                IntroductionView(currentScreen: $currentScreen)
            case .info:
                InformationView(currentScreen: $currentScreen)
            case .settings:
                SettingsView(currentScreen: $currentScreen)
            case .privacy:
                PrivacyView(currentScreen: $currentScreen)
            case .scanning:
                ScanningView(currentScreen: $currentScreen)
            case .impact:
                ImpactView(currentScreen: $currentScreen)
            case .dashboard:
                DashboardView(currentScreen: $currentScreen)
            }
        }
    }
}

// MARK: - Introduction Screen

struct IntroductionView: View {
    @Binding var currentScreen: ProtectorView.Screen

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.checkerboard")
                .font(.system(size: 60))
                .foregroundColor(.arkavoBrand)

            Text("Join the Movement to Protect Creators")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.arkavoText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Text("Every day, content creators face challenges protecting their work online. You can make a real difference!")
                    .foregroundColor(.arkavoText)
                    .multilineTextAlignment(.center)

                Text("By enabling content protection, you'll help identify unauthorized uses of creators' work across social networks.")
                    .foregroundColor(.arkavoText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Button(action: {
                withAnimation {
                    currentScreen = .info
                }
            }) {
                Text("Learn More")
                    .brandPrimaryButton()
            }
            .padding(.horizontal)
        }
        .padding()
        .background(Color.arkavoBackground)
    }
}

// MARK: - Information Screen

struct InformationView: View {
    @Binding var currentScreen: ProtectorView.Screen

    var body: some View {
        VStack(spacing: 24) {
            Text("How It Works")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.arkavoText)

            VStack(spacing: 20) {
                InfoCard(
                    icon: "shield.lefthalf.filled",
                    title: "Privacy First",
                    description: "With your permission, Arkavo will scan social networks to detect unauthorized content."
                )

                InfoCard(
                    icon: "wifi",
                    title: "Low Data Usage",
                    description: "Optimized scanning uses minimal data and only runs when you want it to."
                )

                InfoCard(
                    icon: "battery.100",
                    title: "Battery Efficient",
                    description: "Smart scheduling ensures minimal impact on your device's battery life."
                )
            }

            Spacer()

            Button(action: {
                withAnimation {
                    currentScreen = .settings
                }
            }) {
                Text("Customize Settings")
                    .brandPrimaryButton()
            }
        }
        .padding()
        .background(Color.arkavoBackground)
    }
}

// MARK: - Settings Screen

struct SettingsView: View {
    @Binding var currentScreen: ProtectorView.Screen
    @State private var nightOnly = false
    @State private var whileCharging = false
    @State private var wifiOnly = false
    @State private var selectedNetworks: Set<String> = ["instagram", "tiktok"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Customize Your Contribution")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.arkavoText)

                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle("When to Scan")

                    ToggleRow(
                        title: "Only at Night",
                        subtitle: "Scan during low-usage hours",
                        isOn: $nightOnly
                    )

                    ToggleRow(
                        title: "Only While Charging",
                        subtitle: "Preserve battery life",
                        isOn: $whileCharging
                    )

                    ToggleRow(
                        title: "Only on Wi-Fi",
                        subtitle: "Save mobile data",
                        isOn: $wifiOnly
                    )
                }

                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle("Networks to Scan")

                    ForEach(["Instagram", "TikTok", "Facebook", "Twitter"], id: \.self) { network in
                        NetworkToggleRow(
                            network: network,
                            isSelected: selectedNetworks.contains(network.lowercased()),
                            action: {
                                if selectedNetworks.contains(network.lowercased()) {
                                    selectedNetworks.remove(network.lowercased())
                                } else {
                                    selectedNetworks.insert(network.lowercased())
                                }
                            }
                        )
                    }
                }

                Button(action: {
                    withAnimation {
                        currentScreen = .privacy
                    }
                }) {
                    Text("Save and Start Protecting")
                        .brandPrimaryButton()
                }
            }
            .padding()
        }
        .background(Color.arkavoBackground)
    }
}

// MARK: - Privacy Screen

struct PrivacyView: View {
    @Binding var currentScreen: ProtectorView.Screen

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.arkavoBrand)

                Text("Your Privacy Matters")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.arkavoText)

                VStack(spacing: 20) {
                    PrivacyCard(
                        icon: "doc.text.fill",
                        title: "No Personal Data Collection",
                        description: "We never collect or store your personal information or browsing history"
                    )

                    PrivacyCard(
                        icon: "shield.lefthalf.filled",
                        title: "Secure Background Scanning",
                        description: "All scans are performed securely in the background"
                    )

                    PrivacyCard(
                        icon: "gear",
                        title: "Full Control",
                        description: "Adjust or disable protection features anytime"
                    )
                }

                Link(destination: URL(string: "https://arkavo.com/privacy")!) {
                    Text("Read Our Full Privacy Policy")
                        .font(.subheadline)
                        .foregroundColor(.arkavoBrand)
                        .underline()
                }

                Spacer()

                Button(action: {
                    withAnimation {
                        currentScreen = .scanning
                    }
                }) {
                    Text("I Understand")
                        .brandPrimaryButton()
                }
            }
            .padding()
        }
        .background(Color.arkavoBackground)
    }
}

// MARK: - Scanning Screen

struct ScanningView: View {
    @Binding var currentScreen: ProtectorView.Screen
    @State private var progress: CGFloat = 0.0
    @State private var currentNetwork = "Instagram"
    @State private var isPaused = false

    let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Text("Protecting Creators in Progress")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.arkavoText)

            ZStack {
                Circle()
                    .stroke(lineWidth: 20)
                    .opacity(0.1)
                    .foregroundColor(.arkavoBrand)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .foregroundColor(.arkavoBrand)
                    .rotationEffect(Angle(degrees: -90))
                    .animation(.linear, value: progress)

                VStack {
                    Image(systemName: "shield.checkerboard")
                        .font(.system(size: 40))
                        .foregroundColor(.arkavoBrand)
                    Text("\(Int(progress * 100))%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.arkavoText)
                }
            }
            .frame(width: 200, height: 200)

            VStack(spacing: 12) {
                Text("Scanning \(currentNetwork)...")
                    .font(.headline)
                    .foregroundColor(.arkavoText)
                Text("Next: TikTok")
                    .font(.subheadline)
                    .foregroundColor(.arkavoSecondary)
            }

            Button(action: {
                isPaused.toggle()
            }) {
                Text(isPaused ? "Resume Scanning" : "Pause Scanning")
                    .brandSecondaryButton()
            }

            if progress >= 1.0 {
                Button(action: {
                    currentScreen = .impact
                }) {
                    Text("View Results")
                        .brandPrimaryButton()
                }
            }
        }
        .padding()
        .background(Color.arkavoBackground)
        .onReceive(timer) { _ in
            if !isPaused, progress < 1.0 {
                progress += 0.01
            }
        }
    }
}

// MARK: - Impact Screen

struct ImpactView: View {
    @Binding var currentScreen: ProtectorView.Screen

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.arkavoBrand)

                Text("Thank You for Making a Difference!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.arkavoText)
                    .multilineTextAlignment(.center)

                ImpactStatsView()

                Text("Keep it up! Your contribution safeguards the creative community.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.arkavoSecondary)

                ShareButton()

                Button(action: {
                    withAnimation {
                        currentScreen = .dashboard
                    }
                }) {
                    Text("View Dashboard")
                        .brandPrimaryButton()
                }
            }
            .padding()
        }
        .background(Color.arkavoBackground)
    }
}

// MARK: - Dashboard Screen

struct DashboardView: View {
    @Binding var currentScreen: ProtectorView.Screen
    @State private var selectedTimeFrame = 0
    let timeFrames = ["Week", "Month", "Year"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    Text("Your Protection Stats")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.arkavoText)
                    Spacer()
                    Menu {
                        Button("Settings") {
                            currentScreen = .settings
                        }
                        Button("Privacy Policy") {
                            // Open privacy policy
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                            .foregroundColor(.arkavoBrand)
                    }
                }

                Picker("Time Frame", selection: $selectedTimeFrame) {
                    ForEach(Array(timeFrames.enumerated()), id: \.offset) { index, timeFrame in
                        Text(timeFrame).tag(index)
                    }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 16) {
                    StatCard(title: "Creators Protected", value: "512", trend: "+48")
                    StatCard(title: "Networks Scanned", value: "16", trend: "+3")
                    StatCard(title: "Hours Contributed", value: "24", trend: "+2")
                    StatCard(title: "Issues Found", value: "128", trend: "+12")
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Recent Activity")
                        .font(.headline)
                        .foregroundColor(.arkavoText)

                    ForEach(0 ..< 3) { _ in
                        ActivityRow()
                    }
                }

                Button(action: {
                    currentScreen = .scanning
                }) {
                    Text("Start New Scan")
                        .brandPrimaryButton()
                }
            }
            .padding()
        }
        .background(Color.arkavoBackground)
    }
}

// MARK: - Supporting Views

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .frame(width: 50, height: 50)
                .background(Color.arkavoBrandLight)
                .foregroundColor(.arkavoBrand)
                .cornerRadius(12)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.arkavoText)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.arkavoSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.arkavoBrand.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Privacy Card

struct PrivacyCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        FeatureCard(icon: icon, title: title, description: description)
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        FeatureCard(icon: icon, title: title, description: description)
    }
}

struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.arkavoSecondary)
    }
}

struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.arkavoText)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.arkavoSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.arkavoBrand)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// MARK: - Network Toggle Row

struct NetworkToggleRow: View {
    let network: String
    let isSelected: Bool
    let action: () -> Void

    private func iconName(for network: String) -> String {
        switch network.lowercased() {
        case "instagram":
            "camera.circle.fill"
        case "tiktok":
            "music.note.list"
        case "facebook":
            "person.2.circle.fill"
        case "twitter":
            "message.circle.fill"
        default:
            "network"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: iconName(for: network))
                    .font(.system(size: 20))
                    .frame(width: 40, height: 40)
                    .background(Color.arkavoBrandLight)
                    .foregroundColor(.arkavoBrand)
                    .cornerRadius(8)

                Text(network)
                    .font(.body)
                    .foregroundColor(.arkavoText)

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .arkavoBrand : .arkavoSecondary)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.arkavoBrand.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
    }
}

// MARK: - Impact Stats View

struct ImpactStatsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("You helped protect")
                .font(.headline)
                .foregroundColor(.arkavoText)

            HStack(alignment: .bottom, spacing: 4) {
                Text("512")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.arkavoBrand)
                Text("Creators")
                    .font(.title3)
                    .foregroundColor(.arkavoText)
            }

            Text("across 16 Social Networks")
                .font(.headline)
                .foregroundColor(.arkavoSecondary)
        }
        .padding()
        .background(Color.arkavoBrandLight)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.arkavoBrand.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let trend: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.arkavoSecondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.arkavoText)

            HStack {
                Image(systemName: trend.hasPrefix("+") ? "arrow.up.right" : "arrow.down.right")
                Text(trend)
            }
            .font(.caption)
            .foregroundColor(trend.hasPrefix("+") ? .green : .red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.arkavoBrand.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    var body: some View {
        HStack {
            Circle()
                .fill(Color.arkavoBrandLight)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "shield.checkerboard")
                        .foregroundColor(.arkavoBrand)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Scan Completed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.arkavoText)
                Text("Instagram • 2 issues found")
                    .font(.caption)
                    .foregroundColor(.arkavoSecondary)
            }

            Spacer()

            Text("2m ago")
                .font(.caption)
                .foregroundColor(.arkavoSecondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.arkavoBrand.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Brand Colors

extension Color {
    static let arkavoBrand = Color(red: 225 / 255, green: 113 / 255, blue: 51 / 255) // Orange from image
    static let arkavoText = Color.black
    static let arkavoSecondary = Color.gray
    static let arkavoBackground = Color.white

    // Opacity variants
    static let arkavoBrandLight = Color(red: 225 / 255, green: 113 / 255, blue: 51 / 255).opacity(0.1)
}

// MARK: - Theme Modifications for Views

extension View {
    func brandPrimaryButton() -> some View {
        fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.arkavoBrand)
            .foregroundColor(.white)
            .cornerRadius(12)
    }

    func brandSecondaryButton() -> some View {
        fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.arkavoBrandLight)
            .foregroundColor(.arkavoBrand)
            .cornerRadius(12)
    }
}

// MARK: - Preview Provider

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ProtectorView()
    }
}

struct ShareButton: View {
    private let shareMessage = "I'm helping protect creators with Arkavo! Join me in safeguarding creative content across social networks. 🛡️"

    var body: some View {
        Button(action: {
            shareContent(message: shareMessage)
        }) {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18))

                Text("Share Your Impact")
                    .font(.headline)
            }
            .brandSecondaryButton()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.arkavoBrand.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(.horizontal)
    }

    private func shareContent(message: String) {
        #if os(iOS)
            let activityVC = UIActivityViewController(activityItems: [message], applicationActivities: nil)

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootVC = window.rootViewController
            {
                rootVC.present(activityVC, animated: true)
            }
        #elseif os(macOS)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(message, forType: .string)

            let sharingServices = NSSharingService.sharingServices(forItems: [message])
            if !sharingServices.isEmpty {
                sharingServices[0].perform(withItems: [message])
            }
        #endif
    }
}

// Preview Provider
struct ShareButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ShareButton()
        }
        .padding()
        .background(Color.arkavoBackground)
    }
}
