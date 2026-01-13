import Foundation
import AppKit
import Combine

class ClaudeCodeLocalService: ObservableObject {
    static let shared = ClaudeCodeLocalService()

    // Working endpoint (discovered via testing)
    private let usageEndpoint = "https://api.anthropic.com/api/oauth/usage"

    private let baseURL = "https://api.anthropic.com"
    private let keychainService = "Claude Code-credentials"

    // URLSession with timeout configuration
    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30.0
        configuration.timeoutIntervalForResource = 60.0
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    @Published private(set) var hasAccess: Bool = false
    @Published private(set) var subscriptionType: String?
    @Published private(set) var rateLimitTier: String?
    @Published private(set) var lastError: ServiceError?

    private init() {
        // Check if we have Claude Code credentials on init
        if let _ = getOAuthToken() {
            hasAccess = true
        }
    }

    // MARK: - Keychain Access

    /// Get OAuth token from Claude Code's keychain storage
    func getOAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse the JSON to extract the access token
        guard let jsonData = jsonString.data(using: .utf8),
              let credentials = try? JSONDecoder().decode(ClaudeCodeCredentials.self, from: jsonData) else {
            return nil
        }

        // Update subscription info
        DispatchQueue.main.async {
            self.subscriptionType = credentials.claudeAiOauth.subscriptionType
            self.rateLimitTier = credentials.claudeAiOauth.rateLimitTier
            self.hasAccess = true
        }

        return credentials.claudeAiOauth.accessToken
    }

    /// Check and update access status
    func checkAccess() {
        if let _ = getOAuthToken() {
            hasAccess = true
        } else {
            hasAccess = false
            subscriptionType = nil
            rateLimitTier = nil
        }
    }

    // MARK: - Usage Fetching

    func fetchUsageMetrics() async throws -> UsageMetrics {
        guard let token = getOAuthToken() else {
            let error = ServiceError.notAuthenticated
            await MainActor.run {
                self.lastError = error
                self.hasAccess = false
            }
            throw error
        }

        guard let url = URL(string: usageEndpoint) else {
            throw ServiceError.apiError("Invalid usage endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ServiceError.apiError("Invalid response type")
            }

            if httpResponse.statusCode == 401 {
                await MainActor.run {
                    self.hasAccess = false
                    self.lastError = ServiceError.notAuthenticated
                }
                throw ServiceError.notAuthenticated
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let usageResponse = try decoder.decode(ClaudeCodeUsageResponse.self, from: data)

            await MainActor.run {
                self.lastError = nil
            }

            // Session limit = 5-hour window
            let sessionLimit = UsageLimit(
                used: usageResponse.fiveHour.utilization,
                total: 100.0,
                resetTime: usageResponse.fiveHour.resetsAt
            )

            // Weekly limit = 7-day window (all models)
            let weeklyLimit = UsageLimit(
                used: usageResponse.sevenDay.utilization,
                total: 100.0,
                resetTime: usageResponse.sevenDay.resetsAt
            )

            // Sonnet-only weekly limit (if available)
            var sonnetLimit: UsageLimit? = nil
            if let sonnet = usageResponse.sevenDaySonnet {
                sonnetLimit = UsageLimit(
                    used: sonnet.utilization,
                    total: 100.0,
                    resetTime: sonnet.resetsAt
                )
            }

            return UsageMetrics(
                service: .claudeCode,
                sessionLimit: sessionLimit,
                weeklyLimit: weeklyLimit,
                codeReviewLimit: sonnetLimit
            )
        } catch let urlError as URLError {
            let errorMessage: String
            switch urlError.code {
            case .notConnectedToInternet:
                errorMessage = "No internet connection"
            case .cannotFindHost, .dnsLookupFailed:
                errorMessage = "DNS lookup failed"
            case .timedOut:
                errorMessage = "Request timed out"
            default:
                errorMessage = urlError.localizedDescription
            }
            let error = ServiceError.apiError(errorMessage)
            await MainActor.run { self.lastError = error }
            throw error
        } catch let error as ServiceError {
            throw error
        } catch {
            let serviceError = ServiceError.parsingError
            await MainActor.run { self.lastError = serviceError }
            throw serviceError
        }
    }
}

// MARK: - Response Models

struct ClaudeCodeCredentials: Codable {
    let claudeAiOauth: ClaudeAiOAuth

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }
}

struct ClaudeAiOAuth: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int64
    let scopes: [String]
    let subscriptionType: String?
    let rateLimitTier: String?
}

struct ClaudeCodeUsageResponse: Codable {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindow: Codable {
    let utilization: Double
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}
