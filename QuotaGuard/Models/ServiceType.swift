import Foundation

enum ServiceType: String, Codable, CaseIterable, Identifiable {
    case claude = "Claude"
    case claudeCode = "Claude Code"
    case openai = "OpenAI"
    case cursor = "Cursor"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude API"
        case .claudeCode: return "Claude Code"
        case .openai: return "OpenAI"
        case .cursor: return "Cursor"
        }
    }

    var iconName: String {
        switch self {
        case .claude: return "sparkles"
        case .claudeCode: return "terminal"
        case .openai: return "brain"
        case .cursor: return "cursorarrow.click"
        }
    }
}
