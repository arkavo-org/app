import ArkavoSocial
import SwiftUI

// MARK: - Creator Content View

/// Displays a creator's published TDF-protected content
struct CreatorContentView: View {
    let creatorPublicID: Data
    @StateObject private var viewModel = CreatorContentViewModel()
    @State private var showingTicketInput = false
    @State private var ticketInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Published Content")
                    .font(.headline)

                Spacer()

                Button {
                    showingTicketInput = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if viewModel.contents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("No published content")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Text("Add content with a ticket")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(viewModel.contents) { content in
                    ContentCard(descriptor: content)
                }
            }

            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .task {
            await viewModel.loadContent(for: creatorPublicID)
        }
        .sheet(isPresented: $showingTicketInput) {
            TicketInputSheet(
                ticketInput: $ticketInput,
                isPresented: $showingTicketInput,
                onFetch: { ticket in
                    Task {
                        await viewModel.fetchFromTicket(ticket, creatorPublicID: creatorPublicID)
                    }
                }
            )
        }
    }
}

// MARK: - Ticket Input Sheet

private struct TicketInputSheet: View {
    @Binding var ticketInput: String
    @Binding var isPresented: Bool
    let onFetch: (String) -> Void
    @State private var isFetching = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste content ticket", text: $ticketInput, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Content Ticket")
                } footer: {
                    Text("Enter a content ticket received from a creator to fetch their published content.")
                }

                Section {
                    Button {
                        isFetching = true
                        onFetch(ticketInput)
                        ticketInput = ""
                        isPresented = false
                    } label: {
                        HStack {
                            Spacer()
                            if isFetching {
                                ProgressView()
                            } else {
                                Text("Fetch Content")
                            }
                            Spacer()
                        }
                    }
                    .disabled(ticketInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isFetching)
                }
            }
            .navigationTitle("Enter Ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        ticketInput = ""
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Content Card

struct ContentCard: View {
    let descriptor: ContentDescriptor
    @State private var showingDetail = false

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: 12) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 80, height: 60)
                    .overlay {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(descriptor.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        if let duration = descriptor.durationSeconds {
                            Label(formatDuration(duration), systemImage: "clock")
                        }
                        Label(formatSize(descriptor.payloadSize), systemImage: "doc")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            ContentDetailView(descriptor: descriptor)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - View Model

@MainActor
class CreatorContentViewModel: ObservableObject {
    @Published var contents: [ContentDescriptor] = []
    @Published var isLoading = false
    @Published var error: String?

    private var contentService: IrohContentService? {
        ArkavoIrohManager.shared.contentService
    }

    func loadContent(for creatorPublicID: Data) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Get cached tickets for this creator
        let tickets = await ContentTicketCache.shared.tickets(for: creatorPublicID)

        guard !tickets.isEmpty else {
            // No cached content for this creator
            return
        }

        guard let service = contentService else {
            error = "Iroh not initialized"
            return
        }

        var fetched: [ContentDescriptor] = []
        for ticket in tickets {
            do {
                let descriptor = try await service.fetchContent(ticket: ticket.ticket)
                fetched.append(descriptor)
            } catch {
                print("Failed to fetch content \(ticket.ticket.prefix(20))...: \(error)")
            }
        }

        contents = fetched.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchFromTicket(_ ticket: String, creatorPublicID: Data) async {
        error = nil

        guard let service = contentService else {
            error = "Iroh not initialized"
            return
        }

        do {
            let descriptor = try await service.fetchContentWithRetry(ticket: ticket)

            // Cache the ticket for this creator
            let contentTicket = ContentTicket(
                ticket: ticket,
                contentID: descriptor.contentID,
                version: descriptor.version,
                creatorPublicID: creatorPublicID
            )
            await ContentTicketCache.shared.cache(contentTicket, for: descriptor.contentID)

            // Add to displayed contents if not already present
            if !contents.contains(where: { $0.id == descriptor.id }) {
                contents.insert(descriptor, at: 0)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    CreatorContentView(creatorPublicID: Data(repeating: 0, count: 32))
        .padding()
}
