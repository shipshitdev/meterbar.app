import Foundation
import AppKit
import Combine

class ClaudeCodeLocalService: ObservableObject {
    static let shared = ClaudeCodeLocalService()

    // Try multiple endpoint patterns - OAuth endpoints may follow different conventions
    private let endpointPatterns = [
        "https://api.anthropic.com/v1/oauth/usage",
        "https://api.anthropic.com/api/v1/oauth/usage",
        "https://api.anthropic.com/api/oauth/usage", // Original - keep for backward compatibility
        "https://api.anthropic.com/oauth/v1/usage"
    ]

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
            print("[ClaudeCodeLocalService] No OAuth token found")
            throw error
        }

        print("[ClaudeCodeLocalService] Fetching usage data...")

        // Try each endpoint pattern until one succeeds
        var lastError: Error?
        var lastStatusCode: Int?
        var lastEndpoint: String?

        for endpoint in endpointPatterns {
            guard let url = URL(string: endpoint) else {
                print("[ClaudeCodeLocalService] Invalid URL: \(endpoint)")
                continue
            }

            lastEndpoint = endpoint
            print("[ClaudeCodeLocalService] Trying endpoint: \(endpoint)")

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
                    let error = ServiceError.apiError("Invalid response type from \(endpoint)")
                    print("[ClaudeCodeLocalService] Invalid response type from \(endpoint)")
                    lastError = error
                    continue
                }

                lastStatusCode = httpResponse.statusCode
                print("[ClaudeCodeLocalService] Response status: \(httpResponse.statusCode) from \(endpoint)")

                // Handle different status codes
                if (200...299).contains(httpResponse.statusCode) {
                    // Success - parse the response
                    print("[ClaudeCodeLocalService] Successfully fetched usage data from \(endpoint)")
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601

                    do {
                        let usageResponse = try decoder.decode(ClaudeCodeUsageResponse.self, from: data)

                        // Clear any previous errors on success
                        await MainActor.run {
                            self.lastError = nil
                        }

                        // Create usage metrics from the response
                        // Session limit = 5-hour window
                        let sessionLimit = UsageLimit(
                            used: usageResponse.fiveHour.utilization,
                            total: 100.0, // Percentage-based
                            resetTime: usageResponse.fiveHour.resetsAt
                        )

                        // Weekly limit = 7-day window (all models)
                        let weeklyLimit = UsageLimit(
                            used: usageResponse.sevenDay.utilization,
                            total: 100.0, // Percentage-based
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
                            codeReviewLimit: sonnetLimit // Repurposed for Sonnet usage
                        )
                    } catch let decodeError {
                        let errorMessage = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                        print("[ClaudeCodeLocalService] Decode error from \(endpoint): \(decodeError)")
                        print("[ClaudeCodeLocalService] Response body: \(errorMessage)")

                        // If it's a parsing error but we got a 200, the endpoint might be wrong
                        // Try next endpoint pattern
                        lastError = ServiceError.parsingError
                        continue
                    }
                } else if httpResponse.statusCode == 401 {
                    // Unauthorized - don't try other endpoints
                    await MainActor.run {
                        self.hasAccess = false
                        self.lastError = ServiceError.notAuthenticated
                    }
                    print("[ClaudeCodeLocalService] Authentication failed (401) from \(endpoint)")
                    throw ServiceError.notAuthenticated
                } else if httpResponse.statusCode == 404 {
                    // Not found - try next endpoint
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Endpoint not found"
                    print("[ClaudeCodeLocalService] Endpoint not found (404): \(endpoint) - \(errorMessage)")
                    lastError = ServiceError.apiError("Endpoint not found: \(endpoint)")
                    continue
                } else {
                    // Other error - try next endpoint but log it
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("[ClaudeCodeLocalService] HTTP error \(httpResponse.statusCode) from \(endpoint): \(errorMessage)")
                    lastError = ServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
                    continue
                }
            } catch let urlError as URLError {
                // Handle URL errors specifically
                let errorMessage: String
                switch urlError.code {
                case .notConnectedToInternet:
                    errorMessage = "No internet connection available"
                case .cannotFindHost, .dnsLookupFailed:
                    errorMessage = "Cannot resolve hostname api.anthropic.com. DNS lookup failed."
                case .timedOut:
                    errorMessage = "Request timed out after 30 seconds"
                case .networkConnectionLost:
                    errorMessage = "Network connection lost during request"
                case .cannotConnectToHost:
                    errorMessage = "Cannot connect to api.anthropic.com"
                default:
                    errorMessage = "Network error: \(urlError.localizedDescription) (code: \(urlError.code.rawValue))"
                }

                print("[ClaudeCodeLocalService] URL error from \(endpoint): \(urlError.code.rawValue) - \(errorMessage)")
                lastError = ServiceError.apiError(errorMessage)
                continue
            } catch {
                print("[ClaudeCodeLocalService] Unexpected error from \(endpoint): \(error)")
                lastError = error
                continue
            }
        }

        // All endpoints failed
        let finalError: ServiceError
        if let statusCode = lastStatusCode {
            if statusCode == 404 {
                finalError = ServiceError.apiError("Usage endpoint not found. Tried: \(endpointPatterns.joined(separator: ", ")). The OAuth usage API endpoint may have changed or may not be available.")
            } else {
                finalError = ServiceError.apiError("All endpoint attempts failed. Last error: HTTP \(statusCode) from \(lastEndpoint ?? "unknown")")
            }
        } else if let urlError = lastError as? URLError {
            if urlError.code == .cannotFindHost || urlError.code == .dnsLookupFailed {
                finalError = ServiceError.apiError("DNS resolution failed for api.anthropic.com. Please check your network connection and DNS settings.")
            } else {
                finalError = ServiceError.apiError("Network error: \(urlError.localizedDescription)")
            }
        } else {
            finalError = ServiceError.apiError("Failed to fetch usage data from all endpoint patterns. Last endpoint tried: \(lastEndpoint ?? "unknown"). Error: \(lastError?.localizedDescription ?? "Unknown error")")
        }

        await MainActor.run {
            self.lastError = finalError
        }

        print("[ClaudeCodeLocalService] All endpoint attempts failed. Last endpoint: \(lastEndpoint ?? "none")")
        throw finalError
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
