import ArkavoKit
import SwiftUI

/// Dashboard view for AI agent budget monitoring and controls
struct BudgetDashboardView: View {
    @ObservedObject var agentService: CreatorAgentService
    @State private var budgetStatus: BudgetStatusResponse?
    @State private var isLoading = false
    @State private var editingDailyCap: String = ""
    @State private var errorMessage: String?
    @State private var showError = false

    /// First connected remote agent ID for budget queries
    private var connectedRemoteAgentId: String? {
        agentService.discoveredAgents.first { agent in
            agent.url != "local://in-process" && agentService.isConnected(to: agent.id)
        }?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("AI Budget")
                        .font(.headline)
                    Spacer()
                    Button(action: { Task { await refreshBudget() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || connectedRemoteAgentId == nil)
                }

                if connectedRemoteAgentId == nil {
                    noConnectionView
                } else if let status = budgetStatus {
                    budgetStatusView(status)
                } else if isLoading {
                    ProgressView("Loading budget data...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    Button("Load Budget Status") {
                        Task { await refreshBudget() }
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                // Daily cap control
                dailyCapSection
            }
            .padding()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { /* Dismisses alert */ }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            editingDailyCap = String(format: "%.2f", agentService.dailyBudgetCap)
            if connectedRemoteAgentId != nil {
                Task { await refreshBudget() }
            }
        }
    }

    // MARK: - No Connection

    private var noConnectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            Text("No remote agent connected")
                .font(.subheadline)
            Text("Connect to an arkavo-edge instance to view budget data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Budget Status

    @ViewBuilder
    private func budgetStatusView(_ status: BudgetStatusResponse) -> some View {
        // Daily spend gauge
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Spending")
                .font(.subheadline)
                .fontWeight(.medium)

            let dailySpent = status.dailySpentUsd ?? 0
            let dailyLimit = status.dailyLimitUsd ?? agentService.dailyBudgetCap

            HStack {
                ProgressView(value: min(dailySpent / max(dailyLimit, 0.01), 1.0))
                    .tint(dailySpent > dailyLimit * 0.8 ? .orange : .blue)

                Text(String(format: "$%.2f / $%.2f", dailySpent, dailyLimit))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))

        // Spending summary
        HStack(spacing: 16) {
            spendCard(title: "Session", amount: status.sessionSpentUsd ?? 0)
            spendCard(title: "Hourly", amount: status.hourlySpentUsd ?? 0)
            spendCard(title: "Monthly", amount: status.monthlySpentUsd ?? 0)
            spendCard(title: "Total", amount: status.totalSpentUsd ?? 0)
        }

        // Provider breakdown
        if let breakdown = status.breakdown {
            if let providers = breakdown.byProvider, !providers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Provider")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(providers) { provider in
                        HStack {
                            Text(provider.provider)
                                .font(.caption)
                            Spacer()
                            Text(String(format: "$%.4f", provider.spentUsd))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            if let models = breakdown.byModel, !models.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("By Model")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ForEach(models) { model in
                        HStack {
                            Text(model.model)
                                .font(.caption)
                            Spacer()
                            if let count = model.requestCount {
                                Text("\(count) req")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Text(String(format: "$%.4f", model.spentUsd))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func spendCard(title: String, amount: Double) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(format: "$%.4f", amount))
                .font(.caption)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Daily Cap Section

    private var dailyCapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Budget Cap")
                .font(.headline)

            HStack(spacing: 8) {
                Text("Daily limit: $")
                    .font(.subheadline)
                TextField("5.00", text: $editingDailyCap)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)

                Button("Apply") {
                    if let value = Double(editingDailyCap) {
                        agentService.dailyBudgetCap = value
                        if let agentId = connectedRemoteAgentId {
                            Task {
                                do {
                                    try await agentService.setBudgetCap(agentId: agentId, daily: value)
                                } catch {
                                    errorMessage = "Failed to set budget: \(error.localizedDescription)"
                                    showError = true
                                }
                            }
                        }
                    }
                }
                .disabled(Double(editingDailyCap) == nil)
            }

            Text("Sets the maximum daily AI spending. Enforced by arkavo-edge.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Actions

    private func refreshBudget() async {
        guard let agentId = connectedRemoteAgentId else { return }
        isLoading = true
        do {
            budgetStatus = try await agentService.getBudgetStatus(agentId: agentId)
        } catch {
            errorMessage = "Failed to load budget: \(error.localizedDescription)"
            showError = true
        }
        isLoading = false
    }
}
