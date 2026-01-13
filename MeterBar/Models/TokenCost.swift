import Foundation

struct TokenCost: Codable, Identifiable {
    var id: String { provider.rawValue }

    let provider: ServiceType
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let estimatedCostUSD: Double
    let sessionCount: Int
    let periodStart: Date
    let periodEnd: Date

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    var formattedCost: String {
        String(format: "$%.2f", estimatedCostUSD)
    }

    var formattedTokens: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: totalTokens)) ?? "\(totalTokens)"
    }
}

struct CostSummary {
    let costs: [TokenCost]
    let totalCostUSD: Double
    let totalTokens: Int
    let periodDays: Int

    var formattedTotalCost: String {
        String(format: "$%.2f", totalCostUSD)
    }

    var averageDailyCost: Double {
        guard periodDays > 0 else { return 0 }
        return totalCostUSD / Double(periodDays)
    }

    var formattedDailyCost: String {
        String(format: "$%.2f/day", averageDailyCost)
    }
}
