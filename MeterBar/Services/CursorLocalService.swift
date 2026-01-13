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

    // API endpoints (from Vibeviewer: https://github.com/MarveleE/Vibeviewer)
    private let usageSummaryEndpoint = "https://cursor.com/api/usage-summary"
    private let getMeEndpoint = "https://cursor.com/api/dashboard/get-me"

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

    /// Get the REAL home directory (not sandboxed container)
    private func getRealHomeDirectory() -> String {
        // In sandboxed apps, FileManager.homeDirectoryForCurrentUser returns the container path
        // We need the actual user home directory to access Cursor's database
        if let pw = getpwuid(getuid()) {
            return String(cString: pw.pointee.pw_dir)
        }
        // Fallback to environment variable
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return home
        }
        // Last resort - this will be sandboxed but better than nothing
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Get the path to Cursor's state database
    /// Scans multiple possible locations and optionally searches recursively
    private func getCursorDatabasePath(forceRescan: Bool = false) -> String? {
        let homeDir = getRealHomeDirectory()
        let fileManager = FileManager.default

        // Primary paths to check (most common locations)
        let pathsToCheck = [
            "\(homeDir)/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
            "\(homeDir)/Library/Application Support/Cursor/state.vscdb",
            "\(homeDir)/.config/Cursor/User/globalStorage/state.vscdb",
            // Additional common paths
            "\(homeDir)/Library/Application Support/Cursor/User/workspaceStorage/state.vscdb",
            "\(homeDir)/Library/Application Support/Cursor/globalStorage/state.vscdb",
        ]
        
        // Check each path
        for path in pathsToCheck {
            if fileManager.fileExists(atPath: path) {
                print("[CursorLocalService] Found database at: \(path)")
                return path
            }
        }
        
        // If not found and forceRescan is true, search recursively in Cursor directories
        if forceRescan {
            print("[CursorLocalService] Primary paths not found, scanning Cursor directories...")
            let cursorBasePaths = [
                "\(homeDir)/Library/Application Support/Cursor",
                "\(homeDir)/.config/Cursor"
            ]
            
            for basePath in cursorBasePaths {
                if let foundPath = findDatabaseRecursively(in: basePath, filename: "state.vscdb") {
                    print("[CursorLocalService] Found database via recursive search at: \(foundPath)")
                    return foundPath
                }
            }
        }
        
        // Log all checked paths for debugging
        print("[CursorLocalService] Database not found. Checked paths:")
        for path in pathsToCheck {
            let exists = fileManager.fileExists(atPath: path)
            print("[CursorLocalService]   \(exists ? "✓" : "✗") \(path)")
        }
        
        return nil
    }
    
    /// Recursively search for a database file in a directory
    private func findDatabaseRecursively(in directory: String, filename: String) -> String? {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: directory),
              let enumerator = fileManager.enumerator(atPath: directory) else {
            return nil
        }
        
        for case let path as String in enumerator {
            if path.hasSuffix(filename) {
                let fullPath = "\(directory)/\(path)"
                if fileManager.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }
        
        return nil
    }

    /// Read access token from Cursor's SQLite database
    /// - Parameter forceRescan: If true, will recursively search for database if not found in primary paths
    func getAccessTokenFromDatabase(forceRescan: Bool = false) -> (userId: String, token: String)? {
        guard let dbPath = getCursorDatabasePath(forceRescan: forceRescan) else {
            if forceRescan {
                print("[CursorLocalService] Database not found after rescanning all paths")
            }
            // Database not found - Cursor may not be installed, which is okay
            // Don't print error on init, only when actively trying to fetch
            return nil
        }

        // Verify file exists and is readable before attempting to open
        let isReadable = FileManager.default.isReadableFile(atPath: dbPath)
        if !isReadable {
            print("[CursorLocalService] Database file not readable (sandbox blocking access)")
            return nil
        }

        var db: OpaquePointer?
        let result = sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            print("[CursorLocalService] SQLite open failed: \(result) - \(String(cString: sqlite3_errmsg(db)))")
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
    /// - Parameter forceRescan: If true, will recursively search for database if not found in primary paths
    func checkAccess(forceRescan: Bool = false) {
        if let _ = getAccessTokenFromDatabase(forceRescan: forceRescan) {
            hasAccess = true
        } else {
            hasAccess = false
            subscriptionType = nil
        }
    }

    // MARK: - Usage Fetching

    func fetchUsageMetrics() async throws -> UsageMetrics {
        // Try without rescan first (faster), then with rescan if needed
        guard let (userId, token) = getAccessTokenFromDatabase(forceRescan: false) ?? getAccessTokenFromDatabase(forceRescan: true) else {
            let error = ServiceError.notAuthenticated
            await MainActor.run {
                self.lastError = error
                self.hasAccess = false
            }
            print("[CursorLocalService] No access token found in database after full scan")
            throw error
        }

        await MainActor.run {
            self.hasAccess = true
        }

        print("[CursorLocalService] Fetching usage data from Cursor API...")

        // Fetch usage summary data (uses /api/usage-summary endpoint)
        let summaryData = try await fetchUsageSummary(userId: userId, token: token)

        // Clear any previous errors on success
        await MainActor.run {
            self.lastError = nil
            self.subscriptionType = summaryData.membershipType
        }

        // Parse billing cycle end date for reset time
        var resetTime: Date? = nil
        if let billingEnd = summaryData.billingCycleEnd {
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resetTime = dateFormatter.date(from: billingEnd)

            // Try without fractional seconds if that fails
            if resetTime == nil {
                dateFormatter.formatOptions = [.withInternetDateTime]
                resetTime = dateFormatter.date(from: billingEnd)
            }
        }

        // Extract usage from individual plan
        let planUsed = Double(summaryData.individualUsage?.plan?.used ?? 0)
        let planTotal = Double(summaryData.individualUsage?.plan?.total ?? 500)

        print("[CursorLocalService] Plan type: \(summaryData.membershipType ?? "unknown")")
        print("[CursorLocalService] Plan usage: \(Int(planUsed)) / \(Int(planTotal))")
        print("[CursorLocalService] Billing cycle end: \(summaryData.billingCycleEnd ?? "unknown")")

        // Create usage metrics using plan data
        let weeklyLimit = UsageLimit(
            used: planUsed,
            total: planTotal,
            resetTime: resetTime
        )

        // On-demand usage as secondary metric if enabled
        var sessionLimit: UsageLimit? = nil
        if let onDemand = summaryData.individualUsage?.onDemand, onDemand.enabled == true {
            let onDemandUsed = Double(onDemand.used ?? 0)
            let onDemandLimit = Double(onDemand.limit ?? 0)
            if onDemandUsed > 0 || onDemandLimit > 0 {
                sessionLimit = UsageLimit(
                    used: onDemandUsed,
                    total: onDemandLimit > 0 ? onDemandLimit : onDemandUsed * 1.5,
                    resetTime: resetTime
                )
            }
        }

        print("[CursorLocalService] Successfully fetched Cursor usage data")

        return UsageMetrics(
            service: .cursor,
            sessionLimit: sessionLimit,
            weeklyLimit: weeklyLimit,
            codeReviewLimit: nil
        )
    }

    // MARK: - API Calls

    /// Build browser-like headers for Cursor API requests
    private func buildHeaders(userId: String, token: String) -> [String: String] {
        let authCookie = formatAuthCookie(userId: userId, token: token)
        return [
            "Accept": "*/*",
            "Content-Type": "application/json",
            "Cookie": "WorkosCursorSessionToken=\(authCookie)",
            "Origin": "https://cursor.com",
            "Referer": "https://cursor.com/dashboard?tab=usage",
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        ]
    }

    private func fetchUsageSummary(userId: String, token: String) async throws -> CursorUsageSummaryResponse {
        guard let url = URL(string: usageSummaryEndpoint) else {
            throw ServiceError.apiError("Invalid usage summary URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0

        // Set browser-like headers
        for (key, value) in buildHeaders(userId: userId, token: token) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        print("[CursorLocalService] Calling usage-summary endpoint")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.apiError("Invalid response type")
        }

        print("[CursorLocalService] Usage summary response status: \(httpResponse.statusCode)")

        if httpResponse.statusCode == 401 {
            await MainActor.run {
                self.hasAccess = false
                self.lastError = ServiceError.notAuthenticated
            }
            throw ServiceError.notAuthenticated
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[CursorLocalService] Usage summary error: \(errorMsg.prefix(200))")
            throw ServiceError.apiError("HTTP \(httpResponse.statusCode): \(errorMsg.prefix(100))")
        }

        // Debug: print raw response
        if let rawResponse = String(data: data, encoding: .utf8) {
            print("[CursorLocalService] Raw usage-summary response: \(rawResponse.prefix(500))")
        }

        // Parse the response
        let decoder = JSONDecoder()
        do {
            let summaryResponse = try decoder.decode(CursorUsageSummaryResponse.self, from: data)
            print("[CursorLocalService] Parsed usage summary: used=\(summaryResponse.individualUsage?.plan?.used ?? 0), total=\(summaryResponse.individualUsage?.plan?.total ?? 0)")
            return summaryResponse
        } catch {
            print("[CursorLocalService] JSON decode error: \(error)")
            throw ServiceError.parsingError
        }
    }
}

// MARK: - Response Models

/// Response from https://cursor.com/api/usage-summary
/// Based on Vibeviewer implementation
struct CursorUsageSummaryResponse: Decodable {
    let billingCycleStart: String?
    let billingCycleEnd: String?
    let membershipType: String?
    let limitType: String?
    let individualUsage: CursorIndividualUsage?
    let teamUsage: CursorTeamUsage?
}

struct CursorIndividualUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
}

struct CursorPlanUsage: Decodable {
    let used: Int?
    let limit: Int?
    let remaining: Int?
    let included: Int?
    let bonus: Int?
    let total: Int?
}

struct CursorOnDemandUsage: Decodable {
    let used: Int?
    let limit: Int?
    let remaining: Int?
    let enabled: Bool?
}

struct CursorTeamUsage: Decodable {
    let plan: CursorPlanUsage?
    let onDemand: CursorOnDemandUsage?
}
