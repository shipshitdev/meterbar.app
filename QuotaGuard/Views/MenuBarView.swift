import SwiftUI
import AppKit

struct MenuBarView: View {
    @StateObject private var dataManager = UsageDataManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var claudeCodeService = ClaudeCodeLocalService.shared
    @StateObject private var cursorService = CursorLocalService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Quota Guard")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task {
                        await dataManager.refreshAll()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Service Cards - Always show all three services
            ScrollView {
                VStack(spacing: 12) {
                    // Claude API
                    ServiceRowView(
                        service: .claude,
                        isAuthenticated: authManager.isClaudeAuthenticated,
                        metrics: dataManager.metrics[.claude]
                    )

                    // Claude Code (Local)
                    ClaudeCodeServiceRow(
                        hasAccess: claudeCodeService.hasAccess,
                        metrics: dataManager.metrics[.claudeCode]
                    )

                    // OpenAI
                    ServiceRowView(
                        service: .openai,
                        isAuthenticated: authManager.isOpenAIAuthenticated,
                        metrics: dataManager.metrics[.openai]
                    )

                    // Cursor (Local)
                    CursorServiceRow(
                        hasAccess: cursorService.hasAccess,
                        metrics: dataManager.metrics[.cursor]
                    )
                }
                .padding()
            }

            Divider()

            // Footer Actions
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 500)
    }
}

// MARK: - Service Row View

struct ServiceRowView: View {
    let service: ServiceType
    let isAuthenticated: Bool
    let metrics: UsageMetrics?

    @StateObject private var authManager = AuthenticationManager.shared
    @State private var isExpanded: Bool = false
    @State private var apiKeyInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: service.iconName)
                    .foregroundColor(headerColor)
                Text(service.displayName)
                    .font(.headline)
                Spacer()

                if isAuthenticated {
                    if let metrics = metrics {
                        StatusIndicator(status: metrics.overallStatus)
                    }

                    // Show gear button to manage key when authenticated
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            Text(isExpanded ? "Close" : "Configure")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isAuthenticated, let metrics = metrics {
                Divider()

                // Show usage data
                if let sessionLimit = metrics.sessionLimit {
                    LimitRow(title: "Session", limit: sessionLimit)
                }

                if let weeklyLimit = metrics.weeklyLimit {
                    LimitRow(title: "Weekly", limit: weeklyLimit)
                }

                if let codeReviewLimit = metrics.codeReviewLimit {
                    LimitRow(title: "Code Review", limit: codeReviewLimit)
                }

                Text("Updated: \(formatDate(metrics.lastUpdated))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !isAuthenticated && !isExpanded {
                Text("Not configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Inline settings section
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    if isAuthenticated {
                        // Show masked key and remove button
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API Key configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button(action: {
                            removeApiKey()
                            isExpanded = false
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Remove Key")
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    } else {
                        // Show input field for new key
                        Text(keyPlaceholder)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        SecureField("Paste API key here...", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        HStack {
                            Button(action: {
                                saveApiKey()
                            }) {
                                HStack {
                                    Image(systemName: "checkmark")
                                    Text("Save")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(apiKeyInput.isEmpty)

                            Button(action: {
                                openHelpUrl()
                            }) {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                    Text("Help")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var headerColor: Color {
        if isAuthenticated, let metrics = metrics {
            return colorForStatus(metrics.overallStatus)
        }
        return .gray
    }

    private var keyPlaceholder: String {
        switch service {
        case .claude:
            return "Admin API Key (sk-ant-admin...)"
        case .claudeCode:
            return ""
        case .openai:
            return "Admin API Key"
        case .cursor:
            return ""
        }
    }

    private func saveApiKey() {
        switch service {
        case .claude:
            _ = authManager.setClaudeAdminKey(apiKeyInput)
        case .claudeCode:
            break // Claude Code uses directory picker, not API key
        case .openai:
            _ = authManager.setOpenAIAdminKey(apiKeyInput)
        case .cursor:
            break
        }
        apiKeyInput = ""
        isExpanded = false
    }

    private func removeApiKey() {
        switch service {
        case .claude:
            authManager.removeClaudeAdminKey()
        case .claudeCode:
            break // Claude Code uses directory picker
        case .openai:
            authManager.removeOpenAIAdminKey()
        case .cursor:
            break
        }
    }

    private func openHelpUrl() {
        let urlString: String
        switch service {
        case .claude:
            urlString = "https://console.anthropic.com/settings/admin-keys"
        case .claudeCode:
            return // No help URL for local file access
        case .openai:
            urlString = "https://platform.openai.com/settings/organization/admin-keys"
        case .cursor:
            return
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func colorForStatus(_ status: UsageStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Cursor Service Row (Local)

struct CursorServiceRow: View {
    let hasAccess: Bool
    let metrics: UsageMetrics?

    @StateObject private var cursorService = CursorLocalService.shared
    @StateObject private var dataManager = UsageDataManager.shared
    @State private var isExpanded: Bool = false

    private var headerColor: Color {
        hasAccess ? .blue : .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: ServiceType.cursor.iconName)
                    .foregroundColor(headerColor)
                Text(ServiceType.cursor.displayName)
                    .font(.headline)
                Spacer()

                if hasAccess {
                    if let metrics = metrics {
                        StatusIndicator(status: metrics.overallStatus)
                    }

                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            Text(isExpanded ? "Close" : "Configure")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if hasAccess, let metrics = metrics {
                Divider()

                if let sessionLimit = metrics.sessionLimit {
                    LimitRow(title: "Session", limit: sessionLimit)
                }

                if let weeklyLimit = metrics.weeklyLimit {
                    LimitRow(title: "Monthly", limit: weeklyLimit)
                }

                if let additionalLimit = metrics.codeReviewLimit {
                    LimitRow(title: "Additional", limit: additionalLimit)
                }

                if let subscriptionType = cursorService.subscriptionType {
                    HStack {
                        Text(subscriptionType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                        Spacer()
                        Text("Updated: \(formatDate(metrics.lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Updated: \(formatDate(metrics.lastUpdated))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isExpanded {
                    Divider()
                    Button("Refresh Now") {
                        Task {
                            await dataManager.refresh(service: .cursor)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Text("Automatically reads Cursor IDE credentials from macOS Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Log in to Cursor IDE first: open Cursor and sign in to your account")
                    .font(.caption)
                    .foregroundColor(.orange)

                if isExpanded {
                    Divider()
                    Button("Check Again") {
                        cursorService.checkAccess()
                        if cursorService.hasAccess {
                            Task {
                                await dataManager.refreshAll()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Claude Code Service Row (Local Files)

struct ClaudeCodeServiceRow: View {
    let hasAccess: Bool
    let metrics: UsageMetrics?

    @StateObject private var claudeCodeService = ClaudeCodeLocalService.shared
    @StateObject private var dataManager = UsageDataManager.shared
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: ServiceType.claudeCode.iconName)
                    .foregroundColor(headerColor)
                Text(ServiceType.claudeCode.displayName)
                    .font(.headline)
                Spacer()

                if hasAccess {
                    if let metrics = metrics {
                        StatusIndicator(status: metrics.overallStatus)
                    }

                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                } else {
                    Button(action: { isExpanded.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "gearshape")
                            Text(isExpanded ? "Close" : "Configure")
                        }
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if hasAccess, let metrics = metrics {
                Divider()

                if let sessionLimit = metrics.sessionLimit {
                    LimitRow(title: "Session (5h)", limit: sessionLimit)
                }

                if let weeklyLimit = metrics.weeklyLimit {
                    LimitRow(title: "All Models (7d)", limit: weeklyLimit)
                }

                if let sonnetLimit = metrics.codeReviewLimit {
                    LimitRow(title: "Sonnet (7d)", limit: sonnetLimit)
                }

                if let subscriptionType = claudeCodeService.subscriptionType {
                    HStack {
                        Text(subscriptionType.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                        Spacer()
                        Text("Updated: \(formatDate(metrics.lastUpdated))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Updated: \(formatDate(metrics.lastUpdated))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !hasAccess {
                Text("Log in to Claude Code CLI to enable")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button(action: {
                    claudeCodeService.checkAccess()
                    if claudeCodeService.hasAccess {
                        Task {
                            await dataManager.refreshAll()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check Again")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var headerColor: Color {
        if hasAccess, let metrics = metrics {
            return colorForStatus(metrics.overallStatus)
        }
        return .gray
    }

    private func colorForStatus(_ status: UsageStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Reusable Components

struct ServiceCard: View {
    let metrics: UsageMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: metrics.service.iconName)
                    .foregroundColor(colorForStatus(metrics.overallStatus))
                Text(metrics.service.displayName)
                    .font(.headline)
                Spacer()
                StatusIndicator(status: metrics.overallStatus)
            }

            Divider()

            if let sessionLimit = metrics.sessionLimit {
                LimitRow(title: "Session", limit: sessionLimit)
            }

            if let weeklyLimit = metrics.weeklyLimit {
                LimitRow(title: "Weekly", limit: weeklyLimit)
            }

            if let codeReviewLimit = metrics.codeReviewLimit {
                LimitRow(title: "Code Review", limit: codeReviewLimit)
            }

            Text("Updated: \(formatDate(metrics.lastUpdated))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func colorForStatus(_ status: UsageStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct LimitRow: View {
    let title: String
    let limit: UsageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(limit.percentage))%")
                    .font(.subheadline)
                    .bold()
            }

            ProgressView(value: limit.used, total: limit.total)
                .tint(colorForStatus(limit.statusColor))

            HStack {
                Text("\(formatNumber(limit.used)) / \(formatNumber(limit.total))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if let resetTime = limit.resetTime {
                    Text("Resets: \(formatResetTime(resetTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func colorForStatus(_ status: UsageStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    private func formatResetTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct StatusIndicator: View {
    let status: UsageStatus

    var body: some View {
        Circle()
            .fill(colorForStatus(status))
            .frame(width: 8, height: 8)
    }

    private func colorForStatus(_ status: UsageStatus) -> Color {
        switch status {
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
