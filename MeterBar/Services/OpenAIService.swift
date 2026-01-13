import Foundation
import Combine

class OpenAIService {
    static let shared = OpenAIService()

    private let authManager = AuthenticationManager.shared
    private let baseURL = "https://api.openai.com"

    private init() {}

    func fetchUsageMetrics() async throws -> UsageMetrics {
        guard let adminKey = authManager.openaiAdminKey else {
            throw ServiceError.notAuthenticated
        }

        // Calculate time range: last 7 days (Unix timestamps)
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

        let startTime = Int(startDate.timeIntervalSince1970)
        let endTime = Int(endDate.timeIntervalSince1970)

        // Build URL with query parameters
        var components = URLComponents(string: "\(baseURL)/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: String(startTime)),
            URLQueryItem(name: "end_time", value: String(endTime)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "group_by", value: "model")
        ]

        guard let url = components.url else {
            throw ServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
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

        let responseData = try decoder.decode(OpenAIUsageResponse.self, from: data)

        // Aggregate all usage data
        var totalInputTokens: Double = 0
        var totalOutputTokens: Double = 0
        var totalRequests: Double = 0

        for bucket in responseData.data {
            for result in bucket.results {
                totalInputTokens += Double(result.inputTokens ?? 0)
                totalOutputTokens += Double(result.outputTokens ?? 0)
                totalRequests += Double(result.numModelRequests ?? 0)
            }
        }

        let totalTokens = totalInputTokens + totalOutputTokens

        // Create usage metrics
        // Note: OpenAI doesn't have fixed "limits" in the usage API - this shows actual usage
        let weeklyUsage = UsageLimit(
            used: totalTokens,
            total: max(totalTokens * 1.5, 1000000), // Show relative to usage or 1M baseline
            resetTime: Calendar.current.date(byAdding: .day, value: 7, to: startDate)
        )

        return UsageMetrics(
            service: .openai,
            sessionLimit: nil,
            weeklyLimit: weeklyUsage,
            codeReviewLimit: nil
        )
    }
}

// MARK: - Response Models

struct OpenAIUsageResponse: Codable {
    let object: String?
    let data: [OpenAIUsageBucket]
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

struct OpenAIUsageBucket: Codable {
    let object: String?
    let startTime: Int?
    let endTime: Int?
    let results: [OpenAIUsageResult]

    enum CodingKeys: String, CodingKey {
        case object
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }
}

struct OpenAIUsageResult: Codable {
    let object: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let inputCachedTokens: Int?
    let inputAudioTokens: Int?
    let outputAudioTokens: Int?
    let numModelRequests: Int?
    let projectId: String?
    let userId: String?
    let apiKeyId: String?
    let model: String?
    let batch: Bool?

    enum CodingKeys: String, CodingKey {
        case object
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case inputCachedTokens = "input_cached_tokens"
        case inputAudioTokens = "input_audio_tokens"
        case outputAudioTokens = "output_audio_tokens"
        case numModelRequests = "num_model_requests"
        case projectId = "project_id"
        case userId = "user_id"
        case apiKeyId = "api_key_id"
        case model
        case batch
    }
}
