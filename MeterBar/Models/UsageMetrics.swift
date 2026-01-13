import Foundation

struct UsageMetrics: Codable, Identifiable {
    let id: UUID
    let service: ServiceType
    let sessionLimit: UsageLimit?
    let weeklyLimit: UsageLimit?
    let codeReviewLimit: UsageLimit?
    let lastUpdated: Date
    
    init(
        service: ServiceType,
        sessionLimit: UsageLimit? = nil,
        weeklyLimit: UsageLimit? = nil,
        codeReviewLimit: UsageLimit? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = UUID()
        self.service = service
        self.sessionLimit = sessionLimit
        self.weeklyLimit = weeklyLimit
        self.codeReviewLimit = codeReviewLimit
        self.lastUpdated = lastUpdated
    }
    
    var overallStatus: UsageStatus {
        let limits = [sessionLimit, weeklyLimit, codeReviewLimit].compactMap { $0 }
        guard !limits.isEmpty else { return .good }
        
        if limits.contains(where: { $0.isAtLimit }) {
            return .critical
        } else if limits.contains(where: { $0.isNearLimit }) {
            return .warning
        } else {
            return .good
        }
    }
    
    var hasData: Bool {
        return sessionLimit != nil || weeklyLimit != nil || codeReviewLimit != nil
    }
}

