import Foundation

/// Budget status response from arkavo-edge GetBudgetStatus JSON-RPC call
struct BudgetStatusResponse: Codable {
    let sessionSpentUsd: Double?
    let hourlySpentUsd: Double?
    let dailySpentUsd: Double?
    let monthlySpentUsd: Double?
    let totalSpentUsd: Double?
    let dailyLimitUsd: Double?
    let monthlyLimitUsd: Double?
    let breakdown: BudgetBreakdown?

    enum CodingKeys: String, CodingKey {
        case sessionSpentUsd = "session_spent_usd"
        case hourlySpentUsd = "hourly_spent_usd"
        case dailySpentUsd = "daily_spent_usd"
        case monthlySpentUsd = "monthly_spent_usd"
        case totalSpentUsd = "total_spent_usd"
        case dailyLimitUsd = "daily_limit_usd"
        case monthlyLimitUsd = "monthly_limit_usd"
        case breakdown
    }
}

/// Budget breakdown by provider and model
struct BudgetBreakdown: Codable {
    let byProvider: [ProviderSpend]?
    let byModel: [ModelSpend]?

    enum CodingKeys: String, CodingKey {
        case byProvider = "by_provider"
        case byModel = "by_model"
    }
}

/// Spending for a single provider
struct ProviderSpend: Codable, Identifiable {
    let provider: String
    let spentUsd: Double

    var id: String { provider }

    enum CodingKeys: String, CodingKey {
        case provider
        case spentUsd = "spent_usd"
    }
}

/// Spending for a single model
struct ModelSpend: Codable, Identifiable {
    let model: String
    let spentUsd: Double
    let requestCount: Int?

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case spentUsd = "spent_usd"
        case requestCount = "request_count"
    }
}

/// Configuration for agent budget caps
struct AgentBudgetConfig: Codable {
    var dailyLimitUsd: Double?
    var monthlyLimitUsd: Double?

    enum CodingKeys: String, CodingKey {
        case dailyLimitUsd = "daily_limit_usd"
        case monthlyLimitUsd = "monthly_limit_usd"
    }
}
