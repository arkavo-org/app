import SwiftUI

struct OfflineHomeView: View {
    @EnvironmentObject private var sharedState: SharedState

    private var hasProfile: Bool {
        ViewModelFactory.shared.getCurrentProfile() != nil
    }

    var body: some View {
        VStack {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .padding(.top, 60)

            Text("Offline Mode")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 20)

            Text("You're currently using Arkavo in offline mode.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 10)

            if !hasProfile {
                // Show message to go to Profile page
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .padding(.top, 30)

                    Text("No Profile Yet")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Go to the Profile page to create a local profile and start using Out-of-Band messaging.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .padding(.top, 20)

                Spacer()
            } else {
                // Show feature list when profile exists
                VStack(alignment: .leading, spacing: 16) {
                    FeatureStatusRow(
                        title: "Out-of-Band Messaging",
                        description: "One-time TDF secure messaging works in offline mode",
                        isAvailable: true,
                    )

                    FeatureStatusRow(
                        title: "Video Feed",
                        description: "Requires internet connection",
                        isAvailable: false,
                    )

                    FeatureStatusRow(
                        title: "Social Feed",
                        description: "Requires internet connection",
                        isAvailable: false,
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 30)

                Spacer()
            }
        }
        .overlay(alignment: .topTrailing) {
            // Clickable reconnect button in the corner
            Button {
                // Set flag to retry connection
                Data.didPostRetryConnection = true
            } label: {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.white)

                    Text("Tap to Reconnect")
                        .foregroundColor(.white)
                        .font(.caption)
                        .bold()
                }
                .padding(8)
                .background(Color.red.opacity(0.8))
                .cornerRadius(20)
            }
            .padding(8)
        }
    }
}

struct FeatureStatusRow: View {
    let title: String
    let description: String
    let isAvailable: Bool

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isAvailable ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// Define notification name for retry connection if not already defined
// Define the notification name in the AppDelegate/main file instead

#Preview {
    OfflineHomeView()
        .environmentObject(SharedState())
}
