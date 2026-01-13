import Foundation
import SwiftUI

struct UsageLimit: Codable, Equatable {
    let used: Double
    let total: Double
    let resetTime: Date?
    
    var percentage: Double {
        guard total > 0 else { return 0 }
        return min(100, max(0, (used / total) * 100))
    }
    
    var remaining: Double {
        return max(0, total - used)
    }
    
    var isNearLimit: Bool {
        return percentage >= 80
    }
    
    var isAtLimit: Bool {
        return percentage >= 100
    }
    
    var statusColor: UsageStatus {
        if isAtLimit {
            return .critical
        } else if isNearLimit {
            return .warning
        } else {
            return .good
        }
    }
}

enum UsageStatus {
    case good
    case warning
    case critical

    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}

