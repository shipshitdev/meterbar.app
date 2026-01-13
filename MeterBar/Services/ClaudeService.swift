import Foundation
import Combine

class ClaudeService {
    static let shared = ClaudeService()

    private let authManager = AuthenticationManager.shared
    private let baseURL = "https://api.anthropic.com"

    private init() {}

    func fetchUsageMetrics() async throws -> UsageMetrics {
        guard let adminKey = authManager.claudeAdminKey else {
            throw ServiceError.notAuthenticated
        }

        // Calculate time range: last 7 days
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        let startingAt = dateFormatter.string(from: startDate)
        let endingAt = dateFormatter.string(from: endDate)

        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)/v1/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: startingAt),
            URLQueryItem(name: "ending_at", value: endingAt),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by[]", value: "model")
        ]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw ServiceError.notAuthenticated
            }
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ServiceError.apiError("API error (\(httpResponse.statusCode)): \(errorMessage)")
        }

        // Parse response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let responseData = try decoder.decode(AnthropicUsageResponse.self, from: data)

        // Aggregate all usage data
        var totalInputTokens: Double = 0
        var totalOutputTokens: Double = 0
        var totalCachedTokens: Double = 0

        for bucket in responseData.data {
            totalInputTokens += Double(bucket.inputTokens ?? 0)
            totalOutputTokens += Double(bucket.outputTokens ?? 0)
            totalCachedTokens += Double(bucket.inputCachedTokens ?? 0)
        }

        let totalTokens = totalInputTokens + totalOutputTokens

        // Create usage metrics
        // Note: Anthropic doesn't have fixed "limits" - this shows actual usage
        let weeklyUsage = UsageLimit(
            used: totalTokens,
            total: max(totalTokens * 1.5, 1000000), // Show relative to usage or 1M baseline
            resetTime: Calendar.current.date(byAdding: .day, value: 7, to: startDate)
        )

        return UsageMetrics(
            service: .claude,
            sessionLimit: nil, // Anthropic doesn't have session limits
            weeklyLimit: weeklyUsage,
            codeReviewLimit: nil
        )
    }
}

// MARK: - Response Models

struct AnthropicUsageResponse: Codable {
    let data: [AnthropicUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct AnthropicUsageBucket: Codable {
    let bucketStartTime: String?
    let bucketEndTime: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let inputCachedTokens: Int?
    let cacheCreationInputTokens: Int?
    let model: String?
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case bucketStartTime = "bucket_start_time"
        case bucketEndTime = "bucket_end_time"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case model
        case workspaceId = "workspace_id"
    }
}

enum ServiceError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case apiError(String)
    case parsingError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please set up your Admin API key in settings."
        case .invalidURL:
            return "Invalid URL"
        case .apiError(let message):
            return message
        case .parsingError:
            return "Failed to parse response"
        }
    }
}
