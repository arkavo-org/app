import ArkavoSocial
import SwiftUI

// MARK: - FairPlay Test View

/// Test view for playing FairPlay protected content from Iroh network
@available(iOS 26.0, macOS 26.0, *)
struct FairPlayTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FairPlayTestViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let error = viewModel.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)

                        Text("Error")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            Task {
                                await viewModel.loadContent()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top)
                    }
                } else if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)

                        Text(viewModel.loadingMessage)
                            .foregroundColor(.gray)
                    }
                } else if let tdfData = viewModel.tdfData,
                          let manifest = viewModel.manifest {
                    // Show FMP4 player with fetched content
                    FMP4VideoPlayerView(tdfData: tdfData, manifest: manifest)
                }
            }
            .navigationTitle("FairPlay Test")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .task {
            await viewModel.loadContent()
        }
    }
}

// MARK: - FairPlay Test View Model

@MainActor
final class FairPlayTestViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var loadingMessage = "Connecting to Iroh..."
    @Published var error: String?
    @Published var tdfData: Data?
    @Published var manifest: TDFManifestLite?

    // Published content ticket (Iroh blob ticket for ContentDescriptor)
    static let ticket = "blobacpw6o6wsdainctaomb4kyxrnitiygxg7ifmnfg6nd42jrxqdyd54ajpnb2hi4dthixs65ltmuys2mjoojswyylzfzxdaltjojxwqlldmfxgc4tzfzuxe33ifzwgs3tlfyxraaakaaaghi5uamaauaaarkr3iayamlurkwvdwqbqbqaaaibkhnadaetacakhysai5aaaaaaaaaaaspm2jnadaetacakhysai5aaaaaaaaaaaudekjnadaetacakhysai5aaaplpn3kinla5kjnadaetacakhysai5aaicuphdlacgjf2jnadaetacakhysai5adyloqjjrt7gzr2jnadaetacakhysai5aefurowhqemps4kjnadaetacakhysai5aei55p3pqr4yo72jnadaetacakhysai5af44zds5l5buvhkjnadaetacakhysai5agbufcfcdhbco72jnadaetacakhysai5agjxgehklbnv57kjnadaetacakhysai5agmsiv4jqklkigkjnadaetacakhysai5agub4sxazfq4h2kjnadaetacakhysai5aacza3vxyyv2lvkdo7ba6vmueyh7nhus7kabnx3z7zbob7ohcrbru"

    func loadContent() async {
        isLoading = true
        error = nil
        tdfData = nil
        manifest = nil

        do {
            // 1. Get Iroh content service
            loadingMessage = "Connecting to Iroh network..."
            guard let service = await ArkavoIrohManager.shared.contentService else {
                throw FairPlayTestError.irohNotInitialized
            }

            // 2. Fetch ContentDescriptor using ticket
            loadingMessage = "Fetching content descriptor..."
            print("🎬 [FairPlayTest] Fetching descriptor with ticket: \(Self.ticket.prefix(50))...")

            let descriptor = try await service.fetchContentWithRetry(ticket: Self.ticket)
            print("🎬 [FairPlayTest] Descriptor fetched: \(descriptor.title)")
            print("🎬 [FairPlayTest] Asset ID: \(descriptor.manifest.assetID)")
            print("🎬 [FairPlayTest] Payload size: \(descriptor.payloadSize) bytes")

            // 3. Fetch TDF payload using payloadTicket
            loadingMessage = "Downloading content (\(formatSize(descriptor.payloadSize)))..."
            print("🎬 [FairPlayTest] Fetching payload with ticket: \(descriptor.payloadTicket.prefix(50))...")

            let payload = try await service.fetchPayloadWithRetry(payloadTicket: descriptor.payloadTicket)
            print("🎬 [FairPlayTest] Payload fetched: \(payload.count) bytes")

            // 4. Set data for player view
            self.tdfData = payload
            self.manifest = descriptor.manifest
            isLoading = false

        } catch {
            print("🎬 [FairPlayTest] Error: \(error)")
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Errors

enum FairPlayTestError: Error, LocalizedError {
    case irohNotInitialized
    case contentNotFound
    case invalidTicket

    var errorDescription: String? {
        switch self {
        case .irohNotInitialized:
            return "Iroh network not initialized. Please ensure you're signed in."
        case .contentNotFound:
            return "Content not found on Iroh network"
        case .invalidTicket:
            return "Invalid content ticket"
        }
    }
}

// MARK: - Preview

#Preview {
    FairPlayTestView()
}
