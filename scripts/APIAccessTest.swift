#!/usr/bin/env swift
//
// APIAccessTest.swift
// QuotaGuard
//
// Standalone script to test API access for Claude, OpenAI, Cursor, and Claude Code.
// Run with: swift scripts/APIAccessTest.swift
//

import Foundation
import Security
import SQLite3

// MARK: - Keychain Helpers

func getKeychainItem(service: String, account: String? = nil) -> String? {
    var query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    if let account = account {
        query[kSecAttrAccount as String] = account
    }

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        return nil
    }

    return value
}

func getKeychainItemForAppService(_ service: String) -> String? {
    // Try with app-specific keychain (QuotaGuard's keychain service)
    let appService = "com.agenticindiedev.quotaguard"
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: appService,
        kSecAttrAccount as String: service,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        return nil
    }

    return value
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
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case model
    }
}

struct OpenAIUsageResponse: Codable {
    let object: String?
    let data: [OpenAIUsageBucket]

    enum CodingKeys: String, CodingKey {
        case object
        case data
    }
}

struct OpenAIUsageBucket: Codable {
    let results: [OpenAIUsageResult]
}

struct OpenAIUsageResult: Codable {
    let inputTokens: Int?
    let outputTokens: Int?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case model
    }
}

struct ClaudeCodeCredentials: Codable {
    let claudeAiOauth: ClaudeAiOAuth

    enum CodingKeys: String, CodingKey {
        case claudeAiOauth = "claudeAiOauth"
    }
}

struct ClaudeAiOAuth: Codable {
    let accessToken: String
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

// MARK: - Test Functions

func printHeader(_ title: String, emoji: String) {
    print("\n" + String(repeating: "=", count: 60))
    print("\(emoji) \(title)")
    print(String(repeating: "=", count: 60))
}

func formatTokens(_ count: Double) -> String {
    if count >= 1_000_000 {
        return String(format: "%.2fM", count / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.1fK", count / 1_000)
    } else {
        return String(format: "%.0f", count)
    }
}

func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

// MARK: - Claude API Test

func testClaudeAPI() async -> (success: Bool, message: String) {
    printHeader("CLAUDE (Anthropic) API TEST", emoji: "🔵")

    // Try to get the admin key from keychain
    guard let adminKey = getKeychainItemForAppService("claude_admin_key") else {
        print("⚠️  SKIPPED: No Claude Admin API key found in keychain")
        print("   To configure: Open QuotaGuard app and add your Admin API key in Settings")
        return (false, "Not configured")
    }

    print("✓ Claude Admin API key found")

    // Build the request
    let endDate = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

    let dateFormatter = ISO8601DateFormatter()
    dateFormatter.formatOptions = [.withInternetDateTime]

    var components = URLComponents(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!
    components.queryItems = [
        URLQueryItem(name: "starting_at", value: dateFormatter.string(from: startDate)),
        URLQueryItem(name: "ending_at", value: dateFormatter.string(from: endDate)),
        URLQueryItem(name: "bucket_width", value: "1d"),
        URLQueryItem(name: "group_by[]", value: "model")
    ]

    guard let url = components.url else {
        print("❌ Invalid URL")
        return (false, "Invalid URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(adminKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30.0

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response")
            return (false, "Invalid response")
        }

        if httpResponse.statusCode == 401 {
            print("❌ Authentication failed (401)")
            print("   Your Admin API key may be invalid or expired")
            return (false, "Authentication failed")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            print("❌ API Error (\(httpResponse.statusCode)): \(errorMsg.prefix(100))")
            return (false, "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(AnthropicUsageResponse.self, from: data)

        var totalTokens: Double = 0
        for bucket in responseData.data {
            totalTokens += Double(bucket.inputTokens ?? 0) + Double(bucket.outputTokens ?? 0)
        }

        print("✅ SUCCESS: Claude API access verified!")
        print("\nUsage Data (Last 7 Days):")
        print("  Total Tokens: \(formatTokens(totalTokens))")
        print("  Data Buckets: \(responseData.data.count)")

        return (true, "\(formatTokens(totalTokens)) tokens used")

    } catch {
        print("❌ Request failed: \(error.localizedDescription)")
        return (false, error.localizedDescription)
    }
}

// MARK: - OpenAI API Test

func testOpenAIAPI() async -> (success: Bool, message: String) {
    printHeader("OPENAI (Codex) API TEST", emoji: "🟢")

    // Try to get the admin key from keychain
    guard let adminKey = getKeychainItemForAppService("openai_admin_key") else {
        print("⚠️  SKIPPED: No OpenAI Admin API key found in keychain")
        print("   To configure: Open QuotaGuard app and add your Admin API key in Settings")
        return (false, "Not configured")
    }

    print("✓ OpenAI Admin API key found")

    // Build the request
    let endDate = Date()
    let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate)!

    let startTime = Int(startDate.timeIntervalSince1970)
    let endTime = Int(endDate.timeIntervalSince1970)

    var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
    components.queryItems = [
        URLQueryItem(name: "start_time", value: String(startTime)),
        URLQueryItem(name: "end_time", value: String(endTime)),
        URLQueryItem(name: "bucket_width", value: "1d"),
        URLQueryItem(name: "group_by", value: "model")
    ]

    guard let url = components.url else {
        print("❌ Invalid URL")
        return (false, "Invalid URL")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(adminKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30.0

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response")
            return (false, "Invalid response")
        }

        if httpResponse.statusCode == 401 {
            print("❌ Authentication failed (401)")
            print("   Your Admin API key may be invalid or expired")
            return (false, "Authentication failed")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            print("❌ API Error (\(httpResponse.statusCode)): \(errorMsg.prefix(100))")
            return (false, "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        let responseData = try decoder.decode(OpenAIUsageResponse.self, from: data)

        var totalTokens: Double = 0
        for bucket in responseData.data {
            for result in bucket.results {
                totalTokens += Double(result.inputTokens ?? 0) + Double(result.outputTokens ?? 0)
            }
        }

        print("✅ SUCCESS: OpenAI API access verified!")
        print("\nUsage Data (Last 7 Days):")
        print("  Total Tokens: \(formatTokens(totalTokens))")
        print("  Data Buckets: \(responseData.data.count)")

        return (true, "\(formatTokens(totalTokens)) tokens used")

    } catch {
        print("❌ Request failed: \(error.localizedDescription)")
        return (false, error.localizedDescription)
    }
}

// MARK: - Claude Code API Test

func testClaudeCodeAPI() async -> (success: Bool, message: String) {
    printHeader("CLAUDE CODE (OAuth) API TEST", emoji: "🟣")

    // Try to get the OAuth token from Claude Code's keychain
    guard let credentialsJson = getKeychainItem(service: "Claude Code-credentials") else {
        print("⚠️  SKIPPED: No Claude Code OAuth token found")
        print("   To configure: Run 'claude login' in your terminal")
        return (false, "Not configured")
    }

    guard let credData = credentialsJson.data(using: .utf8),
          let credentials = try? JSONDecoder().decode(ClaudeCodeCredentials.self, from: credData) else {
        print("❌ Failed to parse Claude Code credentials")
        return (false, "Invalid credentials format")
    }

    let token = credentials.claudeAiOauth.accessToken
    print("✓ Claude Code OAuth token found")

    if let subType = credentials.claudeAiOauth.subscriptionType {
        print("  Subscription: \(subType)")
    }
    if let tier = credentials.claudeAiOauth.rateLimitTier {
        print("  Rate Limit Tier: \(tier)")
    }

    // Try multiple endpoint patterns
    let endpoints = [
        "https://api.anthropic.com/v1/oauth/usage",
        "https://api.anthropic.com/api/v1/oauth/usage",
        "https://api.anthropic.com/api/oauth/usage",
        "https://api.anthropic.com/oauth/v1/usage"
    ]

    for endpoint in endpoints {
        guard let url = URL(string: endpoint) else { continue }

        print("\nTrying endpoint: \(endpoint)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { continue }

            print("  Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                print("❌ Authentication failed (401)")
                return (false, "Token expired or invalid")
            }

            if (200...299).contains(httpResponse.statusCode) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                if let usageResponse = try? decoder.decode(ClaudeCodeUsageResponse.self, from: data) {
                    print("✅ SUCCESS: Claude Code API access verified!")
                    print("\nUsage Data:")
                    print("  5-Hour Session: \(String(format: "%.1f", usageResponse.fiveHour.utilization))%")
                    print("    Resets: \(formatDate(usageResponse.fiveHour.resetsAt))")
                    print("  7-Day Weekly: \(String(format: "%.1f", usageResponse.sevenDay.utilization))%")
                    print("    Resets: \(formatDate(usageResponse.sevenDay.resetsAt))")

                    if let sonnet = usageResponse.sevenDaySonnet {
                        print("  7-Day Sonnet: \(String(format: "%.1f", sonnet.utilization))%")
                    }

                    return (true, "\(String(format: "%.1f", usageResponse.sevenDay.utilization))% weekly usage")
                }

                // If we got 200 but couldn't parse, show the response
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode"
                print("  Response (200 but unexpected format): \(rawResponse.prefix(200))")
            }
        } catch {
            print("  Error: \(error.localizedDescription)")
        }
    }

    print("❌ All endpoint attempts failed")
    print("   Note: The OAuth usage endpoint may not be publicly available yet")
    return (false, "API endpoint not accessible")
}

// MARK: - Cursor API Test (cursor-stats approach)

/// Get the path to Cursor's state database
func getCursorDatabasePath() -> String? {
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

/// Extract userId from JWT token's 'sub' claim
func extractUserIdFromJWT(_ token: String) -> String? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }

    var payload = String(parts[1])
    let remainder = payload.count % 4
    if remainder > 0 {
        payload += String(repeating: "=", count: 4 - remainder)
    }

    payload = payload
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    guard let data = Data(base64Encoded: payload),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let sub = json["sub"] as? String else {
        return nil
    }

    if sub.contains("|") {
        return sub.components(separatedBy: "|").last
    }
    return sub
}

/// Read access token from Cursor's SQLite database
func getCursorTokenFromDatabase() -> (userId: String, token: String)? {
    guard let dbPath = getCursorDatabasePath() else {
        print("  Database not found at expected paths")
        return nil
    }

    print("  Database found: \(dbPath)")

    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        print("  Failed to open database: \(String(cString: sqlite3_errmsg(db)))")
        sqlite3_close(db)
        return nil
    }
    defer { sqlite3_close(db) }

    let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
    var statement: OpaquePointer?

    guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
        print("  Failed to prepare query: \(String(cString: sqlite3_errmsg(db)))")
        return nil
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        print("  No token found in database (user may not be logged in)")
        return nil
    }

    guard let tokenCString = sqlite3_column_text(statement, 0) else {
        print("  Failed to read token value")
        return nil
    }

    let token = String(cString: tokenCString)

    guard let userId = extractUserIdFromJWT(token) else {
        print("  Failed to extract userId from JWT")
        return nil
    }

    return (userId: userId, token: token)
}

func testCursorAPI() async -> (success: Bool, message: String) {
    printHeader("CURSOR API TEST", emoji: "🟡")

    // Get token from Cursor's SQLite database
    guard let (userId, token) = getCursorTokenFromDatabase() else {
        print("⚠️  SKIPPED: No Cursor token found in database")
        print("   To configure: Open Cursor and log in to your account")
        return (false, "Not configured")
    }

    print("✓ Cursor token found in database")
    print("  User ID: \(userId.prefix(8))...")

    // Format authentication cookie
    let authCookie = "\(userId)%3A%3A\(token)"

    // Call Cursor usage API
    let usageEndpoint = "https://cursor.com/api/usage"

    guard let url = URL(string: usageEndpoint) else {
        return (false, "Invalid URL")
    }

    print("\nCalling: \(usageEndpoint)")

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("WorkosCursorSessionToken=\(authCookie)", forHTTPHeaderField: "Cookie")
    request.timeoutInterval = 30.0

    do {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            return (false, "Invalid response")
        }

        print("  Status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            print("❌ Authentication failed (401)")
            print("   Token may be expired - try logging out and back into Cursor")
            return (false, "Authentication failed")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            print("❌ API Error: \(errorMsg.prefix(100))")
            return (false, "HTTP \(httpResponse.statusCode)")
        }

        print("✅ SUCCESS: Cursor API access verified!")

        // Parse the response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("  (Could not parse response)")
            return (true, "API accessible")
        }

        // Extract startOfMonth
        if let startOfMonth = json["startOfMonth"] as? String {
            print("\nBilling Period Start: \(startOfMonth)")
        }

        // Extract model usage
        var totalRequests = 0
        var totalTokens = 0

        print("\nUsage by Model:")
        for (key, value) in json {
            if key == "startOfMonth" { continue }

            if let modelData = value as? [String: Any] {
                let numRequests = modelData["numRequests"] as? Int ?? 0
                let numTokens = modelData["numTokens"] as? Int ?? 0
                let maxRequests = modelData["maxRequestUsage"] as? Int

                totalRequests += numRequests
                totalTokens += numTokens

                if numRequests > 0 || numTokens > 0 {
                    print("  \(key):")
                    print("    Requests: \(numRequests)" + (maxRequests != nil ? " / \(maxRequests!)" : ""))
                    print("    Tokens: \(formatTokens(Double(numTokens)))")
                }
            }
        }

        print("\nTotal Usage:")
        print("  Requests: \(totalRequests)")
        print("  Tokens: \(formatTokens(Double(totalTokens)))")

        return (true, "\(totalRequests) requests used")

    } catch {
        print("❌ Request failed: \(error.localizedDescription)")
        return (false, error.localizedDescription)
    }
}

// MARK: - Main

func printSummary(_ results: [(String, Bool, String)]) {
    print("\n" + String(repeating: "=", count: 60))
    print("📊 SUMMARY")
    print(String(repeating: "=", count: 60))
    print("")
    print("  Service       | Status         | Details")
    print("  " + String(repeating: "-", count: 55))

    for (service, success, message) in results {
        let paddedService = service.padding(toLength: 12, withPad: " ", startingAt: 0)
        let status = success ? "✅ Connected" : (message == "Not configured" ? "⚪ Skip" : "❌ Failed")
        let paddedStatus = status.padding(toLength: 14, withPad: " ", startingAt: 0)
        print("  \(paddedService) | \(paddedStatus) | \(message)")
    }
    print("")
}

// Run all tests
print("")
print("╔══════════════════════════════════════════════════════════╗")
print("║          QuotaGuard API Access Test Suite                ║")
print("╚══════════════════════════════════════════════════════════╝")

var results: [(String, Bool, String)] = []

// Run tests sequentially
Task {
    let claudeResult = await testClaudeAPI()
    results.append(("Claude", claudeResult.success, claudeResult.message))

    let openaiResult = await testOpenAIAPI()
    results.append(("OpenAI", openaiResult.success, openaiResult.message))

    let claudeCodeResult = await testClaudeCodeAPI()
    results.append(("Claude Code", claudeCodeResult.success, claudeCodeResult.message))

    let cursorResult = await testCursorAPI()
    results.append(("Cursor", cursorResult.success, cursorResult.message))

    printSummary(results)

    print("╔══════════════════════════════════════════════════════════╗")
    print("║                    Tests Complete                        ║")
    print("╚══════════════════════════════════════════════════════════╝")
    print("")

    exit(0)
}

// Keep the script running until async tasks complete
RunLoop.main.run()
