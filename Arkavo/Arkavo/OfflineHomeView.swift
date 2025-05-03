import SwiftUI

struct OfflineHomeView: View {
    @EnvironmentObject private var sharedState: SharedState
    
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
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureStatusRow(
                    title: "P2P InnerCircle Messaging",
                    description: "One-time TDF secure messaging works in offline mode",
                    isAvailable: true
                )
                
                FeatureStatusRow(
                    title: "Video Feed",
                    description: "Requires internet connection",
                    isAvailable: false
                )
                
                FeatureStatusRow(
                    title: "Social Feed",
                    description: "Requires internet connection",
                    isAvailable: false
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 30)
            
            Spacer()
            
            Button {
                // Post notification to retry connection
                NotificationCenter.default.post(name: .retryConnection, object: nil)
            } label: {
                Text("Try to Reconnect")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 50)
            .padding(.bottom, 40)
        }
        .overlay(alignment: .topTrailing) {
            // Connection indicator in the corner
            HStack {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.white)
                
                Text("Offline")
                    .foregroundColor(.white)
                    .font(.caption)
                    .bold()
            }
            .padding(8)
            .background(Color.red.opacity(0.8))
            .cornerRadius(20)
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
extension Notification.Name {
    static let retryConnection = Notification.Name("RetryConnection")
}

#Preview {
    OfflineHomeView()
        .environmentObject(SharedState())
}