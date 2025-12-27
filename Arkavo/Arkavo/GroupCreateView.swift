import MultipeerConnectivity
import SwiftUI
import UIKit

struct GroupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sharedState: SharedState
    @StateObject var viewModel: GroupViewModel

    @State private var groupName = ""
    @StateObject private var peerManager: PeerDiscoveryManager = ViewModelFactory.shared.getPeerDiscoveryManager()
    @State private var isPeerSearchActive = false
    @State private var pulsate: Bool = false

    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isNameFieldFocused: Bool

    private let systemMargin: CGFloat = 16

    var body: some View {
        Form {
            Section {
                TextField("Group Name", text: $groupName)
                    .focused($isNameFieldFocused)
                    .autocapitalization(.words)
                    .textContentType(.organizationName)
            } header: {
                Text("Group Details")
            } footer: {
                Text("This will be the name of your new group")
            }
            peerDiscoverySection()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    sharedState.showCreateView = false
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Create") {
                    Task {
                        await createGroup()
                        sharedState.showCreateView = false
                        dismiss()
                    }
                }
                .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { /* Dismisses alert */ }
        } message: {
            Text(errorMessage)
        }
    }

    private func peerDiscoverySection() -> some View {
        Section("Connect to Peers (Optional)") {
            VStack(alignment: .leading, spacing: 8) {
                innerCirclePeerDiscoveryUI()
            }
        }
    }

    private func innerCirclePeerDiscoveryUI() -> some View {
        VStack(spacing: systemMargin) {
            Button {
                Task { await togglePeerSearch() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isPeerSearchActive ? "stop.circle.fill" : "antenna.radiowaves.left.and.right.circle.fill")
                        .font(.system(size: 22))
                    Text(isPeerSearchActive ? "Stop Discovery" : "Discover Peers")
                        .font(.body)
                        .fontWeight(.semibold)
                    if isPeerSearchActive {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                            .tint(.blue)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, systemMargin)
                .frame(maxWidth: .infinity)
                .background(isPeerSearchActive ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                .foregroundColor(isPeerSearchActive ? .red : .blue)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            discoveredPeersView
        }
    }

    private func togglePeerSearch() async {
        isPeerSearchActive.toggle()

        if isPeerSearchActive {
            do {
                try await peerManager.setupMultipeerConnectivity()
                try peerManager.startSearchingForPeers()
                presentBrowserController()
            } catch {
                print("Failed to start peer search: \(error.localizedDescription)")
                isPeerSearchActive = false
                errorMessage = "Failed to start peer discovery: \(error.localizedDescription)"
                showError = true
            }
        } else {
            peerManager.stopSearchingForPeers()
        }
    }

    private var discoveredPeersView: some View {
        VStack(spacing: 8) {
            let peerCount = peerManager.connectedPeers.count
            let connectionStatus = peerManager.connectionStatus

            HStack {
                connectionStatusIndicator(status: connectionStatus)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                    Text("\(peerCount) \(peerCount == 1 ? "Peer" : "Peers")")
                        .font(.caption)
                        .foregroundColor(peerCount > 0 ? .blue : .secondary)
                }
            }

            if case .searching = connectionStatus {
                Text("Scanning for nearby devices...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            if case let .failed(error) = connectionStatus {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error.localizedDescription).font(.caption).foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            if peerCount > 0 {
                Divider().padding(.vertical, 8)
                Text("Discovered Devices (\(peerCount))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                LazyVStack(spacing: 8) {
                    ForEach(peerManager.connectedPeers, id: \.self) { peer in
                        peerRow(peer: peer, profile: peerManager.connectedPeerProfiles[peer])
                    }
                }
            } else if isPeerSearchActive {
                searchingStateView()
            } else {
                emptyStateView()
            }
        }
    }

    private func connectionStatusIndicator(status: ConnectionStatus) -> some View {
        HStack(spacing: 5) {
            Group {
                switch status {
                case .idle:
                    Circle().fill(Color.gray)
                case .searching:
                    Circle()
                        .fill(Color.blue)
                        .opacity(0.8)
                        .scaleEffect(pulsate ? 1.2 : 0.8)
                        .animation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsate)
                case .connecting:
                    Circle().fill(Color.orange)
                case .connected:
                    Circle().fill(Color.green)
                case .failed:
                    Circle().fill(Color.red)
                }
            }
            .frame(width: 10, height: 10)

            Text(statusText(for: status))
                .font(.caption2)
                .foregroundColor(statusColor(for: status))
        }
        .padding(.vertical, 4)
        .onAppear { pulsate = true }
        .onDisappear { pulsate = false }
    }

    private func statusText(for status: ConnectionStatus) -> String {
        switch status {
        case .idle: "Inactive"
        case .searching: "Searching"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .failed: "Failed"
        }
    }

    private func statusColor(for status: ConnectionStatus) -> Color {
        switch status {
        case .idle: .gray
        case .searching: .blue
        case .connecting: .orange
        case .connected: .green
        case .failed: .red
        }
    }

    private func emptyStateView() -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 20)
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundColor(.gray)

            Text("No Peers Discovered")
                .font(.headline)
                .foregroundColor(.primary)

            Text("Tap 'Discover Peers' to find nearby devices.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, systemMargin)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, 8)
    }

    private func searchingStateView() -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 10)
            SignalPulseView().frame(width: 50, height: 50)
            Text("Scanning for Devices...").font(.callout).foregroundColor(.secondary)
            Text("Ensure other devices are also searching.").font(.caption2).foregroundColor(.secondary.opacity(0.8))
            Spacer().frame(height: 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.3))
        .cornerRadius(8)
        .padding(.top, 8)
    }

    private func presentBrowserController() {
        if let browserVC = peerManager.getPeerBrowser(),
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootController = windowScene.windows.first?.rootViewController
        {
            rootController.presentedViewController?.dismiss(animated: false)
            rootController.present(browserVC, animated: true)
        } else {
            print("Could not get browser view controller or root view controller.")
        }
    }

    private func peerRow(peer: MCPeerID, profile: Profile?) -> some View {
        HStack(spacing: systemMargin) {
            Circle()
                .fill(profile != nil ? Color.green : Color.orange)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: profile != nil ? "checkmark" : "hourglass")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name ?? peer.displayName)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(profile != nil ? "Verified" : "Connecting...")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let time = peerManager.peerConnectionTimes[peer] {
                    Text("Connected \(connectionTimeString(time))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func connectionTimeString(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)

        if timeInterval < 60 { return "just now" }
        if timeInterval < 3600 { let minutes = Int(timeInterval / 60); return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        if timeInterval < 86400 { let hours = Int(timeInterval / 3600); return "\(hours) hour\(hours == 1 ? "" : "s") ago" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    struct SignalPulseView: View {
        @State private var scale: CGFloat = 1.0
        @State private var rotation: Double = 0.0
        @State private var pulsate: Bool = false

        var body: some View {
            ZStack {
                ZStack {
                    ForEach(0 ..< 3) { i in
                        Circle().stroke(Color.blue.opacity(0.7 - Double(i) * 0.2), lineWidth: 1).scaleEffect(scale - CGFloat(i) * 0.1)
                    }
                }.scaleEffect(pulsate ? 1.2 : 0.8)
                Circle().trim(from: 0.2, to: 0.8).stroke(Color.blue.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 3])).rotationEffect(.degrees(rotation)).scaleEffect(0.7)
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 12, height: 12)
                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                }
            }
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulsate = true }
                withAnimation(Animation.linear(duration: 3).repeatForever(autoreverses: false)) { rotation = 360 }
                withAnimation(Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)) { scale = 1.1 }
            }
            .onDisappear {
                pulsate = false
            }
        }
    }

    private func createGroup() async {
        do {
            let newStream = Stream(
                creatorPublicID: ViewModelFactory.shared.getCurrentProfile()!.publicID,
                name: groupName,
                policies: Policies(admission: .openInvitation, interaction: .open, age: .forAll)
            )
            print("Creating new stream: \(newStream.streamName) (\(newStream.publicID.base58EncodedString))")

            let account = ViewModelFactory.shared.getCurrentAccount()!
            PersistenceController.shared.mainContext.insert(newStream)
            account.streams.append(newStream)
            print("   Added new stream to account.")

            try await PersistenceController.shared.saveChanges()
            print("   Saved changes to persistence.")

            await MainActor.run {
                sharedState.selectedStreamPublicID = newStream.publicID
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to create group: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
