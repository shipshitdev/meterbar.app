import Foundation
import Combine

@MainActor
class UsageDataManager: ObservableObject {
    static let shared = UsageDataManager()

    @Published var metrics: [ServiceType: UsageMetrics] = [:]
    @Published var isLoading: Bool = false
    @Published var lastError: Error?

    private let claudeService = ClaudeService.shared
    private let claudeCodeService = ClaudeCodeLocalService.shared
    private let cursorService = CursorLocalService.shared
    private let openaiService = OpenAIService.shared
    private let authManager = AuthenticationManager.shared

    private var refreshTimer: Timer?
    private let cacheKey = "cached_usage_metrics"
    private let sharedStore = SharedDataStore.shared

    private init() {
        loadCachedData()
        setupAutoRefresh()
    }

    func refreshAll() async {
        isLoading = true
        lastError = nil

        var newMetrics: [ServiceType: UsageMetrics] = [:]

        // Fetch Claude metrics
        if authManager.isClaudeAuthenticated {
            do {
                let metrics = try await claudeService.fetchUsageMetrics()
                newMetrics[.claude] = metrics
            } catch {
                lastError = error
                print("Failed to fetch Claude metrics: \(error)")
            }
        }

        // Fetch Claude Code metrics (local files)
        if claudeCodeService.hasAccess {
            do {
                let metrics = try await claudeCodeService.fetchUsageMetrics()
                newMetrics[.claudeCode] = metrics
                print("[UsageDataManager] Successfully fetched Claude Code metrics")
            } catch {
                lastError = error
                print("[UsageDataManager] Failed to fetch Claude Code metrics: \(error)")
                if let serviceError = error as? ServiceError {
                    print("[UsageDataManager] Claude Code error details: \(serviceError.localizedDescription)")
                }
                // Preserve cached data if available (graceful degradation)
                if let cachedMetrics = self.metrics[.claudeCode] {
                    newMetrics[.claudeCode] = cachedMetrics
                    print("[UsageDataManager] Using cached Claude Code metrics due to fetch failure")
                }
            }
        }

        // Fetch OpenAI metrics
        if authManager.isOpenAIAuthenticated {
            do {
                let metrics = try await openaiService.fetchUsageMetrics()
                newMetrics[.openai] = metrics
            } catch {
                lastError = error
                print("Failed to fetch OpenAI metrics: \(error)")
            }
        }

        // Note: Cursor doesn't have an API, so we don't fetch metrics for it
        
        // Merge new metrics with existing cached metrics for services that failed to fetch (graceful degradation)
        for service in ServiceType.allCases {
            if newMetrics[service] == nil, let cachedMetric = self.metrics[service] {
                newMetrics[service] = cachedMetric
                print("[UsageDataManager] Preserving cached \(service.displayName) metrics after refreshAll")
            }
        }

        metrics = newMetrics
        saveCachedData()
        sharedStore.saveMetrics(newMetrics)
        isLoading = false
    }

    func refresh(service: ServiceType) async {
        isLoading = true
        lastError = nil

        do {
            let newMetrics: UsageMetrics

            switch service {
            case .claude:
                guard authManager.isClaudeAuthenticated else {
                    throw ServiceError.notAuthenticated
                }
                newMetrics = try await claudeService.fetchUsageMetrics()
            case .claudeCode:
                guard claudeCodeService.hasAccess else {
                    throw ServiceError.notAuthenticated
                }
                do {
                    newMetrics = try await claudeCodeService.fetchUsageMetrics()
                    print("[UsageDataManager] Successfully refreshed Claude Code metrics")
                } catch {
                    // On individual refresh, preserve cached data if fetch fails (graceful degradation)
                    if let cachedMetric = metrics[service] {
                        print("[UsageDataManager] Claude Code refresh failed, preserving cached data: \(error)")
                        newMetrics = cachedMetric
                        // Don't throw - preserve cache but still set lastError below
                        lastError = error
                    } else {
                        throw error
                    }
                }
            case .openai:
                guard authManager.isOpenAIAuthenticated else {
                    throw ServiceError.notAuthenticated
                }
                newMetrics = try await openaiService.fetchUsageMetrics()
            case .cursor:
                guard cursorService.hasAccess else {
                    throw ServiceError.notAuthenticated
                }
                do {
                    newMetrics = try await cursorService.fetchUsageMetrics()
                    print("[UsageDataManager] Successfully refreshed Cursor metrics")
                } catch {
                    // On individual refresh, preserve cached data if fetch fails (graceful degradation)
                    if let cachedMetric = metrics[service] {
                        print("[UsageDataManager] Cursor refresh failed, preserving cached data: \(error)")
                        newMetrics = cachedMetric
                        // Don't throw - preserve cache but still set lastError below
                        lastError = error
                    } else {
                        throw error
                    }
                }
            }

            metrics[service] = newMetrics
            saveCachedData()
            sharedStore.saveMetrics(metrics)
        } catch {
            // Only set lastError if it wasn't already set (e.g., from graceful degradation)
            if lastError == nil {
                lastError = error
            }
            print("[UsageDataManager] Failed to fetch \(service.displayName) metrics: \(error)")
            if let serviceError = error as? ServiceError {
                print("[UsageDataManager] \(service.displayName) error details: \(serviceError.localizedDescription)")
            }
            // Preserve existing cached metrics for this service on error (graceful degradation)
            // Metrics may already be set from the instance property, so check if we need to load from cache
            if metrics[service] == nil {
                // Try to load from UserDefaults cache
                if let cachedData = loadCachedMetricsFromDisk()[service] {
                    metrics[service] = cachedData
                    print("[UsageDataManager] Using cached \(service.displayName) metrics from disk due to fetch failure")
                }
            }
        }

        isLoading = false
    }

    private func loadCachedData() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: UsageMetrics].self, from: data) else {
            return
        }

        metrics = decoded.reduce(into: [ServiceType: UsageMetrics]()) { result, pair in
            if let service = ServiceType(rawValue: pair.key) {
                result[service] = pair.value
            }
        }
    }
    
    /// Load cached metrics from disk without modifying instance state
    private func loadCachedMetricsFromDisk() -> [ServiceType: UsageMetrics] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: UsageMetrics].self, from: data) else {
            return [:]
        }

        return decoded.reduce(into: [ServiceType: UsageMetrics]()) { result, pair in
            if let service = ServiceType(rawValue: pair.key) {
                result[service] = pair.value
            }
        }
    }

    private func saveCachedData() {
        let encoded = metrics.reduce(into: [String: UsageMetrics]()) { result, pair in
            result[pair.key.rawValue] = pair.value
        }

        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func setupAutoRefresh() {
        // Refresh every 15 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
    }

    func getNextRefreshTime() -> Date? {
        // Find the earliest reset time across all metrics
        let resetTimes = metrics.values.compactMap { metrics -> Date? in
            let times = [
                metrics.sessionLimit?.resetTime,
                metrics.weeklyLimit?.resetTime,
                metrics.codeReviewLimit?.resetTime
            ].compactMap { $0 }
            return times.min()
        }

        return resetTimes.min()
    }
}
