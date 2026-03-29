import Foundation

enum ProviderHealthState: Int, Comparable {
    case disconnected = 0
    case healthy = 1
    case stale = 2
    case warning = 3
    case critical = 4
    case error = 5

    static func < (lhs: ProviderHealthState, rhs: ProviderHealthState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var isIssue: Bool {
        switch self {
        case .stale, .warning, .critical, .error:
            return true
        case .disconnected, .healthy:
            return false
        }
    }

    var label: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .healthy:
            return "Healthy"
        case .stale:
            return "Stale"
        case .warning:
            return "Low"
        case .critical:
            return "Limit Hit"
        case .error:
            return "Issue"
        }
    }
}

struct ProviderHealthSummary: Identifiable {
    let service: ServiceType
    let title: String
    let state: ProviderHealthState
    let message: String
    let remainingText: String?
    let metrics: UsageMetrics?
    let isConnected: Bool

    var id: ServiceType { service }

    var shouldShowBanner: Bool {
        state.isIssue
    }

    init(
        service: ServiceType,
        title: String,
        metrics: UsageMetrics?,
        isConnected: Bool,
        lastError: Error?,
        staleAfter: TimeInterval = 3600
    ) {
        self.service = service
        self.title = title
        self.metrics = metrics
        self.isConnected = isConnected

        let remainingText = Self.remainingText(from: metrics)
        self.remainingText = remainingText

        if let lastError {
            self.state = .error
            self.message = lastError.localizedDescription
            return
        }

        guard let metrics else {
            if isConnected {
                self.state = .healthy
                self.message = "Connected. Refresh to load the current quota windows."
            } else {
                self.state = .disconnected
                self.message = "Local sign-in was not detected yet."
            }
            return
        }

        if Date().timeIntervalSince(metrics.lastUpdated) > staleAfter {
            self.state = .stale
            self.message = "Last updated \(Self.relativeTimestamp(metrics.lastUpdated)). Refresh to confirm current limits."
            return
        }

        switch metrics.overallStatus {
        case .critical:
            self.state = .critical
            self.message = remainingText.map { "A quota window is exhausted or nearly exhausted (\($0))." }
                ?? "A quota window is exhausted or nearly exhausted."
        case .warning:
            self.state = .warning
            self.message = remainingText.map { "A quota window is running low (\($0))." }
                ?? "A quota window is running low."
        case .good:
            self.state = .healthy
            self.message = remainingText.map { "Primary window has \($0)." }
                ?? "Usage is healthy."
        }
    }

    private static func remainingText(from metrics: UsageMetrics?) -> String? {
        guard let limit = mostConstrainedLimit(from: metrics) else {
            return nil
        }
        let remaining = Int(round(max(0, 100 - limit.percentage)))
        return "\(remaining)% left"
    }

    private static func mostConstrainedLimit(from metrics: UsageMetrics?) -> UsageLimit? {
        guard let metrics else {
            return nil
        }

        return [metrics.sessionLimit, metrics.weeklyLimit, metrics.codeReviewLimit]
            .compactMap { $0 }
            .max(by: { $0.percentage < $1.percentage })
    }

    private static func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
