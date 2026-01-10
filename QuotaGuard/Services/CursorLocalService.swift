import Foundation
import AppKit
import Combine
import Network
import SQLite3

/// Service for fetching Cursor usage data using the cursor-stats approach.
/// Reads authentication token from Cursor's local SQLite database and calls dashboard APIs.
/// Based on: https://github.com/darzhang/cursor-stats-lite
class CursorLocalService: ObservableObject {
    static let shared = CursorLocalService()

    // API endpoints (discovered via testing)
    private let usageEndpoint = "https://cursor.com/api/usage"
    private let authMeEndpoint = "https://cursor.com/api/auth/me"

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
    @Published private(set) var lastError: ServiceError?

    private init() {
        // Check if we have Cursor credentials on init
        checkAccess()
    }

    // MARK: - Database Access (cursor-stats approach)

    /// Get the path to Cursor's state database
    private func getCursorDatabasePath() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let dbPath = "\(homeDir)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"

        if FileManager.default.fileExists(atPath: dbPath) {
            return dbPath
        }

        // Try alternative paths
        let alternatePaths = [
            "\(homeDir)/Library/Application Support/Cursor/state.vscdb",
            "\(homeDir)/.config/Cursor/User/globalStorage/state.vscdb"
        ]

        for path in alternatePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        return nil
    }

    /// Read access token from Cursor's SQLite database
    func getAccessTokenFromDatabase() -> (userId: String, token: String)? {
        guard let dbPath = getCursorDatabasePath() else {
            print("[CursorLocalService] Database not found at expected paths")
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            print("[CursorLocalService] Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            print("[CursorLocalService] Failed to prepare query: \(String(cString: sqlite3_errmsg(db)))")
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            print("[CursorLocalService] No token found in database")
            return nil
        }

        guard let tokenCString = sqlite3_column_text(statement, 0) else {
            print("[CursorLocalService] Failed to read token value")
            return nil
        }

        let token = String(cString: tokenCString)

        // Decode JWT to extract userId from 'sub' claim
        guard let userId = extractUserIdFromJWT(token) else {
            print("[CursorLocalService] Failed to extract userId from JWT")
            return nil
        }

        print("[CursorLocalService] Successfully retrieved token for user: \(userId.prefix(8))...")
        return (userId: userId, token: token)
    }

    /// Extract userId from JWT token's 'sub' claim
    private func extractUserIdFromJWT(_ token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        // Decode the payload (second part)
        var payload = String(parts[1])

        // Add padding if needed for base64
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        // Convert base64url to base64
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String else {
            return nil
        }

        // Extract userId from sub claim
        // Format may be "auth0|userId" or similar
        if sub.contains("|") {
            return sub.components(separatedBy: "|").last
        }

        return sub
    }

    /// Format authentication cookie for Cursor API
    private func formatAuthCookie(userId: String, token: String) -> String {
        // Format: userId::token (URL encoded)
        return "\(userId)%3A%3A\(token)"
    }

    /// Check and update access status
    func checkAccess() {
        if let _ = getAccessTokenFromDatabase() {
            hasAccess = true
        } else {
            hasAccess = false
            subscriptionType = nil
        }
    }

    // MARK: - Usage Fetching

    func fetchUsageMetrics() async throws -> UsageMetrics {
        guard let (userId, token) = getAccessTokenFromDatabase() else {
            let error = ServiceError.notAuthenticated
            await MainActor.run {
                self.lastError = error
                self.hasAccess = false
            }
            print("[CursorLocalService] No access token found in database")
            throw error
        }

        await MainActor.run {
            self.hasAccess = true
        }

        print("[CursorLocalService] Fetching usage data from Cursor API...")

        // Fetch usage data
        let usageData = try await fetchUsage(userId: userId, token: token)

        // Clear any previous errors on success
        await MainActor.run {
            self.lastError = nil
        }

        // Parse the date formatter for reset time
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetTime = dateFormatter.date(from: usageData.startOfMonth)

        // Calculate total requests and limits across all models
        var totalRequests: Double = 0
        var totalTokens: Double = 0
        var maxRequests: Double? = nil

        for (_, modelUsage) in usageData.models {
            totalRequests += Double(modelUsage.numRequests)
            totalTokens += Double(modelUsage.numTokens)
            if let maxReq = modelUsage.maxRequestUsage {
                if maxRequests == nil {
                    maxRequests = Double(maxReq)
                } else {
                    maxRequests! += Double(maxReq)
                }
            }
        }

        // Default max requests if not specified (Pro plan typically has 500 fast requests)
        let effectiveMaxRequests = maxRequests ?? 500.0

        // Create usage metrics
        // Use requests as the primary metric
        let weeklyLimit = UsageLimit(
            used: totalRequests,
            total: effectiveMaxRequests,
            resetTime: resetTime
        )

        // Token usage as session/secondary metric
        var sessionLimit: UsageLimit? = nil
        if totalTokens > 0 {
            sessionLimit = UsageLimit(
                used: totalTokens,
                total: totalTokens * 1.5, // Show relative to usage
                resetTime: resetTime
            )
        }

        print("[CursorLocalService] Successfully fetched Cursor usage data")
        print("[CursorLocalService] Total requests: \(Int(totalRequests)), Max: \(Int(effectiveMaxRequests))")

        return UsageMetrics(
            service: .cursor,
            sessionLimit: sessionLimit,
            weeklyLimit: weeklyLimit,
            codeReviewLimit: nil
        )
    }

    // MARK: - API Calls

    private func fetchUsage(userId: String, token: String) async throws -> CursorUsageResponse {
        guard let url = URL(string: usageEndpoint) else {
            throw ServiceError.apiError("Invalid usage URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Set authentication via Cookie header
        let authCookie = formatAuthCookie(userId: userId, token: token)
        request.setValue("WorkosCursorSessionToken=\(authCookie)", forHTTPHeaderField: "Cookie")

        request.timeoutInterval = 30.0

        print("[CursorLocalService] Calling usage endpoint: \(usageEndpoint)")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError("Invalid response type")
        }

        print("[CursorLocalService] Usage response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            await MainActor.run {
                self.hasAccess = false
                self.lastError = ServiceError.notAuthenticated
            }
            throw ServiceError.notAuthenticated
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[CursorLocalService] Usage error: \(errorMsg.prefix(200))")
            throw ServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg.prefix(100))")
        }

        // Parse the response manually since it has dynamic keys
        let rawResponse = String(data: data, encoding: .utf8) ?? "{}"
        print("[CursorLocalService] Raw response: \(rawResponse.prefix(300))")

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.parsingError
        }

        // Extract startOfMonth
        let startOfMonth = json["startOfMonth"] as? String ?? ""

        // Extract model usage data (dynamic keys like "gpt-4", "claude-3.5-sonnet", etc.)
        var models: [String: CursorModelUsage] = [:]

        for (key, value) in json {
            if key == "startOfMonth" { continue }

            if let modelData = value as? [String: Any] {
                let usage = CursorModelUsage(
                    numRequests: modelData["numRequests"] as? Int ?? 0,
                    numRequestsTotal: modelData["numRequestsTotal"] as? Int ?? 0,
                    numTokens: modelData["numTokens"] as? Int ?? 0,
                    maxTokenUsage: modelData["maxTokenUsage"] as? Int,
                    maxRequestUsage: modelData["maxRequestUsage"] as? Int
                )
                models[key] = usage
            }
        }

        print("[CursorLocalService] Parsed \(models.count) model(s)")

        return CursorUsageResponse(models: models, startOfMonth: startOfMonth)
    }
}

// MARK: - Response Models

/// Response from https://cursor.com/api/usage
/// Format: { "gpt-4": { numRequests: 0, ... }, "startOfMonth": "2025-12-30T..." }
struct CursorUsageResponse {
    let models: [String: CursorModelUsage]
    let startOfMonth: String
}

struct CursorModelUsage {
    let numRequests: Int
    let numRequestsTotal: Int
    let numTokens: Int
    let maxTokenUsage: Int?
    let maxRequestUsage: Int?
}
