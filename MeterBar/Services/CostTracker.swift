import Foundation

@MainActor
class CostTracker: ObservableObject {
    static let shared = CostTracker()

    @Published var costSummary: CostSummary?
    @Published var isScanning: Bool = false
    @Published var lastScanDate: Date?

    // Claude pricing per million tokens (approximate as of Jan 2025)
    private let pricing: [String: TokenPricing] = [
        "claude-sonnet": TokenPricing(input: 3.0, output: 15.0, cacheCreation: 3.75, cacheRead: 0.30),
        "claude-opus": TokenPricing(input: 15.0, output: 75.0, cacheCreation: 18.75, cacheRead: 1.50),
        "claude-haiku": TokenPricing(input: 0.25, output: 1.25, cacheCreation: 0.30, cacheRead: 0.03),
        "default": TokenPricing(input: 3.0, output: 15.0, cacheCreation: 3.75, cacheRead: 0.30)
    ]

    private init() {}

    func scanCosts(days: Int = 30) async {
        isScanning = true
        defer { isScanning = false }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var allCosts: [TokenCost] = []

        // Scan Claude Code sessions
        if let claudeCost = await scanClaudeCodeSessions(since: cutoffDate) {
            allCosts.append(claudeCost)
        }

        // Calculate summary
        let totalCost = allCosts.reduce(0) { $0 + $1.estimatedCostUSD }
        let totalTokens = allCosts.reduce(0) { $0 + $1.totalTokens }

        costSummary = CostSummary(
            costs: allCosts,
            totalCostUSD: totalCost,
            totalTokens: totalTokens,
            periodDays: days
        )
        lastScanDate = Date()
    }

    private func scanClaudeCodeSessions(since cutoffDate: Date) async -> TokenCost? {
        let claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")

        guard FileManager.default.fileExists(atPath: claudeDir.path) else {
            return nil
        }

        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0
        var sessionCount = 0
        var earliestDate = Date()
        var latestDate = cutoffDate

        do {
            let projectDirs = try FileManager.default.contentsOfDirectory(
                at: claudeDir,
                includingPropertiesForKeys: nil
            )

            for projectDir in projectDirs {
                guard projectDir.hasDirectoryPath || projectDir.pathExtension == "" else { continue }

                // Find all .jsonl files in each project
                let jsonlFiles = try FileManager.default.contentsOfDirectory(
                    at: projectDir,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                ).filter { $0.pathExtension == "jsonl" }

                for jsonlFile in jsonlFiles {
                    // Check file modification date
                    let attrs = try jsonlFile.resourceValues(forKeys: [.contentModificationDateKey])
                    guard let modDate = attrs.contentModificationDate, modDate >= cutoffDate else {
                        continue
                    }

                    // Parse the session file
                    let (input, output, cacheCreate, cacheReadTokens, dates) = parseSessionFile(at: jsonlFile, since: cutoffDate)

                    if input > 0 || output > 0 {
                        totalInput += input
                        totalOutput += output
                        totalCacheCreation += cacheCreate
                        totalCacheRead += cacheReadTokens
                        sessionCount += 1

                        if let minDate = dates.min(), minDate < earliestDate {
                            earliestDate = minDate
                        }
                        if let maxDate = dates.max(), maxDate > latestDate {
                            latestDate = maxDate
                        }
                    }
                }
            }
        } catch {
            print("Error scanning Claude sessions: \(error)")
            return nil
        }

        guard totalInput > 0 || totalOutput > 0 else { return nil }

        // Calculate cost using Sonnet pricing (most common model)
        let pricing = self.pricing["claude-sonnet"] ?? self.pricing["default"]!
        let cost = calculateCost(
            input: totalInput,
            output: totalOutput,
            cacheCreation: totalCacheCreation,
            cacheRead: totalCacheRead,
            pricing: pricing
        )

        return TokenCost(
            provider: .claudeCode,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheCreationTokens: totalCacheCreation,
            cacheReadTokens: totalCacheRead,
            estimatedCostUSD: cost,
            sessionCount: sessionCount,
            periodStart: earliestDate,
            periodEnd: latestDate
        )
    }

    private func parseSessionFile(at url: URL, since cutoffDate: Date) -> (input: Int, output: Int, cacheCreation: Int, cacheRead: Int, dates: [Date]) {
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0
        var dates: [Date] = []

        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return (0, 0, 0, 0, [])
        }

        let lines = content.components(separatedBy: .newlines)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines where !line.isEmpty {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            // Check timestamp
            if let timestampStr = json["timestamp"] as? String,
               let timestamp = dateFormatter.date(from: timestampStr) {
                guard timestamp >= cutoffDate else { continue }
                dates.append(timestamp)
            }

            // Extract usage from message
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any] {
                if let input = usage["input_tokens"] as? Int {
                    totalInput += input
                }
                if let output = usage["output_tokens"] as? Int {
                    totalOutput += output
                }
                if let cacheCreation = usage["cache_creation_input_tokens"] as? Int {
                    totalCacheCreation += cacheCreation
                }
                if let cacheRead = usage["cache_read_input_tokens"] as? Int {
                    totalCacheRead += cacheRead
                }
            }
        }

        return (totalInput, totalOutput, totalCacheCreation, totalCacheRead, dates)
    }

    private func calculateCost(input: Int, output: Int, cacheCreation: Int, cacheRead: Int, pricing: TokenPricing) -> Double {
        let inputCost = Double(input) / 1_000_000 * pricing.input
        let outputCost = Double(output) / 1_000_000 * pricing.output
        let cacheCreationCost = Double(cacheCreation) / 1_000_000 * pricing.cacheCreation
        let cacheReadCost = Double(cacheRead) / 1_000_000 * pricing.cacheRead
        return inputCost + outputCost + cacheCreationCost + cacheReadCost
    }
}

private struct TokenPricing {
    let input: Double      // per million tokens
    let output: Double     // per million tokens
    let cacheCreation: Double
    let cacheRead: Double
}
